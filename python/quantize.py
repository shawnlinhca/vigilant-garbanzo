"""Quantize the trained float model to int8 and export .mem files.

Run from the repo root:  python python/quantize.py

Reads:   weights/model_float.pt
Writes:  weights/w1.mem (8-bit), b1.mem (32-bit), w2.mem (8-bit), b2.mem (32-bit),
         weights/quant_params.json
Layout:  w1.mem is row-major [neuron][input]: address = neuron * 784 + input.
         w2.mem is [class][hidden]:           address = class * 32 + hidden.
Values are two's complement hex, one per line (ready for $readmemh).
"""
import json

import numpy as np

from common import WEIGHTS, load_mnist_u8

N_CAL = 10000  # training images used to pick the inter-layer shift


def quantize(w1, b1, w2, b2, x_cal):
    """Pure-numpy core. w1 (32,784), b1 (32,), w2 (10,32), b2 (10,), x_cal uint8 (N,784)."""
    # Layer 1: int8 weights. Real hidden value h = (s1/255) * acc1, so biases are
    # expressed in accumulator units of s1/255.
    s1 = np.abs(w1).max() / 127.0
    w1_q = np.clip(np.round(w1 / s1), -127, 127).astype(np.int8)
    s_acc1 = s1 / 255.0
    b1_q = np.round(b1 / s_acc1).astype(np.int32)

    # Pick a right-shift so the (99.9th percentile of the) hidden activations fit in 0..127.
    acc1 = np.maximum(x_cal.astype(np.float64) @ w1_q.T.astype(np.float64) + b1_q, 0)
    p = np.percentile(acc1, 99.9)
    shift1 = max(0, int(np.ceil(np.log2(p / 127.0))))

    # Layer 2: one hidden unit step is s_act = s_acc1 * 2^shift1 in real units.
    s_act = s_acc1 * (2 ** shift1)
    s2 = np.abs(w2).max() / 127.0
    w2_q = np.clip(np.round(w2 / s2), -127, 127).astype(np.int8)
    b2_q = np.round(b2 / (s2 * s_act)).astype(np.int32)

    return dict(w1=w1_q, b1=b1_q, w2=w2_q, b2=b2_q, shift1=shift1,
                s1=float(s1), s2=float(s2))


def write_mem(path, values, bits):
    mask = (1 << bits) - 1
    width = bits // 4
    with open(path, "w") as f:
        for v in np.asarray(values).flatten():
            f.write(f"{int(v) & mask:0{width}x}\n")


def main():
    import torch

    state = torch.load(WEIGHTS / "model_float.pt")
    w1 = state["0.weight"].numpy()
    b1 = state["0.bias"].numpy()
    w2 = state["2.weight"].numpy()
    b2 = state["2.bias"].numpy()

    x_train, _ = load_mnist_u8(train=True)
    q = quantize(w1, b1, w2, b2, x_train[:N_CAL])

    write_mem(WEIGHTS / "w1.mem", q["w1"], 8)
    write_mem(WEIGHTS / "b1.mem", q["b1"], 32)
    write_mem(WEIGHTS / "w2.mem", q["w2"], 8)
    write_mem(WEIGHTS / "b2.mem", q["b2"], 32)
    params = dict(n_in=784, n_hidden=32, n_out=10, shift1=q["shift1"],
                  w1_scale=q["s1"], w2_scale=q["s2"])
    (WEIGHTS / "quant_params.json").write_text(json.dumps(params, indent=2) + "\n")

    print(f"shift1 = {q['shift1']}")
    print("Wrote weights/w1.mem b1.mem w2.mem b2.mem quant_params.json")


if __name__ == "__main__":
    main()
