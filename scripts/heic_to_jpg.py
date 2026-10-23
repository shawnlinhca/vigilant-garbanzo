"""Convert an iPhone HEIC photo to a README-sized JPEG.

Setup (once, venv active):   pip install pillow-heif
Usage:   python scripts/heic_to_jpg.py <input.HEIC> <output.jpg>
Example: python scripts/heic_to_jpg.py ~/Downloads/hardwareaccelerator.HEIC docs/board_demo.jpg
The photo is rotated upright, shrunk to at most 1600 px on its longest side, and saved
as a JPEG (typically a few hundred KB).
"""
import sys

from PIL import Image, ImageOps
from pillow_heif import register_heif_opener


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    register_heif_opener()
    src, dst = sys.argv[1], sys.argv[2]
    img = ImageOps.exif_transpose(Image.open(src)).convert("RGB")
    img.thumbnail((1600, 1600))
    img.save(dst, "JPEG", quality=85, optimize=True)
    print(f"Wrote {dst} ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    main()
