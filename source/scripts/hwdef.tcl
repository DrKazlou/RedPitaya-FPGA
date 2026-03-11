#Example vivado -nolog -nojournal -mode batch -source source/scripts/hwdef.tcl

set project_name led_blinker_4ch

open_project project/$project_name.xpr

write_hw_platform -fixed -force -file project/$project_name.xsa

close_project