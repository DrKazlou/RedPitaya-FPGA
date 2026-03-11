#vivado -nolog -nojournal -mode batch -source source/scripts/project.tcl

package require fileutil

set project_name adc_dma_4ch
set part_name xc7z020clg400-1

# Create project in project/ subfolder
create_project $project_name project -part xc7z020clg400-1 -force

# Add the packaged IP repository (from root: IP/counter)
set_property ip_repo_paths source/../IP [current_project]


update_ip_catalog

proc wire {name1 name2} {
  set port1 [get_bd_pins $name1]
  set port2 [get_bd_pins $name2]
  if {[llength $port1] == 1 && [llength $port2] == 1} {
    connect_bd_net $port1 $port2
    return
  }
  set port1 [get_bd_intf_pins $name1]
  set port2 [get_bd_intf_pins $name2]
  if {[llength $port1] == 1 && [llength $port2] == 1} {
    connect_bd_intf_net $port1 $port2
    return
  }
  error "** ERROR: can't connect $name1 and $name2"
}

proc cell {cell_vlnv cell_name {cell_props {}} {cell_ports {}}} {
  set cell [create_bd_cell -type ip -vlnv $cell_vlnv $cell_name]
  set prop_list {}
  foreach {prop_name prop_value} $cell_props {
    lappend prop_list CONFIG.$prop_name $prop_value
  }
  if {[llength $prop_list] > 1} {
    set_property -dict $prop_list $cell
  }
  foreach {local_name remote_name} $cell_ports {
    wire $cell_name/$local_name $remote_name
  }
}

proc addr {offset range port master} {
  set object [get_bd_intf_pins $port]
  set segment [get_bd_addr_segs -of_objects $object]
  set config [list Master $master Clk Auto]
  apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config $config $object
  assign_bd_address -offset $offset -range $range $segment
}

create_bd_design system

source source/scripts/block_design.tcl

set system [get_files system.bd]
set_property SYNTH_CHECKPOINT_MODE None $system
generate_target all $system
make_wrapper -files $system -top
add_files -norecurse [glob -nocomplain project/$project_name.gen/sources_1/bd/system/hdl/system_wrapper.v]

set_property TOP system_wrapper [current_fileset]

set files [glob -nocomplain source/*.xdc]
if {[llength $files] > 0} {
  add_files -norecurse -fileset constrs_1 $files
}

puts "Wrapping done!"

launch_runs synth_1 -jobs 24
wait_on_run synth_1

puts "Synthesis done!"

open_run synth_1
# Implementation steps
puts "Starting implementation..."

opt_design
place_design
phys_opt_design
route_design

puts "Implementation done!"

# Bitstream generation with compression
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
write_bitstream -force project/$project_name.bit

puts "Bitstream generated: project/$project_name.bit"

close_project
