// Everything that runs on clk_md and holds emulated machine state: the Nuked-MD board plus
// the external clock enables, bus-request pause and cheat data registers that used to live
// in MegaDrive.sv. The savestate scan chain is inserted into this module as a whole
// (see savestate/README.md), so any register added here is saved automatically.

module md_core
	(
	input MCLK2,

	// savestate
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

	input ext_reset,
	input reset_button,
	input clk_stop,     // stop the 68k/Z80 clocks (cartridge download)
	input pause_req,    // OSD pause, through bus requests
	input pause_allow,

	output [14:0] ram_68k_address,
	output [1:0] ram_68k_byteena,
	output [15:0] ram_68k_data,
	output ram_68k_wren,
	input [15:0] ram_68k_o,
	output [12:0] ram_z80_address,
	output [7:0] ram_z80_data,
	output ram_z80_wren,
	input [7:0] ram_z80_o,

	output [22:0] m68k_addr,
	output [15:0] m68k_bus_do,
	input [15:0] m68k_genie_data,
	output [15:0] z80_addr,
	output [7:0] z80_bus_do,
	input [7:0] z80_genie_data,

	input tmss_enable,
	input [15:0] tmss_data,
	output [9:0] tmss_address,

	input M3,
	output [22:0] cart_address,
	input [15:0] cart_data,
	input cart_data_en,
	output [15:0] cart_data_wr,
	output cart_cs,
	output cart_oe,
	output cart_lwr,
	output cart_uwr,
	output cart_time,
	input cart_m3_pause,
	output cart_dma,
	input ext_dtack,
	input pal,
	input jap,

	output [7:0] V_R, V_G, V_B,
	output V_HS,
	output vdp_vsync2,

	output [8:0] MOL, MOR,
	output [9:0] MOL_2612, MOR_2612,
	output [15:0] PSG,
	output fm_clk1,
	output fm_sel23,

	input [6:0] PA_i,
	output [6:0] PA_o,
	output [6:0] PA_d,
	input [6:0] PB_i,
	output [6:0] PB_o,
	output [6:0] PB_d,
	input [6:0] PC_i,
	output [6:0] PC_o,
	output [6:0] PC_d,

	output vdp_hclk1,
	output vdp_intfield,
	output vdp_de_h,
	output vdp_de_v,
	output vdp_m2,
	output vdp_m5,
	output vdp_rs1,
	input vdp_cramdot_dis,
	input ym2612_status_enable,

	output reg dma_68k_req,
	output reg dma_z80_req
	);

	wire VCLK, ZCLK;
	wire VCLK_next, ZCLK_next;
	wire dma_z80_ack;
	wire res_z80;

	reg vclk_en = 0, zclk_en = 0;
	reg vclk_r = 0, zclk_r = 0;
	always @(posedge MCLK2) begin
		// enables kept one clock ahead: the next clock value is then a 2-input AND of registers
		if(VCLK & ~VCLK_next) vclk_en <= ~clk_stop;
		if(ZCLK & ~ZCLK_next) zclk_en <= ~clk_stop;

		vclk_r <= VCLK_next & vclk_en;
		zclk_r <= ZCLK_next & zclk_en;
	end

	always @(posedge MCLK2) begin
		if(pause_req & pause_allow) begin
			dma_z80_req <= 1;
			if((dma_z80_ack | res_z80) & ~cart_dma) dma_68k_req <= 1;
		end
		else begin
			dma_68k_req <= 0;
			dma_z80_req <= 0;
		end
	end

	reg [15:0] m68k_data;
	reg  [7:0] z80_data;
	always @(posedge MCLK2) begin
		m68k_data <= m68k_genie_data;
		z80_data <= z80_genie_data;
	end

	md_board md_board
	(
		.MCLK2(MCLK2),

		.ss_hold(ss_hold),
		.ss_refresh(ss_refresh),
		.ss_mem_act(ss_mem_act),
		.ss_mem_sel(ss_mem_sel),
		.ss_mem_addr(ss_mem_addr),
		.ss_mem_we(ss_mem_we),
		.ss_mem_wdata(ss_mem_wdata),
		.ssx_rdata(ss_mem_rdata),

		.ext_reset(ext_reset),
		.reset_button(reset_button),
		.ext_vres(1'b0),
		.ext_zres(1'b0),

		.ram_68k_address(ram_68k_address),
		.ram_68k_byteena(ram_68k_byteena),
		.ram_68k_data(ram_68k_data),
		.ram_68k_wren(ram_68k_wren),
		.ram_68k_o(ram_68k_o),
		.ram_z80_address(ram_z80_address),
		.ram_z80_data(ram_z80_data),
		.ram_z80_wren(ram_z80_wren),
		.ram_z80_o(ram_z80_o),

		.m68k_addr(m68k_addr),
		.m68k_bus_do(m68k_bus_do),
		.m68k_di(m68k_data),
		.z80_addr(z80_addr),
		.z80_bus_do(z80_bus_do),
		.z80_di(z80_data),

		.tmss_enable(tmss_enable),
		.tmss_data(tmss_data),
		.tmss_address(tmss_address),

		.ext_VCLK_o(VCLK),
		.ext_ZCLK_o(ZCLK),
		.ext_VCLK_next(VCLK_next),
		.ext_ZCLK_next(ZCLK_next),
		.ext_VCLK_i(vclk_r),
		.ext_VCLK_i_next(VCLK_next & vclk_en),
		.ext_ZCLK_i(zclk_r),

		.M3(M3),
		.cart_address(cart_address),
		.cart_data(cart_data),
		.cart_data_en(cart_data_en),
		.cart_data_wr(cart_data_wr),
		.cart_cs(cart_cs),
		.vdp_dma_oe_early(cart_oe),
		.cart_lwr(cart_lwr),
		.cart_uwr(cart_uwr),
		.cart_time(cart_time),
		.cart_m3_pause(cart_m3_pause),
		.vdp_dma(cart_dma),
		.ext_dtack(ext_dtack),
		.pal(pal),
		.jap(jap),

		.V_R(V_R),
		.V_G(V_G),
		.V_B(V_B),
		.V_HS(V_HS),
		.vdp_vsync2(vdp_vsync2),

		.MOL(MOL),
		.MOR(MOR),
		.MOL_2612(MOL_2612),
		.MOR_2612(MOR_2612),
		.PSG(PSG),
		.fm_clk1(fm_clk1),
		.fm_sel23(fm_sel23),

		.PA_i(PA_i),
		.PA_o(PA_o),
		.PA_d(PA_d),
		.PB_i(PB_i),
		.PB_o(PB_o),
		.PB_d(PB_d),
		.PC_i(PC_i),
		.PC_o(PC_o),
		.PC_d(PC_d),

		.vdp_hclk1(vdp_hclk1),
		.vdp_intfield(vdp_intfield),
		.vdp_de_h(vdp_de_h),
		.vdp_de_v(vdp_de_v),
		.vdp_m2(vdp_m2),
		.vdp_m5(vdp_m5),
		.vdp_rs1(vdp_rs1),
		.vdp_cramdot_dis(vdp_cramdot_dis),
		.ym2612_status_enable(ym2612_status_enable),

		.dma_68k_req(dma_68k_req),
		.dma_z80_req(dma_z80_req),
		.dma_z80_ack(dma_z80_ack),
		.res_z80(res_z80)
	);

`ifdef SS_TEST_VARIANT
	// savestate converter test only: an extra register whose name sorts first, so every
	// other bit of the chain moves
	(* keep *) reg [7:0] aaa_ss_test_pad = 8'h5A;
	always @(posedge MCLK2) aaa_ss_test_pad <= aaa_ss_test_pad + 8'd1;
`endif

	// Without the scan chain (plain RTL simulation) the chain is just a wire.
	assign ss_out = ss_in;

endmodule
