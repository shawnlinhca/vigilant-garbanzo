# Synthesize and implement the `network` module out of context (no board pins needed)
# and report resource usage and timing. Run via scripts/synth.sh, which runs this from
# a build folder containing the .mem files ($readmemh looks in the working directory).
#
# Optional environment variables:
#   CLK_NS   target clock period in ns (default 10.0 = 100 MHz)
#   TOP      top module (default network)

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize "$script_dir/.."]
set part       "xc7a35tcpg236-1"

set top "network"
if {[info exists ::env(TOP)]} { set top $::env(TOP) }
set clk_ns 10.0
if {[info exists ::env(CLK_NS)]} { set clk_ns $::env(CLK_NS) }

set rpt_dir "$repo_dir/docs/reports"
file mkdir $rpt_dir

read_verilog -sv [glob "$repo_dir/src/*.sv"]
synth_design -top $top -part $part -mode out_of_context
create_clock -period $clk_ns -name clk [get_ports clk]

opt_design
place_design
phys_opt_design
route_design

report_utilization              -file "$rpt_dir/utilization.rpt"
report_utilization -hierarchical -file "$rpt_dir/utilization_hier.rpt"
report_timing_summary           -file "$rpt_dir/timing_summary.rpt"
report_timing -nworst 1         -file "$rpt_dir/critical_path.rpt"

# ---- Short summary for the console ----
puts ""
puts "================ SUMMARY ($top, target ${clk_ns} ns) ================"
set fh [open "$rpt_dir/utilization.rpt" r]
foreach line [split [read $fh] "\n"] {
    if {[regexp {^\| *(Slice LUTs|CLB LUTs|Slice Registers|CLB Registers|Block RAM Tile|DSPs)} $line]} {
        puts $line
    }
}
close $fh

set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
puts "Worst setup slack (WNS): $wns ns"
puts [format "Estimated max clock: %.1f MHz" [expr {1000.0 / ($clk_ns - $wns)}]]
puts "Reports written to docs/reports/"
