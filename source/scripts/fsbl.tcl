# fsbl.tcl - Simple FSBL build for Red Pitaya 4-channel (Zynq-7020)
# Usage: xsct fsbl.tcl <project_name> <xsa_file>
#Example: xsct source/scripts/fsbl.tcl led_blinker_4ch project/led_blinker_4ch.xsa

set project_name [lindex $argv 0]
set xsa_file [lindex $argv 1]

# Open the hardware design (.xsa exported from Vivado)
hsi open_hw_design $xsa_file

hsi create_sw_design -proc ps7_cortexa9_0 -os standalone fsbl

# Generate FSBL (standard, no custom patches)
hsi generate_app -proc ps7_cortexa9_0 -app zynq_fsbl -dir project/fsbl_out -compile

puts "FSBL generated in project/fsbl_out/executable.elf"

hsi close_hw_design [hsi current_hw_design]