//============================================================================
//  Savestate controller for the Nuked-MD core.
//
//  Save: wait for an idle cartridge bus, freeze md_core (ss_hold), rotate the
//  scan chain once around while copying it out, read every memory through the
//  ss_mem port, add the cartridge/mapper state, replay the RAM addresses
//  (ss_refresh) and write the header last, so Main_MiSTer only sees the
//  counter change once the slot is complete.
//  Load: check the header, freeze at an idle point, shift the chain in, write
//  the memories and the cartridge state back, refresh, release.
//
//  Slot layout in DDR3 (64-bit words):
//    0   {size in 32-bit words after word 0, save counter}  (read by Main_MiSTer)
//    1   {"MDSS", version, 16'd0}
//    2   {chain length, cartridge state bits}
//    3…  data words: scan chain (LSB first), memories in order, cartridge state
//============================================================================

module ss_ctrl
#(
	parameter [31:0] SS_BASE   = 32'h3E000000,
	parameter [31:0] SLOT_SIZE = 32'h00100000,
	parameter        CART_WORDS = 3
)
(
	input             clk,          // clk_md
	input             reset,

	input             save,         // pulse
	input             load,         // pulse
	input       [1:0] slot,
	input             allow,
	input             safe,         // the core may be frozen at the next clock edge

	output            busy,

	// md_core
	output reg        ss_hold,
	output reg        ss_shift,
	output            ss_in,
	input             ss_out,
	output reg        ss_refresh,
	output reg        ss_mem_act,
	output reg  [3:0] ss_mem_sel,
	output reg [15:0] ss_mem_addr,
	output reg        ss_mem_we,
	output reg [63:0] ss_mem_wdata,
	input      [63:0] ss_mem_rdata,

	// cartridge/mapper state, one 64-bit word at a time while held
	output reg  [3:0] cart_idx,
	input      [63:0] cart_rdata,
	output reg [63:0] cart_wdata,
	output reg        cart_we,

	// DDR3 word access (to ss_ddr, toggle handshake)
	output reg        ddr_req,
	input             ddr_ack,
	output reg        ddr_we,
	output reg [28:0] ddr_addr,
	output reg [63:0] ddr_wdata,
	input      [63:0] ddr_rdata
);

