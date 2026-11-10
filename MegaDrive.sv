//============================================================================
//  HAL for NukedMD-FPGA
//  Copyright (c) 2023 Alexey Melnikov
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign BUTTONS   = osd_btn;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
// DDRAM driven by mdp_audio for CDDA PCM streaming

assign LED_DISK  = 0;
assign LED_POWER = 0;

// MD+ debug: sticky latch — LED stays on after first MD+ command received
reg mdp_cmd_seen;
always @(posedge clk_sys) begin
	if (sys_reset)
		mdp_cmd_seen <= 0;
	else if (mdp_track_request | mdp_stop_request | mdp_resume_request)
		mdp_cmd_seen <= 1;
end

assign LED_USER  = cart_download | sav_pending | mdp_cmd_seen;

assign VGA_SCALER= 0;
assign VGA_DISABLE = 0;

assign AUDIO_S   = 1;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

wire  [1:0] ar = status[49:48];

wire       vcrop_en = status[34];
wire [3:0] vcopt    = status[53:50];
reg        en216p;
reg  [4:0] voff;
always @(posedge CLK_VIDEO) begin
	en216p <= ((HDMI_WIDTH == 1920) && (HDMI_HEIGHT == 1080) && !forced_scandoubler && !scale);
	voff <= (vcopt < 6) ? {vcopt,1'b0} : ({vcopt,1'b0} - 5'd24);
end

wire vga_de;
video_freak video_freak
(
	.*,
	.VGA_DE_IN(vga_de),
	.ARX((!ar) ? arx : (ar - 1'd1)),
	.ARY((!ar) ? ary : 12'd0),
	.CROP_SIZE((en216p & vcrop_en) ? 10'd216 : 10'd0),
	.CROP_OFF(voff),
	.SCALE(status[55:54])
);

`include "build_id.v"
localparam CONF_STR = {
	"MegaDrive;SS3E000000:100000,UART31250,MIDI;",
	"FS1,BINGENMD ;",
	"FS2,SMS;",
	"-;",
	"O[7:6],Region,JP,US,EU;",
	"O[9:8],Auto Region,Header,File Ext,Disabled;",
	"D2O[28:27],Priority,US>EU>JP,EU>US>JP,US>JP>EU,JP>US>EU;",
	"d7O[12],TMSS,Disabled,Enabled;",
	
	"-;",
	"C,Cheats;",
	"H1O[24],Cheats Enabled,Yes,No;",
	"-;",
	"O[13],Autosave,Off,On;",
	"H6D0R[16],Load Backup RAM;",
	"H6D0R[17],Save Backup RAM;",
	"-;",
	"O[65:64],Savestate Slot,1,2,3,4;",
	"R[66],Save state;",
	"R[67],Restore state;",
	"-;",

	"P1,Audio & Video;",
	"P1O[49:48],Aspect Ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O[3:1],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"d5P1O[34],Vertical Crop,Disabled,216p(5x);",
	"d5P1O[53:50],Crop Offset,0,2,4,8,10,12,-12,-10,-8,-6,-4,-2;",
	"P1O[55:54],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P1-;",
	"P1O[30],320x224 Aspect,Original,Corrected;",
	"P1O[29],Border,No,Yes;",
	"P1O[46],Composite Blend,Off,On;",
	"P1O[10],CRAM Dots,Off,On;",
	"P1-;",
	"P1O[15:14],Audio Filter,Model 1,Model 2,Minimal,No Filter;",
	"P1O[11],FM Chip,YM2612,YM3438;",
	"P1O[60],SMS FM Chip,Enabled,Disabled;",
	"P1O[58:57],Stereo Mix,None,25%,50%,100%;",

	"P2,Input;",
	"P2-;",
	"P2O[4],Swap Joysticks,No,Yes;",
	"P2O[5],6 Buttons Mode,No,Yes;",
	"P2O[39:37],Multitap,Disabled,4-Way,TeamPlayer: Port1,TeamPlayer: Port2,J-Cart;",
	"P2-;",
	"P2O[19:18],Mouse,None,Port1,Port2;",
	"P2O[20],Mouse Flip Y,No,Yes;",
	"P2-;",
	"P2O[22:21],Keyboard,None,Port1,Port2;",
	"P2-;",
	"P2O[41:40],Gun Control,Disabled,Joy1,Joy2,Mouse;",
	"D4P2O[42],Gun Fire,Joy,Mouse;",
	"D4P2O[44:43],Cross,Small,Medium,Big,None;",
	"P2-;",
	"P2O[63:62],SNAC,Off,Port 1,Port 2,Port 3;",

	"-;",
	"O[61],Pause When OSD is Open,No,Yes;",
	"R[0],Reset;",
	"J1,A,B,C,Start,Mode,X,Y,Z,Savestates;",
	"jn,A,B,R,Start,Select,X,Y,L;", // name map to SNES layout.
	"jp,Y,B,A,Start,Select,L,X,R;", // positional map to SNES layout (3 button friendly)
	"I,",
	",",
	",",
	",",
	",",
	"Slot=DPAD|Save/Load=Start+DPAD,",
	"Active Slot 1,",
	"Active Slot 2,",
	"Active Slot 3,",
	"Active Slot 4,",
	"Save to state 1,",
	"Restore state 1,",
	"Save to state 2,",
	"Restore state 2,",
	"Save to state 3,",
	"Restore state 3,",
	"Save to state 4,",
	"Restore state 4;",
	"V,v",`BUILD_DATE
};

///////////////////////////////////////////////////

wire clk_53m, clk_107m, clk_53m_v, pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_53m),
	.outclk_1(clk_107m),
	.outclk_2(clk_53m_v),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(pll_locked)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg  [31:0] cfg_data;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

always @(posedge CLK_50M) begin
	reg pald = 0, pald2 = 0;
	reg [2:0] state = 0;
	reg pal_r;

	pald <= PAL;
	pald2 <= pald;

	cfg_write <= 0;
	if(pald2 == pald && pald2 != pal_r) begin
		state <= 1;
		pal_r <= pald2;
	end

	if(!cfg_waitrequest) begin
		if(state) state<=state+1'd1;
		case(state)
			1: begin
					cfg_address <= 0;
					cfg_data <= 0;
					cfg_write <= 1;
				end
			5: begin
					cfg_address <= 7;
					cfg_data <= pal_r ? 2201376125 : 2537930535;
					cfg_write <= 1;
				end
			7: begin
					cfg_address <= 2;
					cfg_data <= 0;
					cfg_write <= 1;
				end
		endcase
	end
end

wire clk_sys     = clk_53m;
wire clk_ram     = clk_107m;
wire clk_md      = clk_107m;
assign CLK_VIDEO = clk_53m_v;

///////////////////////////////////////////////////

wire[127:0] status;
wire  [1:0] buttons;
wire [12:0] joystick_0,joystick_1,joystick_2,joystick_3,joystick_4;
wire  [7:0] joy0_x,joy0_y,joy1_x,joy1_y;
wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_data;
wire  [7:0] ioctl_index;
wire        ioctl_wait;

reg  [31:0] sd_lba;
reg         sd_rd = 0;
reg         sd_wr = 0;
wire        sd_ack;
wire  [7:0] sd_buff_addr;
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire        img_readonly;
wire [63:0] img_size;

wire        forced_scandoubler;
wire [10:0] ps2_key;
wire [2:0]  ps2_kbd_led_status;
wire [2:0]  ps2_kbd_led_use = 3'b111;
wire [24:0] ps2_mouse;

wire [21:0] gamma_bus;
wire [15:0] sdram_sz;

wire [35:0] EXT_BUS;

hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_2(joystick_2),
	.joystick_3(joystick_3),
	.joystick_4(joystick_4),
	.joystick_l_analog_0({joy0_y, joy0_x}),
	.joystick_l_analog_1({joy1_y, joy1_x}),

	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),
	.new_vmode(new_vmode),

	.status(status),
	.status_in({status[127:66],ss_slot,status[63:8],region_set ? region_req : status[7:6],status[5:0]}),
	.status_set(region_set | ss_status_update),
	.status_menumask({tmss_loaded,status[13],en216p,!gun_mode,1'b0,status[8],~gg_available,~bk_ena}),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),
	.ioctl_wait(ioctl_wait),

	.sd_lba('{sd_lba}),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din('{sd_buff_din}),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),

	.gamma_bus(gamma_bus),
	.sdram_sz(sdram_sz),

	.info_req(ss_info_req),
	.info(ss_info),

	.ps2_key(ps2_key),
	.ps2_kbd_led_status(ps2_kbd_led_status),
	.ps2_kbd_led_use(ps2_kbd_led_use),
	.ps2_mouse(ps2_mouse),

	.EXT_BUS(EXT_BUS)
);

