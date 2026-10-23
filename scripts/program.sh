#!/usr/bin/env bash
# Program the Basys 3 with the built bitstream (it is lost when the board loses power).
# Run from anywhere:  bash scripts/program.sh [path/to/file.bit]   (default: synth_build/board_top.bit)

set -e
VIVADO_BIN="${VIVADO_BIN:-/c/AMDDesignTools/2026.1/Vivado/bin}"

cd "$(dirname "$0")/.."            # repo root
BIT="${1:-synth_build/board_top.bit}"
if [ ! -f "$BIT" ]; then
    echo "Bitstream not found: $BIT   (run: bash scripts/build.sh)"
    exit 1
fi

"$VIVADO_BIN/vivado.bat" -mode batch -source scripts/program.tcl -tclargs "$BIT"
