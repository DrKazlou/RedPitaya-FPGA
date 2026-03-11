#vivado -nolog -nojournal -mode batch -source source/scripts/package_core.tcl -tclargs threshold_led

set name [lindex $argv 0]
set part xc7z020clg400-1

# Define output directory for the IP
set ip_dir IP/$name

# Create the directory if it doesn't exist
file mkdir $ip_dir

# Create temporary project inside the IP directory
create_project $name $ip_dir/temp_proj -part $part -force
set_property board_part "" [current_project]

# Read the Verilog file (relative from scripts folder)
#read_verilog source/core/$name.v

add_files -norecurse source/core/$name.v
set_property TOP $name [current_fileset]

set files [glob -nocomplain source/modules/*.v]
if {[llength $files] > 0} {
 add_files -norecurse $files
}

# Package the IP into the target directory
ipx::package_project -root_dir $ip_dir -vendor user.org -library user -taxonomy /UserIP -force
set core [ipx::current_core]

set_property name $name $core
set_property display_name "ADC $name" $core
set_property description "Simple verilog IP" $core
set_property supported_families {zynq Production} $core

ipx::infer_bus_interfaces $core
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core

# Clean up temporary project
close_project
#file delete -force $ip_dir/temp_proj


puts "SUCCESS! $name IP packaged"
puts "=================================="
