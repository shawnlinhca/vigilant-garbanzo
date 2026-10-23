# Program the Basys 3 over JTAG with a bitstream. Run via scripts/program.sh.
# Usage: vivado -mode batch -source scripts/program.tcl -tclargs <path/to/file.bit>

if {[llength $argv] < 1} {
    puts "ERROR: pass the bitstream path with -tclargs"
    exit 1
}
set bit [file normalize [lindex $argv 0]]
if {![file exists $bit]} {
    puts "ERROR: bitstream not found: $bit"
    exit 1
}

open_hw_manager
connect_hw_server
open_hw_target

set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "Programmed $dev with $bit"
close_hw_target
disconnect_hw_server
close_hw_manager
