# Full Basys 3 build: synthesize and implement `board_top` with the real pin constraints,
# report resources and timing, and write the bitstream. Run via scripts/build.sh.

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize "$script_dir/.."]
set part       "xc7a35tcpg236-1"
set rpt_dir    "$repo_dir/docs/reports"
file mkdir $rpt_dir

read_verilog -sv [glob "$repo_dir/src/*.sv"]
read_xdc "$repo_dir/constraints/board_top.xdc"

synth_design -top board_top -part $part
opt_design
place_design
phys_opt_design
route_design

report_utilization               -file "$rpt_dir/board_utilization.rpt"
report_utilization -hierarchical -file "$rpt_dir/board_utilization_hier.rpt"
report_timing_summary            -file "$rpt_dir/board_timing_summary.rpt"
report_timing -nworst 1          -file "$rpt_dir/board_critical_path.rpt"
report_drc                       -file "$rpt_dir/board_drc.rpt"

write_bitstream -force board_top.bit

# ---- Short summary for the console ----
puts ""
puts "================ SUMMARY (board_top) ================"
set fh [open "$rpt_dir/board_utilization.rpt" r]
foreach line [split [read $fh] "\n"] {
    if {[regexp {^\| *(Slice LUTs|CLB LUTs|Slice Registers|CLB Registers|Block RAM Tile|DSPs)} $line]} {
        puts $line
    }
}
close $fh

set clk_ns [get_property PERIOD [get_clocks sys_clk_pin]]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
puts "Clock period: $clk_ns ns"
puts "Worst setup slack (WNS): $wns ns"
puts "Worst hold slack (WHS): $whs ns"
puts [format "Estimated max clock: %.1f MHz" [expr {1000.0 / ($clk_ns - $wns)}]]
puts "Bitstream: synth_build/board_top.bit"
puts "Reports written to docs/reports/ (board_*.rpt)"