wire [1:0] gun_mode = status[41:40];
wire       gun_btn_mode = status[42];

wire cart_download = ioctl_download & (ioctl_index[4:0] == 1 || ioctl_index[4:0] == 2);
wire code_download = ioctl_download & &ioctl_index;
wire tmss_download = ioctl_download & !ioctl_index;

reg cart_ms;
always @(posedge clk_sys) begin
	reg old_download;
	
	old_download <= cart_download;
	if(~old_download & cart_download) begin
		if(ioctl_index[4:0] == 2) cart_ms <= 1;
		if(ioctl_index[4:0] == 1) cart_ms <= 0;
	end
end

reg osd_btn = 0;
always @(posedge clk_sys) begin
	integer timeout = 0;
	reg     has_bootrom = 0;
	reg     last_rst = 0;

	if (RESET) last_rst <= 0;
	if (status[0]) last_rst <= 1;

	if (cart_download & ioctl_wr & status[0]) has_bootrom <= 1;

	if(last_rst & ~status[0]) begin
		osd_btn <= 0;
		if(timeout < 24000000) begin
			timeout <= timeout + 1;
			osd_btn <= ~has_bootrom;
		end
	end
end

///////////////////////////////////////////////////

wire reset   = status[0] | buttons[1] | region_set_rst;
wire loading = cart_download | bk_loading | RESET;

reg        btn_reset;
reg        md_reset;
reg        s_reset;
reg [15:1] ram_rst_a;
always @(posedge clk_md) begin
	reg [4:0] cnt = 0;
	reg old_reset = 0;
	
	ram_rst_a <= ram_rst_a + 1'd1;
	if(&ram_rst_a & ~&cnt) cnt <= cnt + 1'd1;

	old_reset <= reset;
	if(loading | (~old_reset & reset)) cnt <= 0;

	s_reset <= (cnt < 3);
	
	if(loading)       md_reset <= 1;
	else if(cnt == 3) md_reset <= 0;

	if(~old_reset & reset) btn_reset <= 1;
	else if(&cnt)          btn_reset <= 0;
end

reg sys_reset;
always @(posedge clk_sys) begin
	reg [1:0] sreset;
	
	sreset <= {sreset[0], s_reset};
	if(!sreset) sys_reset <= 0;
	if(&sreset) sys_reset <= 1;
end

reg clk_en;
reg pause_req;
always @(posedge clk_md) begin
	clk_en <= ~cart_download;
	pause_req <= OSD_STATUS & status[61];
end

