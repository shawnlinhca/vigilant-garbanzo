"""Train the 784 -> 32 -> 10 MNIST classifier in floating point.

Run from the repo root:  python python/train.py

Outputs:
  weights/model_float.pt      trained float32 weights (input to the quantization step)
  docs/training_curve.png     test accuracy per epoch (for the README)
MNIST is downloaded to data/ on the first run (git-ignored).
"""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")  # no window needed, just save the figure
import matplotlib.pyplot as plt
import numpy as np
import torch
import torch.nn as nn
from torchvision import datasets

ROOT = Path(__file__).resolve().parent.parent
SEED = 0
EPOCHS = 30
BATCH = 128
LR = 1e-3

torch.manual_seed(SEED)
np.random.seed(SEED)


def load(train: bool):
    """Return (images, labels). Pixels are scaled to 0..1 and flattened to 784."""
    ds = datasets.MNIST(ROOT / "data", train=train, download=True)
    x = ds.data.float().div(255.0).view(-1, 784)
    y = ds.targets
    return x, y


def accuracy(model, x, y):
    with torch.no_grad():
        return (model(x).argmax(dim=1) == y).float().mean().item()


def main():
    x_train, y_train = load(train=True)
    x_test, y_test = load(train=False)

    # Matches the hardware: one hidden layer of 32 with ReLU, 10 outputs.
    model = nn.Sequential(nn.Linear(784, 32), nn.ReLU(), nn.Linear(32, 10))
    opt = torch.optim.Adam(model.parameters(), lr=LR)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=EPOCHS)  # decay LR to ~0
    loss_fn = nn.CrossEntropyLoss()

    history = []
    for epoch in range(1, EPOCHS + 1):
        perm = torch.randperm(len(x_train))
        for i in range(0, len(perm), BATCH):
            idx = perm[i:i + BATCH]
            opt.zero_grad()
            loss = loss_fn(model(x_train[idx]), y_train[idx])
            loss.backward()
            opt.step()
        sched.step()
        acc = accuracy(model, x_test, y_test)
        history.append(acc)
        print(f"epoch {epoch:2d}  test accuracy {acc * 100:.2f}%")

    (ROOT / "weights").mkdir(exist_ok=True)
    (ROOT / "docs").mkdir(exist_ok=True)
    torch.save(model.state_dict(), ROOT / "weights" / "model_float.pt")

    plt.plot(range(1, EPOCHS + 1), [a * 100 for a in history], marker="o")
    plt.xlabel("Epoch")
    plt.ylabel("Test accuracy (%)")
    plt.title("784-32-10 MNIST classifier (float32)")
    plt.grid(True)
    plt.savefig(ROOT / "docs" / "training_curve.png", dpi=150, bbox_inches="tight")

    print(f"Final float accuracy: {history[-1] * 100:.2f}%")
    print("Saved weights/model_float.pt and docs/training_curve.png")


if __name__ == "__main__":
    main()
