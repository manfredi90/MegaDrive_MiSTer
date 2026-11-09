#!/bin/sh
# Converter test: build B is build A plus 8 register bits that sort first (every bit of
# the chain moves). A state saved by A, converted by mdss_convert.py, must replay exactly
# in B; the unconverted file must be refused. Needs obj_ss (A) built by build_sim.sh.
set -e
cd "$(dirname "$0")"
R=../../rtl
N=$R/nuked-md
W="-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-COMBDLY -Wno-BLKANDNBLK"
mkdir -p variant/maps
if [ ! -f variant/obj_lib/libmd_core_pl.a ]; then
	OUT=savestate/sim/variant DEFS=-DSS_TEST_VARIANT MAPS=savestate/sim/variant/maps sh ../gen_netlist.sh
	verilator $W --x-assign 0 --x-initial 0 -O3 --cc --build -j 1 -CFLAGS -O2 --protect-lib md_core_pl \
		--top-module md_core -Mdir variant/obj_lib variant/md_core_ss.v $N/m68k_microrom.v vram_ip_model.v
fi
verilator $W --x-assign 0 --x-initial 0 -O3 --cc --exe --build -j 2 --top-module tb -CFLAGS -O2 \
	-DMD_CORE=md_core_pl -Mdir variant/obj_ss -o sim $PWD/tb.sv $PWD/sim_main.cpp $R/ss_ctrl.sv $R/ss_ddr.sv \
	-Ivariant -I$R variant/obj_lib/md_core_pl.sv $PWD/variant/obj_lib/libmd_core_pl.a > variant/build.log

A=$(sed -n "s/.*32'h\(........\);/\1/p" $R/md_core_ss.vh)
B=$(sed -n "s/.*32'h\(........\);/\1/p" variant/md_core_ss.vh)
echo "layout A $A, layout B $B"
mkdir -p variant/conv
cp ../layouts/$A.map.gz variant/maps/

saved=$(./obj_ss/sim savefile 5 variant/a.ss | sed -n 's/saved at cycle \([0-9]*\).*/\1/p')
echo "A saved at cycle $saved"

echo "--- B must refuse the unconverted state"
if ./variant/obj_ss/sim loadfile 5 variant/a.ss $saved | grep -q "LOAD REFUSED"; then echo refused; else echo "NOT REFUSED"; exit 1; fi

echo "--- convert A -> B"
cp variant/a.ss variant/conv/game_1.ss
python3 ../convert/mdss_convert.py --maps variant/maps --to $B variant/conv
./variant/obj_ss/sim loadfile 5 variant/conv/game_1.ss $saved

echo "--- and back B -> A"
python3 ../convert/mdss_convert.py --maps variant/maps --to $A variant/conv
cmp variant/conv/game_1.ss variant/a.ss && echo "round trip gives back the original file"
