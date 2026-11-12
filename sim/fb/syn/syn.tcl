# Gowin build check of the frame buffer alone (fb_syn_top.sv), with the options of the System SJ
# port's build.tcl. Run from an empty output folder:
#
#   gw_sh /path/to/syn.tcl /path/to/fpga_burgertime /path/to/pll_dir
#
# pll_dir holds gowin_pll_game.v and gowin_pll_hdmi.v (the System SJ port's tang/nano20k, until
# this port has its own). Reports: impl/gwsynthesis/fb_syn.log, impl/pnr/fb_syn.rpt.txt
# (resources) and impl/pnr/fb_syn_tr_content.html (timing).

if {$argc != 2} {
    puts "Usage: gw_sh syn.tcl <fpga_burgertime dir> <pll dir>"
    exit 1
}
set root [lindex $argv 0]
set pll  [lindex $argv 1]
set brd  $root/tang/nano20k
set here $root/sim/fb/syn

set_device GW2AR-LV18QN88C8/I7 -device_version C

add_file -type verilog "$here/fb_syn_top.sv"
add_file -type verilog "$brd/framebuffer.sv"
add_file -type verilog "$brd/fb_writer.sv"
add_file -type verilog "$brd/fb_reader.sv"
add_file -type verilog "$brd/sdram.v"
add_file -type verilog "$pll/gowin_pll_game.v"
add_file -type verilog "$pll/gowin_pll_hdmi.v"
add_file -type cst "$here/fb_syn.cst"
add_file -type sdc "$here/fb_syn.sdc"

set_option -synthesis_tool gowinsynthesis
set_option -top_module fb_syn_top
set_option -verilog_std sysv2017
set_option -rw_check_on_ram 1
set_option -place_option 2
set_option -ireg_in_iob 1
set_option -oreg_in_iob 1
set_option -ioreg_in_iob 1
set_option -use_sspi_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_i2c_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -output_base_name fb_syn

run all
