# Synthesize and implement the `network` module out of context (no board pins needed)
# and report resource usage and timing. Run via scripts/synth.sh, which runs this from
# a build folder containing the .mem files ($readmemh looks in the working directory).
#
# Optional environment variables:
#   P        parallel MACs per layer (default 1); reports go to docs/reports/p<P>/
#   CLK_NS   target clock period in ns (default 10.0 = 100 MHz)
#   TOP      top module (default network)

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize "$script_dir/.."]
set part       "xc7a35tcpg236-1"

set top "network"
if {[info exists ::env(TOP)]} { set top $::env(TOP) }
set clk_ns 10.0
if {[info exists ::env(CLK_NS)]} { set clk_ns $::env(CLK_NS) }
set P 1
if {[info exists ::env(P)]} { set P $::env(P) }

set rpt_dir "$repo_dir/docs/reports/p$P"
file mkdir $rpt_dir

read_verilog -sv [glob "$repo_dir/src/*.sv"]

set generics {}
if {$top eq "network" || $top eq "board_top"} { lappend generics -generic P=$P }
synth_design -top $top -part $part -mode out_of_context {*}$generics
create_clock -period $clk_ns -name clk [get_ports clk]

opt_design
place_design
phys_opt_design
route_design

report_utilization               -file "$rpt_dir/utilization.rpt"
report_utilization -hierarchical -file "$rpt_dir/utilization_hier.rpt"
report_timing_summary            -file "$rpt_dir/timing_summary.rpt"
report_timing -nworst 1          -file "$rpt_dir/critical_path.rpt"

# ---- Read the headline numbers back out of the utilization report ----
array set found {}
set fh [open "$rpt_dir/utilization.rpt" r]
foreach line [split [read $fh] "\n"] {
    if {[regexp {^\| *(Slice LUTs|CLB LUTs|Slice Registers|CLB Registers|Block RAM Tile|DSPs)\*? *\| *([0-9.]+) *\|} $line -> name val]} {
        if {![info exists found($name)]} { set found($name) $val }
    }
}
close $fh
proc pick {arrName args} {
    upvar $arrName a
    foreach n $args { if {[info exists a($n)]} { return $a($n) } }
    return "?"
}
set lut  [pick found "Slice LUTs" "CLB LUTs"]
set reg  [pick found "Slice Registers" "CLB Registers"]
set bram [pick found "Block RAM Tile"]
set dsp  [pick found "DSPs"]
set wns  [get_property SLACK [get_timing_paths -max_paths 1 -setup]]

# machine-readable summary (sourced by scripts/sweep.sh)
set sf [open "$rpt_dir/summary.txt" w]
puts $sf "LUT=$lut"
puts $sf "REG=$reg"
puts $sf "BRAM=$bram"
puts $sf "DSP=$dsp"
puts $sf "WNS=$wns"
puts $sf "TARGET_NS=$clk_ns"
close $sf

# ---- Short summary for the console ----
puts ""
puts "================ SUMMARY ($top, P=$P, target ${clk_ns} ns) ================"
puts "LUTs: $lut   Registers: $reg   BRAM tiles: $bram   DSPs: $dsp"
puts "Worst setup slack (WNS): $wns ns"
puts [format "Estimated max clock: %.1f MHz" [expr {1000.0 / ($clk_ns - $wns)}]]
puts "Reports written to docs/reports/p$P/"
