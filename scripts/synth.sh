#!/usr/bin/env bash
# Synthesize + implement the network and print a resource/timing summary.
# Run from anywhere:  bash scripts/synth.sh
# Options (environment variables):
#   CLK_NS=8.0   target clock period in ns        (default 10.0)
#   P=4          parallel MACs per layer          (default 1; needs weights/p4/ from
#                                                  python python/export_parallel.py)
# Generated files go in synth_build/ (git-ignored); reports go to docs/reports/p<P>/.

set -e
VIVADO_BIN="${VIVADO_BIN:-/c/AMDDesignTools/2026.1/Vivado/bin}"
P="${P:-1}"
export P

cd "$(dirname "$0")/.."            # repo root
if [ "$P" = "1" ]; then
    WDIR=weights
else
    WDIR=weights/p$P
    if [ ! -d "$WDIR" ]; then
        echo "Missing $WDIR  (run: python python/export_parallel.py $P)"
        exit 1
    fi
fi

mkdir -p synth_build
cd synth_build

# $readmemh looks in the working directory, so copy the weight files here
cp -f ../$WDIR/*.mem .

"$VIVADO_BIN/vivado.bat" -mode batch -source ../scripts/synth.tcl
