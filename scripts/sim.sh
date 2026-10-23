#!/usr/bin/env bash
# Compile and run a SystemVerilog testbench with the Vivado simulator (xsim).
# Run from anywhere:  bash scripts/sim.sh [testbench_module]   (default: tb_top)
# Parallel MACs:      P=4 bash scripts/sim.sh tb_network       (tb_layer1 / tb_network only)
#                     needs weights/p4/ from: python python/export_parallel.py
# All generated files go in sim_build/, which is git-ignored.
#
# For P != 1 a small wrapper module is generated that instantiates the testbench with
# P set in code. (Passing P=4 on the command line does not work: Vivado's launchers are
# .bat files, and a .bat splits arguments at "=".)

set -e
TB="${1:-tb_top}"
P="${P:-1}"
VIVADO_BIN="${VIVADO_BIN:-/c/AMDDesignTools/2026.1/Vivado/bin}"

cd "$(dirname "$0")/.."            # repo root
mkdir -p sim_build
cd sim_build

# $readmemh looks in the simulator's working directory, so copy the .mem files here
if [ "$P" = "1" ]; then
    WDIR=../weights
else
    WDIR=../weights/p$P
    if [ ! -d "$WDIR" ]; then
        echo "Missing $WDIR  (run: python python/export_parallel.py $P)"
        exit 1
    fi
fi
cp -f $WDIR/*.mem .
cp -f ../tb/vectors/*.mem . 2>/dev/null || true

# Wrapper module for P != 1 (removed first so a stale one never lingers)
rm -f wrap_p.sv
TOP="$TB"
EXTRA=()
if [ "$P" != "1" ]; then
    TOP="${TB}_p${P}"
    printf '`timescale 1ns / 1ps\nmodule %s;\n    %s #(.P(%s)) u_tb ();\nendmodule\n' \
        "$TOP" "$TB" "$P" > wrap_p.sv
    EXTRA=(wrap_p.sv)
fi

"$VIVADO_BIN/xvlog.bat" -sv ../src/*.sv ../tb/*.sv "${EXTRA[@]}"
"$VIVADO_BIN/xelab.bat" "$TOP" -s "${TOP}_sim"
"$VIVADO_BIN/xsim.bat" "${TOP}_sim" -runall
