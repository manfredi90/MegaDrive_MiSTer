# Savestates for the Nuked-MD core

Nuked-MD is a gate-level translation of the Mega Drive chips: the machine state is
~16,600 flip-flops spread over thousands of anonymous latches. Instead of wiring
each one to a save bus by hand, the whole clk_md side of the core is turned into a
**scan chain** automatically.

## How it works

* `rtl/md_core.v` wraps `md_board` together with the clk_md registers that used to
  live in `MegaDrive.sv` (external clock enables, bus-request pause, cheat data).
* `savestate/gen_netlist.sh` flattens `md_core` with Yosys and runs
  `scan_insert.py`, which gives every flip-flop
  `D' = ss_shift ? previous_bit : (ss_hold ? Q : D)`.
  The result is `rtl/md_core_ss.v` (what Quartus compiles) and
  `rtl/md_core_ss.vh` (chain length, layout hash). Bits are saved sorted by register
  name, so the order does not depend on Yosys and only moves where the design does.
* Memories are not in the chain; `ss_mem_*` reads and writes them while the core is
  held: VSRAM, SAT cache, sprite data, line buffer, CRAM, VRAM, 68k RAM, Z80 RAM,
  plus the cartridge backup RAM (select 8, in `MegaDrive.sv`).
* Block RAMs register their address internally, which the chain cannot see. Each
  one has a shadow copy of that address in the chain, and `ss_refresh` replays it
  for one clock after a save or load (`ss_row` in `vram.v`, `ss_ua/ss_na` for the
  68k microcode ROM, `ss_ram68_a/ss_ramz_a/ss_tmss_a` in `md_board.v`).
* Registers whose name starts with `ssx_` belong to the savestate logic and are
  left out of the chain.
* `rtl/ss_ctrl.sv` freezes the core when the cartridge bus is idle, streams
  chain, memories and mapper registers to DDR3 (`rtl/ss_ddr.sv` shares the port
  with the MD+ audio reader), and writes the header last. Main_MiSTer saves the
  slot to the SD card when the counter in the header changes (`SS3E000000:100000`
  in the config string: 4 slots of 1 MB). A state is ~210 KB; the core is held
  for about 9 ms on a save and 12 ms on a load (most of it is DDR3 round trips).

## Layouts and old states

Each build has a layout: the chain bits in save order with their names and power-on
values, the memories and the cartridge fields (`savestate/layout_fixed.txt`). It is
written to `savestate/layouts/<hash>.map.gz` and the hash goes into every state. The
core only loads states with its own hash; the others are left alone, never loaded wrong.

`savestate/convert/mdss_convert.py` carries states across builds by name: registers
present in both keep their value, new ones get their power-on value, removed ones are
dropped, memories and cartridge fields are copied. The original stays as
`<name>.ss.<oldhash>.bak`. On the MiSTer it runs from the Scripts menu
(`megadrive_savestates.sh`); on a PC: `python3 mdss_convert.py --maps maps X:\savestates\MegaDrive`.
It needs the map of the build that saved each state, so maps are never deleted.

If an update changes what a register means (not just adds or removes some), a
converted state can glitch or hang right after loading; it still loads in the old
build with the `.bak` file.

After changing anything in `rtl/md_core.v` or `rtl/nuked-md`:

```
sh savestate/gen_netlist.sh        # needs yosys and python3
git add savestate/layouts          # keep the new map
```

The CI build does the same and warns when the map is not committed. Its
`MegaDrive_SS_sd` artifact is laid out as the SD card: the core in `_Console`, the
script in `Scripts`, the converter and all maps in `Scripts/.megadrive_savestates`.

## Tests

`savestate/sim` runs the core in Verilator on a small test ROM that keeps the 68000,
VDP (DMA, sprites, scroll, interrupts), Z80, YM2612 and PSG busy:

```
sim/build_rom.sh                   # needs z80asm and binutils-m68k-linux-gnu
sim/build_sim.sh                   # obj_rtl (plain RTL), obj_lib + obj_ss (netlist)
cd sim
./obj_ss/sim test 1                # save, run on, scramble, load: replay must match cycle by cycle
./obj_ss/sim ctrl 1                # same through ss_ctrl/ss_ddr with a stalling DDR model
./obj_rtl/sim trace N a; ./obj_ss/sim trace N b; cmp a b   # netlist vs RTL
./test_convert.sh                  # state saved by build A, converted, replayed in build B
```

Build B in `test_convert.sh` is build A plus a register whose name sorts first, so every
bit of the chain moves; B must refuse the unconverted state, replay the converted one
cycle by cycle, and converting back must give the original file.

Netlist and RTL traces match except for a one-clock difference on the cartridge
LWR strobe about every 12,500 clocks: it comes out of a combinational loop in the
bus arbiter, which the two simulations settle differently. Video, audio and the
machine state stay identical.

The netlist library (obj_lib) needs ~6 GB of RAM and ~25 minutes to build; after
that the testbench links against it in seconds.

## Not covered

* SVP (Virtua Racing) and Pier Solar: savestates are disabled for them.
* The EEPROM chips' serial state machines (saving during an EEPROM transfer may
  break it) and the SMS FM chip's internal state (only a short sound glitch).
* MD+ CD audio playback position.
* Active cheat codes can be wrong for the first couple of clocks after a load.
