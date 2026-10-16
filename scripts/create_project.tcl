# Rebuilds the Vivado project from the sources in this repo.
# Run from the repo root:
#   vivado -mode batch -source scripts/create_project.tcl

set proj_name "digit_classifier"
set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize "$script_dir/.."]

# Basys 3 FPGA part (Artix-7 XC7A35T-1CPG236C)
create_project $proj_name "$repo_dir/vivado_proj" -part xc7a35tcpg236-1 -force

# Design sources (SystemVerilog)
set src_files [glob -nocomplain "$repo_dir/src/*.sv"]
if {[llength $src_files] > 0} { add_files -fileset sources_1 $src_files }

# Testbenches (simulation only)
set tb_files [glob -nocomplain "$repo_dir/tb/*.sv"]
if {[llength $tb_files] > 0} { add_files -fileset sim_1 $tb_files }

# Pin constraints
set xdc_files [glob -nocomplain "$repo_dir/constraints/*.xdc"]
if {[llength $xdc_files] > 0} { add_files -fileset constrs_1 $xdc_files }

# Weight files used by $readmemh
set mem_files [glob -nocomplain "$repo_dir/weights/*.mem"]
if {[llength $mem_files] > 0} { add_files -fileset sources_1 $mem_files }

puts "Project created: $repo_dir/vivado_proj/$proj_name.xpr"
