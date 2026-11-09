#!/bin/sh
# Build the Verilator models:
#   rtl  obj_rtl: plain RTL (no scan chain)
#   lib  obj_lib: the generated scan netlist as a protected library (slow, ~6 GB RAM, once)
#   ss   obj_ss:  testbench linked against obj_lib (fast to rebuild)
set -e
cd "$(dirname "$0")"
R=../../rtl
N=$R/nuked-md
W="-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-COMBDLY -Wno-BLKANDNBLK"
FLAGS="$W --x-assign 0 --x-initial 0 -O3 --cc --exe --build -j 2 --top-module tb -CFLAGS -O2"
what=${1:-all}
if [ $what = rtl ] || [ $what = all ]; then
	verilator $FLAGS -DEXT_CLOCKS -DM68K_CHEAT -DZ80_CHEAT -Mdir obj_rtl -o sim tb.sv sim_main.cpp \
		$R/ss_ctrl.sv $R/ss_ddr.sv -I$R vram_ip_model.v \
		$R/md_core.v $N/md_board.v $N/68k.v $N/m68k_microrom.v $N/z80.v $N/fc1004.v $N/ym7101.v \
		$N/ym6045.v $N/ym6046.v $N/tmss.v $N/vram.v $N/ym_lib.v $N/ym3438*.v
fi
if [ $what = lib ] || [ $what = all ] || [ ! -f obj_lib/libmd_core_pl.a ]; then
	verilator $W --x-assign 0 --x-initial 0 -O3 --cc --build -j 1 -CFLAGS -O2 --protect-lib md_core_pl \
		--top-module md_core -Mdir obj_lib $R/md_core_ss.v $N/m68k_microrom.v vram_ip_model.v
fi
if [ $what = ss ] || [ $what = lib ] || [ $what = all ]; then
	verilator $FLAGS -DMD_CORE=md_core_pl -Mdir obj_ss -o sim tb.sv sim_main.cpp $R/ss_ctrl.sv $R/ss_ddr.sv -I$R \
		obj_lib/md_core_pl.sv $PWD/obj_lib/libmd_core_pl.a
fi
ln -sf $N/68k_ucode.txt $N/68k_ncode.txt $R/md_core_ss.vh .
