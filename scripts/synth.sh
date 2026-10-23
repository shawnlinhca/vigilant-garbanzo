#!/usr/bin/env bash
# Synthesize + implement the network and print a resource/timing summary.
# Run from anywhere:  bash scripts/synth.sh
# Optional: CLK_NS=8.0 bash scripts/synth.sh     (target clock period in ns)
# Generated files go in synth_build/ (git-ignored); reports are copied to docs/reports/.

set -e
VIVADO_BIN="${VIVADO_BIN:-/c/AMDDesignTools/2026.1/Vivado/bin}"

cd "$(dirname "$0")/.."            # repo root
mkdir -p synth_build
cd synth_build

# $readmemh looks in the working directory, so copy the weight files here
cp -f ../weights/*.mem .

"$VIVADO_BIN/vivado.bat" -mode batch -source ../scripts/synth.tcl
