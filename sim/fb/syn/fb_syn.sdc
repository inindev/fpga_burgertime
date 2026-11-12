// Clocks for the frame buffer build check: the same as the System SJ port's sj.sdc.

create_clock -name clk27 -period 37.037 -waveform {0 18.518} [get_ports {sys_clk}]
create_generated_clock -name clk48 -source [get_ports {sys_clk}] -master_clock clk27 -multiply_by 16 -divide_by 9 [get_pins {u_pll_game/rpll_inst/CLKOUTD}]
create_generated_clock -name clk32 -source [get_ports {sys_clk}] -master_clock clk27 -multiply_by 32 -divide_by 27 [get_pins {u_pll_game/rpll_inst/CLKOUTD3}]
create_generated_clock -name hclk5 -source [get_ports {sys_clk}] -master_clock clk27 -multiply_by 55 -divide_by 4 [get_pins {u_pll_hdmi/rpll_inst/CLKOUT}]
create_generated_clock -name hclk -source [get_pins {u_pll_hdmi/rpll_inst/CLKOUT}] -master_clock hclk5 -divide_by 5 [get_pins {u_div5/CLKOUT}]

// first flop of each synchroniser
set_false_path -to [get_regs {*_meta*}]
