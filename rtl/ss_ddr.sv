// DDR3 port sharing for the savestates: single 64-bit word accesses requested from the
// clk_md domain (toggle handshake) and the MD+ CD audio reader, which keeps the port
// whenever it has a read in flight.

module ss_ddr
(
	input             clk,          // DDRAM_CLK (clk_sys)

	// savestate controller (other clock domain, toggle handshake)
	input             ss_busy,      // controller wants the port
	input             ss_req,
	output reg        ss_ack = 0,
	input             ss_we,
	input      [28:0] ss_addr,
	input      [63:0] ss_wdata,
	output reg [63:0] ss_rdata,

	// MD+ audio reader
	output            a_BUSY,
	input       [7:0] a_BURSTCNT,
	input      [28:0] a_ADDR,
	output     [63:0] a_DOUT,
	output            a_DOUT_READY,
	input             a_RD,
	input      [63:0] a_DIN,
	input       [7:0] a_BE,
	input             a_WE,

	// DDR3
	input             DDRAM_BUSY,
	output      [7:0] DDRAM_BURSTCNT,
	output     [28:0] DDRAM_ADDR,
	input      [63:0] DDRAM_DOUT,
	input             DDRAM_DOUT_READY,
	output            DDRAM_RD,
	output     [63:0] DDRAM_DIN,
	output      [7:0] DDRAM_BE,
	output            DDRAM_WE
);

reg  [1:0] busy_s, req_s;
reg        own = 0;         // the savestate side owns the port
reg        a_pending = 0;   // audio read issued, data not back yet
reg        rd = 0, we = 0;
reg [28:0] addr;
reg [63:0] din;
reg        wait_data = 0;

always @(posedge clk) begin
	busy_s <= {busy_s[0], ss_busy};
	req_s  <= {req_s[0], ss_req};

	if(~own) begin
		if(a_RD & ~DDRAM_BUSY) a_pending <= 1;
		if(DDRAM_DOUT_READY)   a_pending <= 0;
		if(busy_s[1] & ~a_pending & ~a_RD & ~a_WE) own <= 1;
	end
	else begin
		if(~DDRAM_BUSY) begin
			rd <= 0;
			we <= 0;
			if(we) ss_ack <= ~ss_ack;
		end
		if(wait_data & DDRAM_DOUT_READY) begin
			wait_data <= 0;
			ss_rdata  <= DDRAM_DOUT;
			ss_ack    <= ~ss_ack;
		end
		if(~rd & ~we & ~wait_data & (req_s[1] != req_s[0] ? 1'b0 : 1'b1) & (req_s[1] != ss_ack)) begin
			addr <= ss_addr;
			din  <= ss_wdata;
			if(ss_we) we <= 1;
			else begin
				rd <= 1;
				wait_data <= 1;
			end
		end
		if(~busy_s[1] & ~rd & ~we & ~wait_data & (req_s[1] == ss_ack)) own <= 0;
	end
end

assign DDRAM_BURSTCNT = own ? 8'd1 : a_BURSTCNT;
assign DDRAM_ADDR     = own ? addr : a_ADDR;
assign DDRAM_RD       = own ? rd   : a_RD;
assign DDRAM_WE       = own ? we   : a_WE;
assign DDRAM_DIN      = own ? din  : a_DIN;
assign DDRAM_BE       = own ? 8'hFF : a_BE;

assign a_BUSY       = own | DDRAM_BUSY;
assign a_DOUT       = DDRAM_DOUT;
assign a_DOUT_READY = ~own & DDRAM_DOUT_READY;

endmodule
