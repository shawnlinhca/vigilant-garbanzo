#!/usr/bin/env bash
# Build the Basys 3 bitstream and print a resource/timing summary.
# Run from anywhere:  bash scripts/build.sh
# Output: synth_build/board_top.bit (git-ignored) and reports in docs/reports/board_*.rpt

set -e
VIVADO_BIN="${VIVADO_BIN:-/c/AMDDesignTools/2026.1/Vivado/bin}"

cd "$(dirname "$0")/.."            # repo root
mkdir -p synth_build
cd synth_build

# $readmemh looks in the working directory, so copy the weight files here
cp -f ../weights/*.mem .

"$VIVADO_BIN/vivado.bat" -mode batch -source ../scripts/build.tcl
