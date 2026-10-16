"""Shared helpers for the quantization and golden-model scripts."""
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
WEIGHTS = ROOT / "weights"


def load_mnist_u8(train: bool):
    """Return (images, labels): images are uint8 0..255, shape (N, 784)."""
    from torchvision import datasets  # imported here so other helpers work without torch

    ds = datasets.MNIST(ROOT / "data", train=train, download=True)
    return ds.data.numpy().reshape(-1, 784).astype(np.uint8), ds.targets.numpy()
