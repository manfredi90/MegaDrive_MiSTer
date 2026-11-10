derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
#set_multicycle_path -from {emu|md_board|*} -to {emu|cartridge|*} -setup 2
#set_multicycle_path -from {emu|md_board|*} -to {emu|cartridge|*} -hold 1

# psg_iir registers only load on ce_flt, a 7 MHz enable on clk_sys
set_multicycle_path -from {*|psg_iir|*} -to {*|psg_iir|*intreg*} -setup 2
set_multicycle_path -from {*|psg_iir|*} -to {*|psg_iir|*intreg*} -hold 1

# Savestate memory port. rtl/ss_ctrl.sv keeps ss_mem_* steady for several clocks per
# entry and takes the read data two clocks after each hop, and these paths only switch
# while the core is held, so they get two clocks instead of one.
set_multicycle_path -from [get_registers {*|ss_ctrl:ss_ctrl|ss_mem_*}] -setup -start 2
set_multicycle_path -from [get_registers {*|ss_ctrl:ss_ctrl|ss_mem_*}] -hold -start 1
set_multicycle_path -from [get_registers {*|md_core:md_core|*ssx_*}] -setup -start 2
set_multicycle_path -from [get_registers {*|md_core:md_core|*ssx_*}] -hold -start 1
set_multicycle_path -to [get_registers {*|md_core:md_core|*ssx_*}] -setup -end 2
set_multicycle_path -to [get_registers {*|md_core:md_core|*ssx_*}] -hold -end 1
set_multicycle_path -to [get_registers {*|ss_ctrl:ss_ctrl|mem_q*}] -setup -end 2
set_multicycle_path -to [get_registers {*|ss_ctrl:ss_ctrl|mem_q*}] -hold -end 1
