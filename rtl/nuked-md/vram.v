module vram
	(
	input MCLK,
	input RAS,
	input CAS,
	input WE,
	input OE,
	input SC,
	input SE,
	input [7:0] AD,
	input [7:0] RD_i,
	output reg [7:0] RD_o,
	// savestate
	input ss_hold,
	input ss_refresh,
	input ss_mem_en,
	input [15:0] ss_mem_addr,
	input ss_mem_we,
	input [7:0] ss_mem_wdata,
	output reg [7:0] ssx_vram_rdata,
	output RD_d,
	output [7:0] SD_o,
	output SD_d
	);
	
	reg [15:0] addr;
	reg dt;
	reg [7:0] addr_ser;
	reg [2047:0] ser;
	
	reg o_OE;
	reg o_RAS;
	reg o_cas;
	reg o_SC;
	reg o_valid;
	
	wire cas = ~RAS & ~CAS;
	wire wr = ~RAS & ~CAS & ~WE;
	wire rd = ~RAS & ~CAS & ~OE & ~dt;
	
	// savestate: the RAM blocks register their address internally, ss_row keeps a copy
	// so the read output can be rebuilt after a restore.
	reg [7:0] ss_row = 8'h0;
	// byte select of the read mux: a copy of addr[7:0] (loaded with it, and from it while
	// held, so it is right again after a restore) that takes the savestate address during
	// a memory access, so the read path has no savestate mux in it. Not scanned, but with
	// single-clock timing like the rest of the read path (ssy_, see scan_insert.py).
	reg [7:0] ssy_bsel = 8'h0;
	wire [7:0] slice_sel = ssy_bsel;
	
	wire [7:0] mem_addr = ss_mem_en ? ss_mem_addr[15:8] : ss_refresh ? ss_row : addr[15:8];
	wire [31:0] mem_be;
	wire [2047:0] mem_o;
	
	wire [7:0] slice_s[0:255];
	wire [7:0] slice_p[0:255];
	
	genvar i;
	generate
		for (i = 0; i < 32; i = i + 1)
		begin : l1
			assign mem_be[i] = (ss_mem_en ? ss_mem_addr[4:0] : addr[4:0]) == i;
		end
		for (i = 0; i < 8; i = i + 1)
		begin : l2
			vram_ip mem
				(
				.clock(MCLK),
				.address(mem_addr),
				.byteena(mem_be),
				.data({32{ss_mem_en ? ss_mem_wdata : RD_i}}),
				.wren(ss_mem_en ? (ss_mem_we & (ss_mem_addr[7:5] == i)) : (wr & ~ss_hold & (addr[7:5] == i))),
				.q(mem_o[(256*(i+1)-1):(256*i)])
				);
		end
		for (i = 0; i < 256; i = i + 1)
		begin : l3
			assign slice_p[i] = mem_o[(8*(i+1)-1):(8*i)];
			assign slice_s[i] = ser[(8*(i+1)-1):(8*i)]; 
		end
	endgenerate
	
	assign RD_d = ~o_valid;
	assign SD_d = SE;
	
	reg [7:0] vram_ser;
	
	assign SD_o = vram_ser;
	
	always @(posedge MCLK)
	begin
		if (ss_mem_en)
			ssy_bsel <= ss_mem_addr[7:0];
		else if (ss_hold)
			ssy_bsel <= addr[7:0];
		else if (~o_cas & cas)
			ssy_bsel <= AD;
		ssx_vram_rdata <= slice_p[slice_sel];
	end
	
	always @(posedge MCLK)
	begin
		ss_row <= mem_addr;
		if (dt & !o_OE & OE)
		begin
			addr_ser <= addr[7:0];
			ser <= mem_o;
		end
		else if (~o_SC & SC)
		begin
			addr_ser <= addr_ser + 8'h1;
			vram_ser <= slice_s[addr_ser];
		end
		if (o_RAS & ~RAS)
		begin
			dt <= ~OE;
			addr[15:8] <= AD;
		end
		if (~o_cas & cas)
		begin
			addr[7:0] <= AD;
		end
		if (dt & !o_OE & OE)
		begin
			addr_ser <= addr[7:0];
			ser <= mem_o;
		end
		
		if (rd)
		begin
			RD_o <= slice_p[slice_sel];
			o_valid <= 1'h1;
		end
		else if (CAS | OE)
		begin
			o_valid <= 1'h0;
		end
		
		o_OE <= OE;
		o_RAS <= RAS;
		o_cas <= cas;
		o_SC <= SC;
	end

endmodule
