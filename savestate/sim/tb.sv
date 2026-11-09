// Simulation top for the savestate tests: md_core (RTL or scan netlist) with the work RAMs,
// a cartridge that answers from a ROM image, and the savestate ports exposed to C++.

module tb
(
	input clk,
	input reset,

	input ss_hold,
	input ss_shift,
	input ss_in,
	output ss_out,
	input ss_refresh,
	input ss_mem_act,
	input [3:0] ss_mem_sel,
	input [15:0] ss_mem_addr,
	input ss_mem_we,
	input [63:0] ss_mem_wdata,
	output [63:0] ss_mem_rdata,

	output [7:0] V_R, V_G, V_B,
	output V_HS, V_VS,
	output vdp_hclk1, vdp_de_h, vdp_de_v,
	output [8:0] MOL, MOR,
	output [15:0] PSG,
	output cart_busy,
	output [22:0] dbg_m68k_addr,

	// savestate controller test: use_ctrl hands the ss ports to ss_ctrl
	input use_ctrl,
	input ctrl_save,
	input ctrl_load,
	input [1:0] ctrl_slot,
	output ctrl_busy,
	output ctrl_hold,
	output [4:0] dbg_cart,
	input ddr_busy_rnd   // random DDRAM_BUSY stalls
);

// clk_sys: half of clk, rising together with it
reg clk_sys = 0;
always @(posedge clk) clk_sys <= ~clk_sys;

wire        c_hold, c_shift, c_in, c_refresh, c_act, c_we;
wire  [3:0] c_sel;
wire [15:0] c_addr;
wire [63:0] c_wdata;
wire        core_hold   = use_ctrl ? c_hold    : ss_hold;
wire        core_shift  = use_ctrl ? c_shift   : ss_shift;
wire        core_in     = use_ctrl ? c_in      : ss_in;
wire        core_refresh= use_ctrl ? c_refresh : ss_refresh;
wire        core_act    = use_ctrl ? c_act     : ss_mem_act;
wire  [3:0] core_sel    = use_ctrl ? c_sel     : ss_mem_sel;
wire [15:0] core_addr   = use_ctrl ? c_addr    : ss_mem_addr;
wire        core_we     = use_ctrl ? c_we      : ss_mem_we;
wire [63:0] core_wdata  = use_ctrl ? c_wdata   : ss_mem_wdata;
assign ctrl_hold = c_hold;

