// Modules kept as instances in the generated netlist (their RTL is passed to Quartus as is).

(* blackbox *)
module vram_ip
(
	input	  [7:0] address,
	input	 [31:0] byteena,
	input	        clock,
	input	[255:0] data,
	input	        wren,
	output[255:0] q
);
endmodule

(* blackbox *)
module m68k_microrom
	(
	input MCLK,
	input en,
	input [5:0] ucode_addr,
	input [7:0] ncode_addr,
	output [271:0] ucode_out,
	output [271:0] ncode_out
	);
endmodule