`include "md_core_ss.vh"

localparam CHAIN_WORDS = (SS_CHAIN_LEN + 63) / 64;
localparam NMEM = 9;

// memories behind ss_mem (select = index): VSRAM, SAT cache, sprite data, line buffer, CRAM,
// VRAM, 68k RAM, Z80 RAM (all in md_core) and the cartridge backup RAM (64 KB as 32K words
// through the save port, clk_sys, slower)
function [16:0] mem_cnt(input [3:0] i);
	case(i) 0: mem_cnt = 40; 1: mem_cnt = 80; 2: mem_cnt = 20; 3: mem_cnt = 40; 4: mem_cnt = 64;
	        5: mem_cnt = 65536; 6,8: mem_cnt = 32768; default: mem_cnt = 8192; endcase
endfunction
function [3:0] mem_epw(input [3:0] i);
	case(i) 5,7: mem_epw = 8; 6,8: mem_epw = 4; default: mem_epw = 1; endcase
endfunction

localparam [31:0] MEM_WORDS  = 40 + 80 + 20 + 40 + 64 + 65536/8 + 32768/4 + 8192/8 + 32768/4;
localparam [31:0] DATA_WORDS = 2 + CHAIN_WORDS + MEM_WORDS + CART_WORDS;   // after word 0
localparam [31:0] MAGIC   = "MDSS";
localparam [15:0] VERSION = 16'd1;
localparam [63:0] WORD1   = {MAGIC, VERSION, 16'd0};
localparam [63:0] WORD2   = SS_CHAIN_LEN * 64'h100000000 + CART_WORDS;

localparam S_IDLE = 0, S_HDR = 1, S_SAFE = 2, S_PRE = 3, S_CHAIN = 4, S_MEM = 5, S_CART = 6,
           S_POST = 7, S_REFRESH = 8, S_TAIL = 9, S_RELEASE = 10, S_DDR = 11;
localparam P_CHAIN = 0, P_MEM = 1, P_CART = 2;

reg  [3:0] state, ret_state;
reg  [1:0] phase;
reg        saving;
reg  [1:0] cur_slot;
reg [31:0] counter = 0;
reg [28:0] slot_base;
reg [28:0] ptr;            // next data word in DDR
reg [63:0] buf_w;          // word being assembled (save) or consumed (load)
reg [31:0] chain_left;     // chain bits still to shift
reg  [6:0] bit_cnt;
reg  [3:0] mem_i;
reg [16:0] ent;
reg  [3:0] ent_in_word;
reg  [2:0] step;
reg        ack_old;
reg        ss_in_r;

assign busy  = (state != S_IDLE);
assign ss_in = saving ? ss_out : ss_in_r;   // saving rotates the chain once around

wire [63:0] ent_val = (mem_epw(mem_i) == 8) ? {56'd0, buf_w[ent_in_word[2:0]*8 +: 8]} :
                      (mem_epw(mem_i) == 4) ? {48'd0, buf_w[ent_in_word[1:0]*16 +: 16]} : buf_w;

task ddr_rd(input [28:0] addr, input [3:0] ret);
begin
	ddr_we    <= 0;
	ddr_addr  <= addr;
	ddr_req   <= ~ddr_req;
	ret_state <= ret;
	state     <= S_DDR;
end
endtask

task ddr_wr(input [28:0] addr, input [63:0] data, input [3:0] ret);
begin
	ddr_we    <= 1;
	ddr_addr  <= addr;
	ddr_wdata <= data;
	ddr_req   <= ~ddr_req;
	ret_state <= ret;
	state     <= S_DDR;
end
endtask

always @(posedge clk) begin
	ack_old    <= ddr_ack;
	ss_shift   <= 0;
	ss_refresh <= 0;
	ss_mem_we  <= 0;
	cart_we    <= 0;

	if(reset) begin
		state      <= S_IDLE;
		ss_hold    <= 0;
		ss_mem_act <= 0;
	end
	else case(state)
		S_IDLE: begin
			ss_hold    <= 0;
			ss_mem_act <= 0;
			step       <= 0;
			saving     <= save;
			cur_slot   <= slot;
			slot_base  <= (SS_BASE >> 3) + slot * (SLOT_SIZE >> 3);
			if(allow & (save | load)) state <= save ? S_SAFE : S_HDR;
		end

		// load: only accept a slot written by this build (same layout and chain)
		S_HDR: begin
			step <= step + 1'd1;
			case(step)
				0: ddr_rd(slot_base, S_HDR);
				1: if(buf_w[63:32] != DATA_WORDS * 2) state <= S_IDLE; else ddr_rd(slot_base + 29'd1, S_HDR);
				2: if(buf_w != WORD1) state <= S_IDLE; else ddr_rd(slot_base + 29'd2, S_HDR);
				3: if(buf_w != WORD2) state <= S_IDLE; else state <= S_SAFE;
			endcase
		end

		S_SAFE: if(safe) begin
			ss_hold    <= 1;
			ptr        <= slot_base + 29'd3;
			phase      <= P_CHAIN;
			chain_left <= SS_CHAIN_LEN;
			mem_i      <= 0;
			ent        <= 0;
			cart_idx   <= 0;
			state      <= S_PRE;
		end

		// start of a data word: fetch it when loading
		S_PRE: begin
			bit_cnt     <= 0;
			ent_in_word <= 0;
			step        <= 0;
			case(phase)
				P_CHAIN: ret_state <= S_CHAIN;
				P_MEM:   ret_state <= S_MEM;
				default: ret_state <= S_CART;
			endcase
			if(saving) begin
				buf_w <= 0;
				state <= (phase == P_CHAIN) ? S_CHAIN : (phase == P_MEM) ? S_MEM : S_CART;
			end
			else ddr_rd(ptr, (phase == P_CHAIN) ? S_CHAIN : (phase == P_MEM) ? S_MEM : S_CART);
		end

		// up to 64 chain bits per word, one per clock. ss_shift is registered: bit n
		// shifts at the edge after the one that requested it, and is captured there.
		S_CHAIN: begin
			if(bit_cnt == 64 || !chain_left) begin
				if(~ss_shift) state <= S_POST;
			end
			else begin
				ss_shift   <= 1;
				ss_in_r    <= buf_w[bit_cnt[5:0]];
				bit_cnt    <= bit_cnt + 1'd1;
				chain_left <= chain_left - 1'd1;
			end
			if(saving & ss_shift) buf_w[bit_cnt[5:0] - 1'd1] <= ss_out;
		end

		// memory entries: address, wait, read or write (3 clocks each)
		S_MEM: begin
			ss_mem_act   <= 1;
			ss_mem_sel   <= mem_i;
			ss_mem_addr  <= ent[15:0];
			ss_mem_wdata <= ent_val;
			// the cartridge RAM runs on clk_sys: keep the write two clocks and wait longer
			step <= step + 1'd1;
			if(~saving && (step == 1 || (mem_i == 8 && step == 2))) ss_mem_we <= 1;
			if(step == ((mem_i == 8) ? 3'd7 : 3'd3)) begin
				step <= 0;
				if(saving) begin
					case(mem_epw(mem_i))
						8: buf_w[ent_in_word[2:0]*8 +: 8]   <= ss_mem_rdata[7:0];
						4: buf_w[ent_in_word[1:0]*16 +: 16] <= ss_mem_rdata[15:0];
						default: buf_w <= ss_mem_rdata;
					endcase
				end
				ent_in_word <= ent_in_word + 1'd1;
				if(ent + 1'd1 == mem_cnt(mem_i)) begin
					ent   <= 0;
					mem_i <= mem_i + 1'd1;
				end
				else ent <= ent + 1'd1;
				if(ent_in_word + 1'd1 == mem_epw(mem_i)) state <= S_POST;
			end
		end

		// cartridge registers live on clk_sys: two-clock write strobe
		S_CART: begin
			step <= step + 1'd1;
			cart_wdata <= buf_w;
			if(~saving && (step == 1 || step == 2)) cart_we <= 1;
			if(step == 3) begin
				if(saving) buf_w <= cart_rdata;
				state <= S_POST;
			end
		end

		// end of a data word: write it when saving, then move on
		S_POST: begin
			ss_mem_act <= 0;
			ptr <= ptr + 1'd1;
			case(phase)
				P_CHAIN: if(!chain_left) phase <= P_MEM;
				P_MEM:   if(mem_i == NMEM) phase <= P_CART;
				default: cart_idx <= cart_idx + 1'd1;
			endcase
			step <= 0;
			if(saving) ddr_wr(ptr, buf_w, ((phase == P_CART) && (cart_idx + 1'd1 == CART_WORDS)) ? S_TAIL : S_PRE);
			else state <= ((phase == P_CART) && (cart_idx + 1'd1 == CART_WORDS)) ? S_REFRESH : S_PRE;
		end

		// replay the RAM addresses on the last held clock (S_RELEASE), nothing may follow
		S_REFRESH: begin
			ss_refresh <= 1;
			state <= S_RELEASE;
		end

		// save: words 1 and 2, then word 0 with the new counter
		S_TAIL: begin
			step <= step + 1'd1;
			case(step)
				0: ddr_wr(slot_base + 29'd1, WORD1, S_TAIL);
				1: ddr_wr(slot_base + 29'd2, WORD2, S_TAIL);
				2: begin
						counter <= counter + 1'd1;
						ddr_wr(slot_base, {DATA_WORDS[30:0], 1'b0, counter + 1'd1}, S_TAIL);
					end
				default: state <= S_REFRESH;
			endcase
		end

		S_RELEASE: begin
			ss_hold <= 0;
			state   <= S_IDLE;
		end

		S_DDR: if(ack_old != ddr_ack) begin
			if(~ddr_we) buf_w <= ddr_rdata;
			state <= ret_state;
		end
	endcase
end

endmodule
