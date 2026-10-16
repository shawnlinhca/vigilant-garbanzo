"""Export test vectors for the SystemVerilog testbenches from the golden model.

Run from the repo root:  python python/export_vectors.py [N]     (default N = 10)

Writes tb/vectors/ (all .mem, one value per line, two's complement hex):
  images.mem    8-bit,  784 lines per image
  exp_acc1.mem  32-bit,  32 lines per image   (layer-1 accumulators)
  exp_a1.mem    8-bit,   32 lines per image   (after ReLU/shift/clamp)
  exp_acc2.mem  32-bit,  10 lines per image   (layer-2 accumulators)
  exp_pred.mem  8-bit,    1 line  per image   (predicted digit)
  labels.mem    8-bit,    1 line  per image   (true digit)
The first N images of the MNIST test set are used.
"""
import sys

from common import ROOT, load_mnist_u8
from golden import infer, load_params
from quantize import write_mem


def export(x, y, m, out_dir, n):
    out_dir.mkdir(parents=True, exist_ok=True)
    x, y = x[:n], y[:n]
    r = infer(x, m)
    write_mem(out_dir / "images.mem", x, 8)
    write_mem(out_dir / "exp_acc1.mem", r["acc1"], 32)
    write_mem(out_dir / "exp_a1.mem", r["a1"], 8)
    write_mem(out_dir / "exp_acc2.mem", r["acc2"], 32)
    write_mem(out_dir / "exp_pred.mem", r["pred"], 8)
    write_mem(out_dir / "labels.mem", y, 8)
    return r


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    x, y = load_mnist_u8(train=False)
    r = export(x, y, load_params(), ROOT / "tb" / "vectors", n)
    print(f"Exported {n} images to tb/vectors/ "
          f"(golden predictions: {r['pred'].tolist()}, labels: {y[:n].tolist()})")


if __name__ == "__main__":
    main()
