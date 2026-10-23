"""Write weight files for P parallel MACs per layer: weights/p{P}/{w1,b1,w2,b2}.mem

Run from the repo root:  python python/export_parallel.py [P ...]     (default: 4 8 16)

Layout: neurons are processed in groups of P (group g = neurons g*P .. g*P+P-1).
  w*.mem: one word per line, 2P hex digits = P int8 weights; neuron g*P+p is in bits [8p+7:8p].
          Word address = g * N_IN + i  (group-major, input index fastest).
  b*.mem: one word per group, 8P hex digits = P int32 biases; neuron g*P+p is in bits [32p+31:32p].
Neurons past N_OUT (padding in the last group) get weight 0 and bias 0.
Layer 1 uses P MACs; layer 2 uses min(P, 10), since it only has 10 outputs.
P = 1 needs no extra files: it uses weights/w1.mem etc. directly.
"""
import sys

import numpy as np

from common import WEIGHTS
from golden import load_params


def layout_weights(w, P):
    """w: (N_OUT, N_IN) ints -> list of hex lines, one P-weight word per line."""
    n_out, n_in = w.shape
    groups = -(-n_out // P)
    lines = []
    for g in range(groups):
        for i in range(n_in):
            word = 0
            for p in range(P):
                n = g * P + p
                v = int(w[n, i]) if n < n_out else 0
                word |= (v & 0xFF) << (8 * p)
            lines.append(f"{word:0{2 * P}x}")
    return lines


def layout_biases(b, P):
    """b: (N_OUT,) ints -> list of hex lines, one P-bias word per group."""
    n_out = len(b)
    groups = -(-n_out // P)
    lines = []
    for g in range(groups):
        word = 0
        for p in range(P):
            n = g * P + p
            v = int(b[n]) if n < n_out else 0
            word |= (v & 0xFFFFFFFF) << (32 * p)
        lines.append(f"{word:0{8 * P}x}")
    return lines


def main():
    ps = [int(a) for a in sys.argv[1:]] or [4, 8, 16]
    m = load_params()
    for P in ps:
        if P < 2:
            print("P=1 uses the original weights/*.mem files; nothing to export.")
            continue
        P2 = min(P, m["w2"].shape[0])
        out = WEIGHTS / f"p{P}"
        out.mkdir(exist_ok=True)
        files = {"w1.mem": layout_weights(m["w1"], P), "b1.mem": layout_biases(m["b1"], P),
                 "w2.mem": layout_weights(m["w2"], P2), "b2.mem": layout_biases(m["b2"], P2)}
        for name, lines in files.items():
            (out / name).write_text("\n".join(lines) + "\n")
        print(f"P={P}: wrote weights/p{P}/ (layer 1 uses {P} MACs, layer 2 uses {P2})")


if __name__ == "__main__":
    main()
