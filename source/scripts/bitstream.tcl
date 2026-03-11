# bitstream.tcl - Universal implementation and bitstream generation
# Usage: vivado -mode batch -source source/scripts/bitstream.tcl -tclargs project_name

set project_name [lindex $argv 0]

if {$project_name == ""} {
  puts "ERROR: Project name not provided!"
  puts "Usage: vivado -mode batch -source source/scripts/bitstream.tcl -tclargs project_name"
  exit 1
}

set project_dir project/$project_name.xpr

if {![file exists $project_dir]} {
  puts "ERROR: Project $project_name not found at $project_dir"
  exit 1
}

open_project $project_dir

# Check if implementation is complete
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  launch_runs impl_1 -to_step write_bitstream -jobs 24
  wait_on_run impl_1
}

# Open implemented design
open_run impl_1

# Enable compression (as in Pavel Demin)
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# Write bitstream to project root
write_bitstream -force $project_name.bit

close_project

puts "Bitstream generated: $project_name.bit"