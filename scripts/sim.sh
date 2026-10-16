#!/usr/bin/env bash
# Compile and run a SystemVerilog testbench with the Vivado simulator (xsim).
# Run from anywhere:  bash scripts/sim.sh [testbench_module]   (default: tb_top)
# All generated files go in sim_build/, which is git-ignored.

set -e
TB="${1:-tb_top}"
VIVADO_BIN="${VIVADO_BIN:-/c/AMDDesignTools/2026.1/Vivado/bin}"

cd "$(dirname "$0")/.."            # repo root
mkdir -p sim_build
cd sim_build

"$VIVADO_BIN/xvlog.bat" -sv ../src/*.sv ../tb/*.sv
"$VIVADO_BIN/xelab.bat" "$TB" -s "${TB}_sim"
"$VIVADO_BIN/xsim.bat" "${TB}_sim" -runall