// savestate signals (logic at the end of the file)
wire        ss_hold, ss_shift, ss_sel, ss_in, ss_out, ss_refresh;
wire        ss_mem_act, ss_mem_we;
wire  [3:0] ss_mem_sel;
wire [15:0] ss_mem_addr;
wire [63:0] ss_mem_wdata, ss_core_rdata;
wire        ss_sram = ss_mem_act & (ss_mem_sel == 4'd8);
wire  [3:0] ss_cart_idx;
wire [63:0] ss_cart_rdata, ss_cart_wdata;
wire        ss_cart_we;
wire        cart_ss_busy;
wire        svp_or_pier;
wire  [1:0] ss_slot;
wire  [7:0] ss_info;
wire        ss_info_req, ss_status_update;

///////////////////////////////////////////////////

wire        PAL = status[7];
wire        JAP = !status[7:6];

wire [23:1] cart_addr;
wire        cart_cs, cart_oe, cart_lwr, cart_uwr, cart_time, cart_dma;
wire [15:0] cart_data_wr;

// Cartridge module outputs (before MD+ overlay mux)
wire [15:0] cart_data_rom;
wire        cart_data_en_rom;
wire        cart_dtack_rom;

// MD+ overlay outputs
wire        mdp_data_en;
wire [15:0] mdp_data_out;
wire        mdp_dtack;
wire        mdp_active;
wire [15:0] mdp_last_cmd;
wire        mdp_track_request;
wire  [7:0] mdp_track_num;
wire        mdp_track_loop;
wire        mdp_stop_request;
wire  [7:0] mdp_fade_sectors;
wire        mdp_resume_request;
wire  [7:0] mdp_volume;
wire        mdp_volume_request;

// Muxed cart signals: MD+ overlay takes priority when active
wire [15:0] cart_data    = mdp_data_en ? mdp_data_out : cart_data_rom;
wire        cart_data_en = mdp_data_en | cart_data_en_rom;
wire        cart_dtack   = mdp_dtack   | cart_dtack_rom;

wire        vdp_hclk1;
wire        vdp_de_h;
wire        vdp_de_v;
wire        vdp_intfield;
wire        vdp_m2, vdp_m5, vdp_rs1;
wire  [7:0] r,g,b;
wire        hs, vs;

wire  [6:0] PA_d, PA_o, PB_d, PB_o, PC_d, PC_o;
wire  [6:0] PA_i, PB_i, PC_i;

wire  [8:0] MOL, MOR;
wire  [9:0] MOL_2612, MOR_2612;
wire [15:0] PSG;
wire        fm_clk1;
wire        fm_sel23;

wire [14:0] ram_68k_address;
wire  [1:0] ram_68k_byteena;
wire [15:0] ram_68k_data;
wire        ram_68k_wren;
wire [15:0] ram_68k_o;
wire [12:0] ram_z80_address;
wire  [7:0] ram_z80_data;
wire        ram_z80_wren;
wire  [7:0] ram_z80_o;
wire [15:0] tmss_data;
wire  [9:0] tmss_address;

wire [23:1] m68k_addr;
wire [15:0] m68k_bus_do;
wire [15:0] z80_addr;
wire  [7:0] z80_bus_do;

wire        dma_z80_req;

wire        core_cart_cs, core_cart_oe, core_cart_lwr, core_cart_uwr, core_cart_time, core_cart_dma;
wire  [6:0] core_PA_d, core_PA_o, core_PB_d, core_PB_o, core_PC_d, core_PC_o;

// while a savestate holds the core its outputs are meaningless: keep the cartridge bus idle
// and the pad lines at their last value
assign cart_cs   = core_cart_cs   & ~ss_hold;
assign cart_oe   = core_cart_oe   & ~ss_hold;
assign cart_lwr  = core_cart_lwr  & ~ss_hold;
assign cart_uwr  = core_cart_uwr  & ~ss_hold;
assign cart_time = core_cart_time & ~ss_hold;
assign cart_dma  = core_cart_dma  & ~ss_hold;

reg [6:0] PA_d_r, PA_o_r, PB_d_r, PB_o_r, PC_d_r, PC_o_r;
always @(posedge clk_md) if(~ss_hold) {PA_d_r, PA_o_r, PB_d_r, PB_o_r, PC_d_r, PC_o_r} <= {core_PA_d, core_PA_o, core_PB_d, core_PB_o, core_PC_d, core_PC_o};
assign {PA_d, PA_o, PB_d, PB_o, PC_d, PC_o} = ss_hold ? {PA_d_r, PA_o_r, PB_d_r, PB_o_r, PC_d_r, PC_o_r} :
                                                        {core_PA_d, core_PA_o, core_PB_d, core_PB_o, core_PC_d, core_PC_o};

// Nuked-MD board and its clk_md glue, flattened with the savestate scan chain
// (rtl/md_core_ss.v, generated from rtl/md_core.v by savestate/gen_netlist.sh)
md_core md_core
(
	.MCLK2(clk_md),

	.ss_hold(ss_hold),
	.ss_shift(ss_shift),
	.ss_sel(ss_sel),
	.ss_in(ss_in),
	.ss_out(ss_out),
	.ss_refresh(ss_refresh),
	.ss_mem_act(ss_mem_act),
	.ss_mem_sel(ss_mem_sel),
	.ss_mem_addr(ss_mem_addr),
	.ss_mem_we(ss_mem_we),
	.ss_mem_wdata(ss_mem_wdata),
	.ss_mem_rdata(ss_core_rdata),

	.ext_reset(md_reset),
	.reset_button(btn_reset), // edge triggered, requires some activity time to get detected.
	.clk_stop(cart_download),
	.pause_req(pause_req),
	.pause_allow(~md_reset & ~btn_reset & ~cart_download),

	// ram
	.ram_68k_address(ram_68k_address),
	.ram_68k_byteena(ram_68k_byteena),
	.ram_68k_data(ram_68k_data),
	.ram_68k_wren(ram_68k_wren),
	.ram_68k_o(ram_68k_o),
	.ram_z80_address(ram_z80_address),
	.ram_z80_data(ram_z80_data),
	.ram_z80_wren(ram_z80_wren),
	.ram_z80_o(ram_z80_o),

	// cheat engine
	.m68k_addr(m68k_addr),
	.m68k_bus_do(m68k_bus_do),
	.m68k_genie_data(m68k_genie_data),
	.z80_addr(z80_addr),
	.z80_bus_do(z80_bus_do),
	.z80_genie_data(z80_genie_data),

	.tmss_enable(tmss_enable & tmss_loaded),
	.tmss_data(tmss_data),
	.tmss_address(tmss_address),

	// cart
	.M3(~cart_ms),
	.cart_address(cart_addr),
	.cart_data(cart_data),
	.cart_data_en(cart_data_en),
	.cart_data_wr(cart_data_wr),
	.cart_cs(core_cart_cs),
	.cart_oe(core_cart_oe),
	.cart_lwr(core_cart_lwr),
	.cart_uwr(core_cart_uwr),
	.cart_time(core_cart_time),
	.cart_m3_pause(joystick_0[7] | joystick_1[7] | joystick_2[7] | joystick_3[7] | joystick_4[7]),
	.cart_dma(core_cart_dma),
	.ext_dtack(cart_dtack),
	.pal(PAL),
	.jap(JAP),

	// video
	.V_R(r),
	.V_G(g),
	.V_B(b),
	.V_HS(hs),
	.vdp_vsync2(vs),

	// audio
	.MOL(MOL),
	.MOR(MOR),
	.MOL_2612(MOL_2612),
	.MOR_2612(MOR_2612),
	.PSG(PSG),
	.fm_clk1(fm_clk1),
	.fm_sel23(fm_sel23),

	// pads
	.PA_i(PA_i),
	.PA_o(core_PA_o),
	.PA_d(core_PA_d), // 1 - input, 0 - output
	.PB_i(PB_i),
	.PB_o(core_PB_o),
	.PB_d(core_PB_d),
	.PC_i(PC_i),
	.PC_o(core_PC_o),
	.PC_d(core_PC_d),

	// helpers
	.vdp_hclk1(vdp_hclk1),
	.vdp_intfield(vdp_intfield),
	.vdp_de_h(vdp_de_h),
	.vdp_de_v(vdp_de_v),
	.vdp_m2(vdp_m2),
	.vdp_m5(vdp_m5),
	.vdp_rs1(vdp_rs1),
	.vdp_cramdot_dis(~status[10]),
	.ym2612_status_enable(ym2612_quirk),

	.dma_68k_req(),
	.dma_z80_req(dma_z80_req)
);

dpram #(15,16) ram_68k
(
	.clock(clk_md),

	.address_a(ram_68k_address),
	.data_a(ram_68k_data),
	.wren_a(ram_68k_wren),
	.byteena_a(ram_68k_byteena),
	.q_a(ram_68k_o),

	.address_b(ram_rst_a),
	.wren_b(md_reset)
);

dpram #(13,8) ram_z80k
(
	.clock(clk_md),

	.address_a(ram_z80_address),
	.data_a(ram_z80_data),
	.wren_a(ram_z80_wren),
	.q_a(ram_z80_o),

	.address_b(ram_rst_a),
	.wren_b(md_reset),
	.data_b(8'hC7) // reset instruction to fix Titan 2 bug
);

dpram_difclk #(10,16,10,16) rom_tmss
(
	.clock_a(clk_md),
	.address_a(tmss_address),
	.q_a(tmss_data),

	.clock_b(clk_sys),
	.address_b(ioctl_addr[10:1]),
	.wren_b(ioctl_wr && tmss_download && !ioctl_addr[24:11]),
	.data_b({ioctl_data[7:0],ioctl_data[15:8]})
);

reg tmss_enable = 0;
reg tmss_loaded = 0;
always @(posedge clk_sys) begin
	if(ioctl_wr & tmss_download) tmss_loaded <= 1;
	if(sys_reset) tmss_enable <= status[12];
end

wire [13:0] sms_fm_audio;
wire        gun_type;
wire  [7:0] gun_sensor_delay;
wire        ym2612_quirk;

cartridge cartridge
(
	.clk(clk_sys),
	.clk_ram(clk_ram),
	.reset(sys_reset),
	.reset_sdram(~pll_locked),

	.SDRAM_CLK(SDRAM_CLK),
	.SDRAM_CKE(SDRAM_CKE),
	.SDRAM_A(SDRAM_A),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_DQ(SDRAM_DQ),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nWE(SDRAM_nWE),
	
	.cart_dl(cart_download),
	.cart_dl_addr(ioctl_addr),
	.cart_dl_data(ioctl_data),
	.cart_dl_wr(ioctl_wr),
	.cart_dl_wait(ioctl_wait),

	.cart_ms(cart_ms),
	.cart_addr(cart_addr),
	.cart_data(cart_data_rom),
	.cart_data_en(cart_data_en_rom),
	.cart_data_wr(cart_data_wr),
	.cart_cs(cart_cs),
	.cart_oe(cart_oe),
	.cart_lwr(cart_lwr),
	.cart_uwr(cart_uwr),
	.cart_time(cart_time),
	.cart_dtack(cart_dtack_rom),
	.cart_dma(cart_dma),

	.save_addr(ss_sram ? ss_mem_addr : {sd_lba[6:0],sd_buff_addr}),
	.save_di(ss_sram ? ss_mem_wdata[15:0] : sd_buff_dout),
	.save_do(sd_buff_din),
	.save_wr(ss_sram ? ss_mem_we : (sd_buff_wr & sd_ack)),
	.save_change(bk_change),

	.jcart_en(status[39]),
	.jcart_data(jcart_data),
	.jcart_th(jcart_th),
	
	.gun_type(gun_type),
	.gun_sensor_delay(gun_sensor_delay),

	.ym2612_quirk(ym2612_quirk),

	.fm_en(~status[60]),
	.fm_audio(sms_fm_audio),

	.ss_idx(ss_cart_idx),
	.ss_rdata(ss_cart_rdata),
	.ss_wdata(ss_cart_wdata),
	.ss_we(ss_cart_we),
	.ss_busy(cart_ss_busy),
	.ss_unsupported(svp_or_pier)
);


///////////////////////////////////////////////////
// MD+ Overlay (CDDA command intercept)
///////////////////////////////////////////////////

// HPS ↔ FPGA bridge for MD+ status + audio pointer exchange
wire mdp_hps_playing;
wire [7:0] mdp_hps_current_track;
wire [15:0] mdp_audio_rd_ptr;
wire [15:0] mdp_audio_wr_ptr;
wire        mdp_audio_active;

hps_ext hps_ext
(
	.clk_sys(clk_sys),
	.reset(sys_reset),
	.EXT_BUS(EXT_BUS),

	.mdp_track_request(mdp_track_request),
	.mdp_track_num(mdp_track_num),
	.mdp_track_loop(mdp_track_loop),
	.mdp_stop_request(mdp_stop_request),
	.mdp_fade_sectors(mdp_fade_sectors),
	.mdp_resume_request(mdp_resume_request),
	.mdp_volume(mdp_volume),
	.mdp_volume_request(mdp_volume_request),

	.mdp_playing(mdp_hps_playing),
	.mdp_current_track(mdp_hps_current_track),

	.audio_rd_ptr(mdp_audio_rd_ptr),
	.audio_wr_ptr(mdp_audio_wr_ptr),
	.audio_active(mdp_audio_active)
);

md_plus md_plus
(
	.clk(clk_sys),
	.reset(sys_reset),

	.cart_addr(cart_addr),
	.cart_data_wr(cart_data_wr),
	.cart_cs(cart_cs),
	.cart_oe(cart_oe),
	.cart_lwr(cart_lwr),
	.cart_uwr(cart_uwr),

	.mdp_data_en(mdp_data_en),
	.mdp_data_out(mdp_data_out),
	.mdp_dtack(mdp_dtack),

	.mdp_track_request(mdp_track_request),
	.mdp_track_num(mdp_track_num),
	.mdp_track_loop(mdp_track_loop),
	.mdp_stop_request(mdp_stop_request),
	.mdp_fade_sectors(mdp_fade_sectors),
	.mdp_resume_request(mdp_resume_request),
	.mdp_volume(mdp_volume),
	.mdp_volume_request(mdp_volume_request),

	.mdp_playing(mdp_hps_playing),
	.mdp_current_track(mdp_hps_current_track),

	.mdp_active(mdp_active),
	.mdp_last_cmd(mdp_last_cmd)
);

// CDDA audio output from mdp_audio
wire signed [15:0] cdda_l, cdda_r;

wire        mdp_ddr_busy, mdp_ddr_dout_ready, mdp_ddr_rd, mdp_ddr_we;
wire  [7:0] mdp_ddr_burstcnt, mdp_ddr_be;
wire [28:0] mdp_ddr_addr;
wire [63:0] mdp_ddr_dout, mdp_ddr_din;

mdp_audio mdp_audio
(
	.clk(clk_sys),
	.reset(sys_reset),

	// DDRAM interface (shared with the savestates)
	.DDRAM_CLK(DDRAM_CLK),
	.DDRAM_BUSY(mdp_ddr_busy),
	.DDRAM_BURSTCNT(mdp_ddr_burstcnt),
	.DDRAM_ADDR(mdp_ddr_addr),
	.DDRAM_DOUT(mdp_ddr_dout),
	.DDRAM_DOUT_READY(mdp_ddr_dout_ready),
	.DDRAM_RD(mdp_ddr_rd),
	.DDRAM_DIN(mdp_ddr_din),
	.DDRAM_BE(mdp_ddr_be),
	.DDRAM_WE(mdp_ddr_we),

	// Ring buffer pointers (from/to hps_ext)
	.active(mdp_audio_active),
	.buf_wr_ptr(mdp_audio_wr_ptr),
	.buf_rd_ptr(mdp_audio_rd_ptr),

	// MD+ commands (directly from md_plus)
	.track_start(mdp_track_request),
	.stop_request(mdp_stop_request),
	.fade_sectors(mdp_fade_sectors),
	.volume(mdp_volume),
	.resume_request(mdp_resume_request),
	.osd_pause(OSD_STATUS & status[61]),

	// Audio output
	.audio_l(cdda_l),
	.audio_r(cdda_r)
);


///////////////////////////////////////////////////

reg new_vmode;
always @(posedge clk_sys) begin
	reg old_pal;
	int to;

	if(~sys_reset) begin
		old_pal <= PAL;
		if(old_pal != PAL) to <= 5000000;
	end
	else to <= 5000000;

	if(to) begin
		to <= to - 1;
		if(to == 1) new_vmode <= ~new_vmode;
	end
end

wire       ce_pix;
wire       f1;
wire       interlace;
wire       vblank_c, hblank_c, hs_c, vs_c;
wire [7:0] r_c, g_c, b_c;
wire[11:0] arx,ary;

// CLK_VIDEO is clk_md/2 at a phase the PLL leaves open: hold the VDP video for two clk_md,
// loading on the clocks vdp_hclk1 changes on, so video_cond sees each value once at either phase.
reg  [7:0] vh_r, vh_g, vh_b;
reg        vh_hs, vh_vs, vh_hclk1, vh_de_h, vh_de_v, vh_intfield, vh_m2, vh_m5, vh_rs1;
reg        vh_ph, vh_h1d;
always @(posedge clk_md) begin
	vh_h1d <= vdp_hclk1;
	vh_ph <= ~vh_ph & (vh_h1d == vdp_hclk1);
	if(vh_ph & ~ss_hold) {vh_r, vh_g, vh_b, vh_hs, vh_vs, vh_hclk1, vh_de_h, vh_de_v, vh_intfield, vh_m2, vh_m5, vh_rs1}
		<= {r, g, b, hs, vs, vdp_hclk1, vdp_de_h, vdp_de_v, vdp_intfield, vdp_m2, vdp_m5, vdp_rs1};
end

video_cond video_cond
(
	.clk(CLK_VIDEO),

	.vdp_hclk1(vh_hclk1),
	.vdp_de_h(vh_de_h),
	.vdp_de_v(vh_de_v),
	.vdp_intfield(vh_intfield),
	.vdp_m2(vh_m2),
	.vdp_m5(vh_m5),
	.vdp_rs1(vh_rs1),

	.r_in(vh_r),
	.g_in(vh_g),
	.b_in(vh_b),
	.hs_in(vh_hs),
	.vs_in(vh_vs),

	.pal(PAL),
	.border_en(status[29]),
	.h40corr(status[30]),
	.blender(status[46]),

	.arx(arx),
	.ary(ary),

	.ce_pix(ce_pix),
	.interlace(interlace),
	.f1(f1),

	.r_out(r_c),
	.g_out(g_c),
	.b_out(b_c),
	.hs_out(hs_c),
	.vs_out(vs_c),
	.hbl_out(hblank_c),
	.vbl_out(vblank_c)
);

wire [2:0] scale = status[3:1];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;

assign VGA_SL = {~interlace,~interlace}&sl[1:0];
assign VGA_F1 = f1;

video_mixer #(.LINE_LENGTH(400), .GAMMA(1)) video_mixer
(
	.*,

	.scandoubler(~interlace && (scale || forced_scandoubler)),
	.hq2x(scale==1),
	.freeze_sync(),

	.VGA_DE(vga_de),
	.R((lg_target && gun_mode && (~&status[44:43])) ? {8{lg_target[0]}} : r_c),
	.G((lg_target && gun_mode && (~&status[44:43])) ? {8{lg_target[1]}} : g_c),
	.B((lg_target && gun_mode && (~&status[44:43])) ? {8{lg_target[2]}} : b_c),

	// Positive pulses.
	.HSync(hs_c),
	.VSync(vs_c),
	.HBlank(hblank_c),
	.VBlank(vblank_c)
);


///////////////////////////////////////////////////

// FM + PSG base audio (before CDDA mix)
wire [15:0] base_audio_l, base_audio_r;

audio_cond audio_cond
(
	.clk(clk_sys),
	.reset(sys_reset),
	.mute(~clk_en | dma_z80_req | ss_hold),

	.lpf_mode(status[15:14]),
	.fm_mode(status[11]),

	.fm_clk1(fm_clk1),
	.fm_sel23(fm_sel23),
	.MOL(MOL),
	.MOR(MOR),
	.MOL_2612(MOL_2612),
	.MOR_2612(MOR_2612),
	.PSG(PSG),
	.sms_fm_audio(sms_fm_audio),

	.AUDIO_L(base_audio_l),
	.AUDIO_R(base_audio_r)
);

// Attenuate CDDA: 93/256 ≈ 0.363 — matched to Mega Drive hardware output via A/B recording comparisons
wire signed [24:0] cdda_scaled_l = $signed(cdda_l) * $signed(9'd93);
wire signed [24:0] cdda_scaled_r = $signed(cdda_r) * $signed(9'd93);
wire signed [15:0] cdda_att_l = cdda_scaled_l[23:8];
wire signed [15:0] cdda_att_r = cdda_scaled_r[23:8];

// Saturating mix: FM/PSG + attenuated CDDA
wire signed [16:0] mix_l = $signed(base_audio_l) + $signed(cdda_att_l);
wire signed [16:0] mix_r = $signed(base_audio_r) + $signed(cdda_att_r);

assign AUDIO_L = (mix_l[16] != mix_l[15]) ? {mix_l[16], {15{~mix_l[16]}}} : mix_l[15:0];
assign AUDIO_R = (mix_r[16] != mix_r[15]) ? {mix_r[16], {15{~mix_r[16]}}} : mix_r[15:0];

assign AUDIO_MIX = status[58:57];


///////////////////////////////////////////////////

reg  [1:0] region_req;
reg        region_set = 0;
reg        region_set_rst = 0;

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state, old_ready = 0;
	old_state <= ps2_key[10];

	if(old_state != ps2_key[10]) begin
		casex(code)
			'h005: begin region_req <= 0; region_set_rst <= pressed; region_set <= pressed; end // F1
			'h006: begin region_req <= 1; region_set_rst <= pressed; region_set <= pressed; end // F2
			'h004: begin region_req <= 2; region_set_rst <= pressed; region_set <= pressed; end // F3
		endcase
	end

	old_ready <= cart_hdr_ready;
	if(~cart_ms & ~status[9] & ~old_ready & cart_hdr_ready) begin
		if(~status[8]) begin
			region_set <= 1;
			case(status[28:27])
				0: if(hdr_u) region_req <= 1;
					else if(hdr_e) region_req <= 2;
					else if(hdr_j) region_req <= 0;
					else region_req <= 1;

				1: if(hdr_e) region_req <= 2;
					else if(hdr_u) region_req <= 1;
					else if(hdr_j) region_req <= 0;
					else region_req <= 2;

				2: if(hdr_u) region_req <= 1;
					else if(hdr_j) region_req <= 0;
					else if(hdr_e) region_req <= 2;
					else region_req <= 1;

				3: if(hdr_j) region_req <= 0;
					else if(hdr_u) region_req <= 1;
					else if(hdr_e) region_req <= 2;
					else region_req <= 0;
			endcase
		end
		else begin
			region_set <= |ioctl_index;
			region_req <= ioctl_index[7:6];
		end
	end

	if(old_ready & ~cart_hdr_ready) region_set <= 0;
end

wire [3:0] hrgn = ioctl_data[3:0] - 4'd7;

reg cart_hdr_ready = 0;
reg hdr_j=0,hdr_u=0,hdr_e=0;
always @(posedge clk_sys) begin
	reg old_download;
	old_download <= cart_download;

	if(~old_download && cart_download) {hdr_j,hdr_u,hdr_e} <= 0;
	if(old_download && ~cart_download) cart_hdr_ready <= 0;

	if(ioctl_wr & cart_download) begin
		if(ioctl_addr == 'h1F0) begin
			if(ioctl_data[7:0] == "J") hdr_j <= 1;
			else if(ioctl_data[7:0] == "U") hdr_u <= 1;
			else if(ioctl_data[7:0] == "E") hdr_e <= 1;
			else if(ioctl_data[7:0] >= "0" && ioctl_data[7:0] <= "9") {hdr_e, hdr_u, hdr_j} <= {ioctl_data[3], ioctl_data[2], ioctl_data[0]};
			else if(ioctl_data[7:0] >= "A" && ioctl_data[7:0] <= "F") {hdr_e, hdr_u, hdr_j} <= {      hrgn[3],       hrgn[2],       hrgn[0]};
		end
		if(ioctl_addr == 'h1F2) begin
			if(ioctl_data[7:0] == "J") hdr_j <= 1;
			else if(ioctl_data[7:0] == "U") hdr_u <= 1;
			else if(ioctl_data[7:0] == "E") hdr_e <= 1;
		end
		if(ioctl_addr == 'h1F0) begin
			if(ioctl_data[15:8] == "J") hdr_j <= 1;
			else if(ioctl_data[15:8] == "U") hdr_u <= 1;
			else if(ioctl_data[15:8] == "E") hdr_e <= 1;
		end
		if(ioctl_addr == 'h200) cart_hdr_ready <= 1;
	end
end

///////////////////////////////////////////////////

wire [11:0] joy0 = status[4] ? joystick_1[11:0] : joystick_0[11:0];
wire [11:0] joy1 = status[4] ? joystick_0[11:0] : joystick_1[11:0];

wire [6:0] md_io_port1, md_io_port2;

wire [15:0] jcart_data;
wire        jcart_th;

md_io md_io
(
	.clk(clk_sys),
	.reset(sys_reset),

	.MODE(status[5]),
	.SMS(cart_ms),
	.MULTITAP(cart_ms ? {|status[39:37], 1'b0} : status[38:37]),

	.P1_UP(joy0[3]),
	.P1_DOWN(joy0[2]),
	.P1_LEFT(joy0[1]),
	.P1_RIGHT(joy0[0]),
	.P1_A(joy0[4]),
	.P1_B(joy0[5]),
	.P1_C(joy0[6]),
	.P1_START(joy0[7]),
	.P1_MODE(joy0[8]),
	.P1_X(joy0[9]),
	.P1_Y(joy0[10]),
	.P1_Z(joy0[11]),

	.P2_UP(joy1[3]),
	.P2_DOWN(joy1[2]),
	.P2_LEFT(joy1[1]),
	.P2_RIGHT(joy1[0]),
	.P2_A(joy1[4]),
	.P2_B(joy1[5]),
	.P2_C(joy1[6]),
	.P2_START(joy1[7]),
	.P2_MODE(joy1[8]),
	.P2_X(joy1[9]),
	.P2_Y(joy1[10]),
	.P2_Z(joy1[11]),

	.P3_UP(joystick_2[3]),
	.P3_DOWN(joystick_2[2]),
	.P3_LEFT(joystick_2[1]),
	.P3_RIGHT(joystick_2[0]),
	.P3_A(joystick_2[4]),
	.P3_B(joystick_2[5]),
	.P3_C(joystick_2[6]),
	.P3_START(joystick_2[7]),
	.P3_MODE(joystick_2[8]),
	.P3_X(joystick_2[9]),
	.P3_Y(joystick_2[10]),
	.P3_Z(joystick_2[11]),

	.P4_UP(joystick_3[3]),
	.P4_DOWN(joystick_3[2]),
	.P4_LEFT(joystick_3[1]),
	.P4_RIGHT(joystick_3[0]),
	.P4_A(joystick_3[4]),
	.P4_B(joystick_3[5]),
	.P4_C(joystick_3[6]),
	.P4_START(joystick_3[7]),
	.P4_MODE(joystick_3[8]),
	.P4_X(joystick_3[9]),
	.P4_Y(joystick_3[10]),
	.P4_Z(joystick_3[11]),

	.P5_UP(joystick_4[3]),
	.P5_DOWN(joystick_4[2]),
	.P5_LEFT(joystick_4[1]),
	.P5_RIGHT(joystick_4[0]),
	.P5_A(joystick_4[4]),
	.P5_B(joystick_4[5]),
	.P5_C(joystick_4[6]),
	.P5_START(joystick_4[7]),
	.P5_MODE(joystick_4[8]),
	.P5_X(joystick_4[9]),
	.P5_Y(joystick_4[10]),
	.P5_Z(joystick_4[11]),

	.GUN_OPT(|gun_mode),
	.GUN_TYPE(gun_type),
	.GUN_SENSOR(lg_sensor),
	.GUN_A(lg_a),
	.GUN_B(lg_b),
	.GUN_C(lg_c),
	.GUN_START(lg_start),

	.MOUSE(ps2_mouse),
	.MOUSE_OPT(status[20:18]),

	.jcart_data(jcart_data),
	.jcart_th(jcart_th),

	.port1_out(md_io_port1),
	.port1_in(PA_o  | {7{snac_port1}}),
	.port1_dir(PA_d | {7{snac_port1}}),

	.port2_out(md_io_port2),
	.port2_in(PB_o  | {7{snac_port2}}),
	.port2_dir(PB_d | {7{snac_port2}}),

	.PS2_KEY(ps2_key),
	.PS2_LED(ps2_kbd_led_status),
	.KEYBOARD_OPT(status[22:21])
);

wire [2:0] lg_target;
wire       lg_sensor;
wire       lg_a;
wire       lg_b;
wire       lg_c;
wire       lg_start;

lightgun lightgun
(
	.CLK(clk_sys),
	.RESET(sys_reset),

	.MOUSE(ps2_mouse),
	.MOUSE_XY(&gun_mode),

	.JOY_X(gun_mode[0] ? joy0_x : joy1_x),
	.JOY_Y(gun_mode[0] ? joy0_y : joy1_y),
	.JOY(gun_mode[0] ? joystick_0 : joystick_1),

	.RELOAD(gun_type),

	.HDE(~hblank_c),
	.VDE(~vblank_c),
	.CE_PIX(ce_pix),
	.H40(vdp_rs1),

	.BTN_MODE(gun_btn_mode),
	.SIZE(status[44:43]),
	.SENSOR_DELAY(gun_sensor_delay),

	.TARGET(lg_target),
	.SENSOR(lg_sensor),
	.BTN_A(lg_a),
	.BTN_B(lg_b),
	.BTN_C(lg_c),
	.BTN_START(lg_start)
);

wire [6:0] SNAC_IN;
wire [6:0] SNAC_OUT;
always_comb begin
	SNAC_IN[0]  = USER_IN[1]; //up
	SNAC_IN[1]  = USER_IN[0]; //down
	SNAC_IN[2]  = USER_IN[5]; //left
	SNAC_IN[3]  = USER_IN[3]; //right
	SNAC_IN[4]  = USER_IN[2]; //b TL
	SNAC_IN[5]  = USER_IN[6]; //c TR GPIO7
	SNAC_IN[6]  = USER_IN[4]; //  TH
	USER_OUT[1] = SNAC_OUT[0];
	USER_OUT[0] = SNAC_OUT[1];
	USER_OUT[5] = SNAC_OUT[2];
	USER_OUT[3] = SNAC_OUT[3];
	USER_OUT[2] = SNAC_OUT[4];
	USER_OUT[6] = SNAC_OUT[5];
	USER_OUT[4] = SNAC_OUT[6];
end

wire snac_port1 = (status[63:62] == 1);
assign PA_i = snac_port1 ? SNAC_IN : md_io_port1;

wire snac_port2 = (status[63:62] == 2);
assign PB_i = snac_port2 ? SNAC_IN : md_io_port2;

wire snac_port3 = (status[63:62] == 3);
assign PC_i = snac_port3 ? SNAC_IN : (PC_d | PC_o);

assign SNAC_OUT = snac_port1 ? (PA_d | PA_o) : snac_port2 ? (PB_d | PB_o) : snac_port3 ? (PC_d | PC_o) : 7'h7F;

/////////////////////////  BRAM SAVE/LOAD  /////////////////////////////

wire downloading = cart_download;

reg bk_ena = 0;
reg sav_pending = 0;
wire bk_change;

always @(posedge clk_sys) begin
	reg old_downloading = 0;
	reg old_change = 0;

	old_downloading <= downloading;
	if(~old_downloading & downloading) bk_ena <= 0;

	//Save file always mounted in the end of downloading state.
	if(downloading && img_mounted && !img_readonly) bk_ena <= 1;

	old_change <= bk_change;
	if (~old_change & bk_change & ~OSD_STATUS) sav_pending <= 1;
	else if (bk_state) sav_pending <= 0;
end

wire bk_load    = status[16];
wire bk_save    = status[17] | (sav_pending & OSD_STATUS & status[13]);
reg  bk_loading = 0;
reg  bk_state   = 0;

always @(posedge clk_sys) begin
	reg old_downloading = 0;
	reg old_load = 0, old_save = 0, old_ack;

	old_downloading <= downloading;

	old_load <= bk_load;
	old_save <= bk_save;
	old_ack  <= sd_ack;

	if(~old_ack & sd_ack) {sd_rd, sd_wr} <= 0;

	if(!bk_state) begin
		if(bk_ena & ((~old_load & bk_load) | (~old_save & bk_save))) begin
			bk_state <= 1;
			bk_loading <= bk_load;
			sd_lba <= 0;
			sd_rd <=  bk_load;
			sd_wr <= ~bk_load;
		end
		if(old_downloading & ~downloading & |img_size & bk_ena) begin
			bk_state <= 1;
			bk_loading <= 1;
			sd_lba <= 0;
			sd_rd <= 1;
			sd_wr <= 0;
		end
	end else begin
		if(old_ack & ~sd_ack) begin
			if(&sd_lba[6:0]) begin
				bk_loading <= 0;
				bk_state <= 0;
			end else begin
				sd_lba <= sd_lba + 1'd1;
				sd_rd  <=  bk_loading;
				sd_wr  <= ~bk_loading;
			end
		end
	end
end


///////////////////////////////////////////////////
// Cheat codes loading for WIDE IO (16 bit)
reg [128:0] gg_code;
wire        gg_available;

// Code layout:
// {clock bit, code flags,     32'b address, 32'b compare, 32'b replace}
//  128        127:96          95:64         63:32         31:0
// Integer values are in BIG endian byte order, so it up to the loader
// or generator of the code to re-arrange them correctly.

always_ff @(posedge clk_sys) begin
	gg_code[128] <= 1'b0;

	if (code_download & ioctl_wr) begin
		case (ioctl_addr[3:0])
			0:  gg_code[111:96]  <= ioctl_data; // Flags Bottom Word
			2:  gg_code[127:112] <= ioctl_data; // Flags Top Word
			4:  gg_code[79:64]   <= ioctl_data; // Address Bottom Word
			6:  gg_code[95:80]   <= ioctl_data; // Address Top Word
			8:  gg_code[47:32]   <= ioctl_data; // Compare Bottom Word
			10: gg_code[63:48]   <= ioctl_data; // Compare top Word
			12: gg_code[15:0]    <= ioctl_data; // Replace Bottom Word
			14: begin
				gg_code[31:16]   <= ioctl_data; // Replace Top Word
				gg_code[128]     <=  1'b1;      // Clock it in
			end
		endcase
	end
end

wire [15:0] m68k_genie_data;
CODES #(.ADDR_WIDTH(24), .DATA_WIDTH(16), .BIG_ENDIAN(1)) codes_68k
(
	.clk(clk_sys),
	.reset(cart_download | (code_download && ioctl_wr && !ioctl_addr)),
	.enable(~status[24] & ~cart_ms),
	.code(gg_code),
	.available(gg_available),
	.addr_in({m68k_addr, 1'b0}),
	.data_in(m68k_bus_do),
	.data_out(m68k_genie_data)
);

wire [7:0] z80_genie_data;
CODES #(.ADDR_WIDTH(16), .DATA_WIDTH(8)) codes_z80
(
	.clk(clk_sys),
	.reset(cart_download | (code_download && ioctl_wr && !ioctl_addr)),
	.enable(~status[24] & cart_ms),
	.code(gg_code),
	.addr_in(z80_addr),
	.data_in(z80_bus_do),
	.data_out(z80_genie_data)
);


/////////////////////////  SAVESTATES  /////////////////////////////

wire        ss_save, ss_load;
wire        ss_busy;
wire        ddr_req, ddr_ack, ddr_we;
wire [28:0] ddr_addr;
wire [63:0] ddr_wdata, ddr_rdata;

// a cartridge has been loaded since power on
reg rom_loaded = 0;
always @(posedge clk_sys) begin
	reg old_dl;
	old_dl <= cart_download;
	if(old_dl & ~cart_download) rom_loaded <= 1;
end

// the core may be frozen when nothing is on the cartridge bus and the SDRAM is idle
wire        ss_safe = ~(core_cart_cs | core_cart_oe | core_cart_lwr | core_cart_uwr | core_cart_time) & ~cart_ss_busy
                      & ~md_reset & ~btn_reset & ~cart_download & ~bk_state;

// the UI pulses are on clk_sys: carry them over to clk_md as toggles
reg ss_save_t = 0, ss_load_t = 0;
always @(posedge clk_sys) begin
	if(ss_save) ss_save_t <= ~ss_save_t;
	if(ss_load) ss_load_t <= ~ss_load_t;
end

reg ss_save_md, ss_load_md;
always @(posedge clk_md) begin
	reg [1:0] save_s, load_s;
	save_s <= {save_s[0], ss_save_t};
	load_s <= {load_s[0], ss_load_t};
	ss_save_md <= save_s[1] ^ save_s[0];
	ss_load_md <= load_s[1] ^ load_s[0];
end

ss_ctrl ss_ctrl
(
	.clk(clk_md),
	.reset(md_reset),

	.save(ss_save_md),
	.load(ss_load_md),
	.slot(ss_slot),
	.allow(rom_loaded & ~svp_or_pier),
	.safe(ss_safe),
	.busy(ss_busy),

	.ss_hold(ss_hold),
	.ss_shift(ss_shift),
	.ss_sel(ss_sel),
	.ss_in(ss_in),
	.ss_out(ss_out),
	.ss_refresh(ss_refresh),
	.ss_mem_act(ss_mem_act),
	.ss_mem_sel(ss_mem_sel),
	.ss_mem_addr(ss_mem_addr),
	.ss_mem_we(ss_mem_we),
	.ss_mem_wdata(ss_mem_wdata),
	.ss_mem_rdata((ss_mem_sel == 4'd8) ? {48'd0, sd_buff_din} : ss_core_rdata),

	.cart_idx(ss_cart_idx),
	.cart_rdata(ss_cart_rdata),
	.cart_wdata(ss_cart_wdata),
	.cart_we(ss_cart_we),

	.ddr_req(ddr_req),
	.ddr_ack(ddr_ack),
	.ddr_we(ddr_we),
	.ddr_addr(ddr_addr),
	.ddr_wdata(ddr_wdata),
	.ddr_rdata(ddr_rdata)
);

ss_ddr ss_ddr
(
	.clk(clk_sys),

	.ss_busy(ss_busy),
	.ss_req(ddr_req),
	.ss_ack(ddr_ack),
	.ss_we(ddr_we),
	.ss_addr(ddr_addr),
	.ss_wdata(ddr_wdata),
	.ss_rdata(ddr_rdata),

	.a_BUSY(mdp_ddr_busy),
	.a_BURSTCNT(mdp_ddr_burstcnt),
	.a_ADDR(mdp_ddr_addr),
	.a_DOUT(mdp_ddr_dout),
	.a_DOUT_READY(mdp_ddr_dout_ready),
	.a_RD(mdp_ddr_rd),
	.a_DIN(mdp_ddr_din),
	.a_BE(mdp_ddr_be),
	.a_WE(mdp_ddr_we),

	.DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
	.DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_RD(DDRAM_RD),
	.DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE),
	.DDRAM_WE(DDRAM_WE)
);

// OSD, gamepad (Savestates button + Start + D-pad). The keyboard is left out: F1-F3 already
// switch the region in this core.
savestate_ui #(.INFO_TIMEOUT_BITS(25)) savestate_ui
(
	.clk            (clk_sys),
	.ps2_key        (11'd0),
	.allow_ss       (rom_loaded & ~svp_or_pier),
	.joySS          (joystick_0[12]),
	.joyRight       (joystick_0[0]),
	.joyLeft        (joystick_0[1]),
	.joyDown        (joystick_0[2]),
	.joyUp          (joystick_0[3]),
	.joyStart       (joystick_0[7]),
	.status_slot    (status[65:64]),
	.OSD_saveload   (status[67:66]),
	.ss_save        (ss_save),
	.ss_load        (ss_load),
	.ss_info_req    (ss_info_req),
	.ss_info        (ss_info),
	.statusUpdate   (ss_status_update),
	.selected_slot  (ss_slot)
);

endmodule
