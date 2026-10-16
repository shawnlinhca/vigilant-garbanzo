"""Pure-integer golden model of the hardware. Reads the exported .mem files.

Run from the repo root:  python python/golden.py
Prints int8 accuracy on the 10,000 MNIST test images, agreement with the float
model, and the accumulator bit widths the hardware needs.
"""
import json

import numpy as np

from common import WEIGHTS, load_mnist_u8


def read_mem(path, bits):
    """Read a $readmemh-style file of two's complement hex values."""
    a = np.array([int(t, 16) for t in path.read_text().split()], dtype=np.int64)
    return np.where(a >= (1 << (bits - 1)), a - (1 << bits), a)


def load_params():
    p = json.loads((WEIGHTS / "quant_params.json").read_text())
    n_in, n_h, n_out = p["n_in"], p["n_hidden"], p["n_out"]
    return dict(
        w1=read_mem(WEIGHTS / "w1.mem", 8).reshape(n_h, n_in),
        b1=read_mem(WEIGHTS / "b1.mem", 32),
        w2=read_mem(WEIGHTS / "w2.mem", 8).reshape(n_out, n_h),
        b2=read_mem(WEIGHTS / "b2.mem", 32),
        shift1=p["shift1"],
    )


def infer(x_u8, m):
    """Integer-only inference. x_u8: uint8 array (N,784). Returns dict of intermediates."""
    acc1 = x_u8.astype(np.int64) @ m["w1"].T + m["b1"]          # layer 1 MACs + bias
    relu = np.maximum(acc1, 0)                                   # ReLU
    sh = m["shift1"]
    a1 = np.minimum((relu + ((1 << sh) >> 1)) >> sh, 127)        # round, shift, clamp 0..127
    acc2 = a1 @ m["w2"].T + m["b2"]                              # layer 2 MACs + bias
    return dict(acc1=acc1, a1=a1, acc2=acc2, pred=acc2.argmax(axis=1))


def main():
    import torch

    m = load_params()
    x, y = load_mnist_u8(train=False)
    r = infer(x, m)
    int_acc = (r["pred"] == y).mean()

    state = torch.load(WEIGHTS / "model_float.pt")
    xf = torch.from_numpy(x).float() / 255.0
    h = torch.relu(xf @ state["0.weight"].T + state["0.bias"])
    fl = (h @ state["2.weight"].T + state["2.bias"]).argmax(dim=1).numpy()

    print(f"Float accuracy : {(fl == y).mean() * 100:.2f}%")
    print(f"Int8 accuracy  : {int_acc * 100:.2f}%")
    print(f"Agreement with float model: {(fl == r['pred']).mean() * 100:.2f}%")
    for name in ("acc1", "acc2"):
        mx = int(np.abs(r[name]).max())
        print(f"{name}: max |value| = {mx}  ->  needs {mx.bit_length() + 1} signed bits")


if __name__ == "__main__":
    main()