// cartridge backup RAM model on clk_sys (select 8)
reg  [15:0] sram[0:65535] /*verilator public*/;
reg  [15:0] sram_a;
wire        ss_sram = core_act & (core_sel == 4'd8);
always @(posedge clk_sys) begin
	if(ss_sram & core_we) sram[core_addr] <= core_wdata[15:0];
	sram_a <= core_addr;
end

// cartridge registers model on clk_sys
reg  [63:0] cart_regs[0:2] /*verilator public*/;
wire  [3:0] cart_idx;
wire [63:0] cart_wdata;
wire        cart_we;
always @(posedge clk_sys) if(cart_we && cart_idx < 3) cart_regs[cart_idx] <= cart_wdata;

wire        ddr_req, ddr_ack, ddr_we;
wire [28:0] ddr_addr;
wire [63:0] ddr_wdata, ddr_rdata;
wire [63:0] core_rdata;

ss_ctrl ss_ctrl
(
	.clk(clk),
	.reset(reset),
	.save(ctrl_save),
	.load(ctrl_load),
	.slot(ctrl_slot),
	.allow(1'b1),
	.safe(~cart_busy),
	.busy(ctrl_busy),
	.ss_hold(c_hold),
	.ss_shift(c_shift),
	.ss_in(c_in),
	.ss_out(ss_out),
	.ss_refresh(c_refresh),
	.ss_mem_act(c_act),
	.ss_mem_sel(c_sel),
	.ss_mem_addr(c_addr),
	.ss_mem_we(c_we),
	.ss_mem_wdata(c_wdata),
	.ss_mem_rdata((c_sel == 4'd8) ? {48'd0, sram[sram_a]} : core_rdata),
	.cart_idx(cart_idx),
	.cart_rdata(cart_idx < 3 ? cart_regs[cart_idx] : 64'd0),
	.cart_wdata(cart_wdata),
	.cart_we(cart_we),
	.ddr_req(ddr_req),
	.ddr_ack(ddr_ack),
	.ddr_we(ddr_we),
	.ddr_addr(ddr_addr),
	.ddr_wdata(ddr_wdata),
	.ddr_rdata(ddr_rdata)
);

// DDR3 model: 4 slots of 1MB at 0x3E000000, random wait states
wire        D_BUSY = ddr_busy_rnd;
wire  [7:0] D_BURSTCNT;
wire [28:0] D_ADDR;
reg  [63:0] D_DOUT;
reg         D_DOUT_READY;
wire        D_RD, D_WE;
wire [63:0] D_DIN;
wire  [7:0] D_BE;
reg  [63:0] ddr[0:524287] /*verilator public*/;
reg   [3:0] rd_lat = 0;
reg  [18:0] rd_a;
always @(posedge clk_sys) begin
	D_DOUT_READY <= 0;
	if(~D_BUSY & D_WE) ddr[D_ADDR - 29'h7C00000] <= D_DIN;
	if(~D_BUSY & D_RD) begin rd_lat <= 5; rd_a <= D_ADDR - 29'h7C00000; end
	if(rd_lat) begin
		rd_lat <= rd_lat - 1'd1;
		if(rd_lat == 1) begin D_DOUT <= ddr[rd_a]; D_DOUT_READY <= 1; end
	end
end

ss_ddr ss_ddr
(
	.clk(clk_sys),
	.ss_busy(ctrl_busy),
	.ss_req(ddr_req),
	.ss_ack(ddr_ack),
	.ss_we(ddr_we),
	.ss_addr(ddr_addr),
	.ss_wdata(ddr_wdata),
	.ss_rdata(ddr_rdata),
	.a_BUSY(),
	.a_BURSTCNT(8'd1),
	.a_ADDR(29'd0),
	.a_DOUT(),
	.a_DOUT_READY(),
	.a_RD(1'b0),
	.a_DIN(64'd0),
	.a_BE(8'd0),
	.a_WE(1'b0),
	.DDRAM_BUSY(D_BUSY),
	.DDRAM_BURSTCNT(D_BURSTCNT),
	.DDRAM_ADDR(D_ADDR),
	.DDRAM_DOUT(D_DOUT),
	.DDRAM_DOUT_READY(D_DOUT_READY),
	.DDRAM_RD(D_RD),
	.DDRAM_DIN(D_DIN),
	.DDRAM_BE(D_BE),
	.DDRAM_WE(D_WE)
);

assign ss_mem_rdata = core_rdata;

wire [14:0] ram_68k_address;
wire  [1:0] ram_68k_byteena;
wire [15:0] ram_68k_data;
wire        ram_68k_wren;
reg  [15:0] ram_68k[0:32767] /*verilator public*/;
reg  [14:0] ram_68k_a;
always @(posedge clk) begin
	if(ram_68k_wren & ram_68k_byteena[0]) ram_68k[ram_68k_address][7:0]  <= ram_68k_data[7:0];
	if(ram_68k_wren & ram_68k_byteena[1]) ram_68k[ram_68k_address][15:8] <= ram_68k_data[15:8];
	ram_68k_a <= ram_68k_address;
end

wire [12:0] ram_z80_address;
wire  [7:0] ram_z80_data;
wire        ram_z80_wren;
reg   [7:0] ram_z80[0:8191] /*verilator public*/;
reg  [12:0] ram_z80_a;
always @(posedge clk) begin
	if(ram_z80_wren) ram_z80[ram_z80_address] <= ram_z80_data;
	ram_z80_a <= ram_z80_address;
end

reg [15:0] rom[0:65535];
initial $readmemh("testrom.hex", rom);

wire [22:0] cart_address;
wire        cart_cs, cart_oe, cart_lwr, cart_uwr, cart_time, cart_dma;
wire [15:0] m68k_bus_do;
wire  [7:0] z80_bus_do;
wire  [6:0] PC_o, PC_d;

assign cart_busy = cart_cs | cart_oe | cart_lwr | cart_uwr | cart_time;
assign dbg_cart = {cart_cs, cart_oe, cart_lwr, cart_uwr, cart_time};

`ifndef MD_CORE
`define MD_CORE md_core
`endif
`MD_CORE md_core
(
	.MCLK2(clk),

	.ss_hold(core_hold),
	.ss_shift(core_shift),
	.ss_in(core_in),
	.ss_out(ss_out),
	.ss_refresh(core_refresh),
	.ss_mem_act(core_act),
	.ss_mem_sel(core_sel),
	.ss_mem_addr(core_addr),
	.ss_mem_we(core_we),
	.ss_mem_wdata(core_wdata),
	.ss_mem_rdata(core_rdata),

	.ext_reset(reset),
	.reset_button(1'b0),
	.clk_stop(1'b0),
	.pause_req(1'b0),
	.pause_allow(1'b1),

	.ram_68k_address(ram_68k_address),
	.ram_68k_byteena(ram_68k_byteena),
	.ram_68k_data(ram_68k_data),
	.ram_68k_wren(ram_68k_wren),
	.ram_68k_o(ram_68k[ram_68k_a]),
	.ram_z80_address(ram_z80_address),
	.ram_z80_data(ram_z80_data),
	.ram_z80_wren(ram_z80_wren),
	.ram_z80_o(ram_z80[ram_z80_a]),

	.m68k_addr(dbg_m68k_addr),
	.m68k_bus_do(m68k_bus_do),
	.m68k_genie_data(m68k_bus_do),
	.z80_addr(),
	.z80_bus_do(z80_bus_do),
	.z80_genie_data(z80_bus_do),

	.tmss_enable(1'b0),
	.tmss_data(16'h0),
	.tmss_address(),

	.M3(1'b1),
	.cart_address(cart_address),
	.cart_data(rom[cart_address[15:0]]),
	.cart_data_en(cart_oe & cart_cs),
	.cart_data_wr(),
	.cart_cs(cart_cs),
	.cart_oe(cart_oe),
	.cart_lwr(cart_lwr),
	.cart_uwr(cart_uwr),
	.cart_time(cart_time),
	.cart_m3_pause(1'b0),
	.cart_dma(cart_dma),
	.ext_dtack(1'b0),
	.pal(1'b0),
	.jap(1'b0),

	.V_R(V_R),
	.V_G(V_G),
	.V_B(V_B),
	.V_HS(V_HS),
	.vdp_vsync2(V_VS),

	.MOL(MOL),
	.MOR(MOR),
	.MOL_2612(),
	.MOR_2612(),
	.PSG(PSG),
	.fm_clk1(),
	.fm_sel23(),

	.PA_i(7'h7F),
	.PA_o(),
	.PA_d(),
	.PB_i(7'h7F),
	.PB_o(),
	.PB_d(),
	.PC_i(PC_d | PC_o),
	.PC_o(PC_o),
	.PC_d(PC_d),

	.vdp_hclk1(vdp_hclk1),
	.vdp_intfield(),
	.vdp_de_h(vdp_de_h),
	.vdp_de_v(vdp_de_v),
	.vdp_m2(),
	.vdp_m5(),
	.vdp_rs1(),
	.vdp_cramdot_dis(1'b1),
	.ym2612_status_enable(1'b0),

	.dma_68k_req(),
	.dma_z80_req()
);

endmodule
