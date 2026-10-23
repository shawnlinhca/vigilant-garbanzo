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

# Pin constraints for the board build (basys3.xdc is only for the old switches-to-LEDs warm-up)
set xdc_file "$repo_dir/constraints/board_top.xdc"
if {[file exists $xdc_file]} { add_files -fileset constrs_1 $xdc_file }

# Weight files used by $readmemh
set mem_files [glob -nocomplain "$repo_dir/weights/*.mem"]
if {[llength $mem_files] > 0} { add_files -fileset sources_1 $mem_files }

# Test vectors used by the testbenches
set vec_files [glob -nocomplain "$repo_dir/tb/vectors/*.mem"]
if {[llength $vec_files] > 0} { add_files -fileset sim_1 $vec_files }

# Top module for synthesis
set_property top board_top [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "Project created: $repo_dir/vivado_proj/$proj_name.xpr"
