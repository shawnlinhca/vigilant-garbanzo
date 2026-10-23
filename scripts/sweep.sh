#!/usr/bin/env bash
# For each P: simulate the full network (latency in cycles, and a PASS check against the
# golden model), then synthesize it (resources and timing). Prints and saves a table.
#
# Run from anywhere:  bash scripts/sweep.sh              (P = 1 4 8 16)
#                     bash scripts/sweep.sh 1 4          (just these)
#                     CLK_NS=10.0 bash scripts/sweep.sh  (different clock target; default 8.0)
# Needs weights/p4, p8, p16 from: python python/export_parallel.py
# Takes about 4-5 minutes per P. Output: docs/reports/sweep.md

set -e
cd "$(dirname "$0")/.."
export CLK_NS="${CLK_NS:-8.0}"
PS=("$@")
if [ ${#PS[@]} -eq 0 ]; then PS=(1 4 8 16); fi

OUT=docs/reports/sweep.md
mkdir -p docs/reports sim_build
{
    echo "| MACs per layer (P) | Latency (cycles) | Latency at 100 MHz (µs) | LUTs | Registers | BRAM tiles | DSPs | Setup slack at ${CLK_NS} ns |"
    echo "| --- | --- | --- | --- | --- | --- | --- | --- |"
} > "$OUT"

for P in "${PS[@]}"; do
    echo "=== P=$P: simulation ==="
    sim_out=$(P=$P bash scripts/sim.sh tb_network)
    echo "$sim_out" | grep -E "PASS|FAIL|Latency" || true
    if ! echo "$sim_out" | grep -q "PASS: 100/100"; then
        echo "Simulation did not pass for P=$P; stopping."
        exit 1
    fi
    cycles=$(echo "$sim_out" | grep -oE 'Latency: [0-9]+' | grep -oE '[0-9]+')
    micros=$(awk "BEGIN { printf \"%.1f\", $cycles / 100 }")

    echo "=== P=$P: synthesis (this takes a few minutes) ==="
    P=$P bash scripts/synth.sh > "sim_build/synth_p$P.log" 2>&1 || {
        echo "Synthesis failed for P=$P; last lines of sim_build/synth_p$P.log:"
        tail -20 "sim_build/synth_p$P.log"
        exit 1
    }
    # shellcheck disable=SC1090
    source "docs/reports/p$P/summary.txt"
    echo "| $P | $cycles | $micros | $LUT | $REG | $BRAM | $DSP | $WNS ns |" >> "$OUT"
    echo "P=$P done: $cycles cycles, $LUT LUTs, $REG registers, $BRAM BRAM, $DSP DSPs, slack $WNS ns"
done

echo
echo "================ RESULTS ================"
cat "$OUT"
echo
echo "Saved to $OUT"
