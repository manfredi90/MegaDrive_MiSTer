/*
 * Copyright (C) 2022-2023 nukeykt
 *
 * This file is part of Nuked-MD.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 *  68000 emulator.
 *  Thanks:
 *      John McMaster (siliconpr0n.org):
 *          68000 decap and die shot.
 *      Olivier Galibert:
 *          68000 schematics.
 *      org, andkorzh, HardWareMan (emu-russia):
 *          help & support.
 *
 */

// Microcode/nanocode ROMs with registered output (M10K).
module m68k_microrom
	(
	input MCLK,
	input en,
	input [5:0] ucode_addr,
	input [7:0] ncode_addr,
	output reg [271:0] ucode_out,
	output reg [271:0] ncode_out
	);
	
	(* ramstyle = "M10K" *) reg [271:0] ucode[0:63];
	(* ramstyle = "M10K" *) reg [271:0] ncode[0:255];
	
	initial
	begin
		$readmemb("68k_ucode.txt", ucode);
		$readmemb("68k_ncode.txt", ncode);
	end
	
	always @(posedge MCLK)
	begin
		if (en)
		begin
			ucode_out <= ucode[ucode_addr];
			ncode_out <= ncode[ncode_addr];
		end
	end
endmodule
