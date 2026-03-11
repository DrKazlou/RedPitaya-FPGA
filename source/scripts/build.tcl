# complete_build.tcl - Run after block_design.tcl to finish synthesis, impl, and generate loadable bitstream
set project_name adc_bram
# Open the project created by block_design.tcl (essential for batch mode)
open_project project/$project_name.xpr

# Run implementation
opt_design
place_design
phys_opt_design
route_design

# Enable compression (smaller bitstream)
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# Generate standard compressed bitstream
write_bitstream -force project/$project_name.bit

puts ""
puts "=================================="
puts "SUCCESS! Full build complete"
puts "  Standard bitstream: project/$project_name.bit"
puts ""
