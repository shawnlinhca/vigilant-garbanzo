"""Stream MNIST test images to the Basys 3 over UART and measure on-board accuracy.

Run from the repo root (venv active):
    python python/send_images.py --list                    # show serial ports
    python python/send_images.py --port COM5 --n 1         # first try: one image
    python python/send_images.py --port COM5 --n 100
    python python/send_images.py --port COM5 --n 10000 --out docs/onboard_results.txt

Protocol: 784 raw pixel bytes at 115200 baud (8N1); the board replies with one ASCII digit.
Each reply is compared to the true label and to the Python integer golden model.
Sending one image takes about 68 ms (784 bytes x 10 bits / 115200), so 10,000 images is ~12 min.
"""
import argparse
import datetime
import time

import numpy as np

from common import load_mnist_u8
from golden import infer, load_params


def classify(port, image_bytes):
    """Send one image, return (digit or None, kind) where kind is 'ok', 'timeout' or 'bad_reply'."""
    port.reset_input_buffer()
    port.write(image_bytes)
    reply = port.read(1)
    if len(reply) == 0:
        return None, "timeout"
    b = reply[0]
    if 0x30 <= b <= 0x39:
        return b - 0x30, "ok"
    return None, "bad_reply"


def evaluate(port, images, labels, golden, resync_delay=0.2, progress_every=100):
    """Send every image; compare the board's answers to the labels and the golden model."""
    r = dict(n=len(images), board_correct=0, golden_correct=0, agree=0,
             timeouts=0, bad_replies=0, mismatches=[], seconds=0.0)
    t_start = time.perf_counter()
    for i in range(len(images)):
        pred, kind = classify(port, images[i].tobytes())
        if kind != "ok":
            r["timeouts" if kind == "timeout" else "bad_replies"] += 1
            r["mismatches"].append((i, None if kind == "timeout" else -1, int(golden[i]), int(labels[i])))
            # the board discards a stalled partial image after 0.1 s; wait it out, then resync
            time.sleep(resync_delay)
            port.reset_input_buffer()
        else:
            r["board_correct"] += int(pred == labels[i])
            r["agree"] += int(pred == golden[i])
            if pred != golden[i]:
                r["mismatches"].append((i, pred, int(golden[i]), int(labels[i])))
        r["golden_correct"] += int(golden[i] == labels[i])
        if progress_every and (i + 1) % progress_every == 0:
            print(f"  {i + 1}/{len(images)} images sent", flush=True)
    r["seconds"] = time.perf_counter() - t_start
    return r


def format_summary(r, start, port_name):
    n = r["n"]
    pct = lambda k: f"{100.0 * k / n:.2f}%" if n else "n/a"
    lines = [
        f"On-board test, {datetime.datetime.now():%Y-%m-%d %H:%M} ({port_name}, 115200 baud)",
        f"Images: {n} (MNIST test set, indices {start} to {start + n - 1})",
        f"Board accuracy vs. true labels : {r['board_correct']}/{n} ({pct(r['board_correct'])})",
        f"Golden model accuracy (same)   : {r['golden_correct']}/{n} ({pct(r['golden_correct'])})",
        f"Board agrees with golden model : {r['agree']}/{n} ({pct(r['agree'])})",
        f"No reply: {r['timeouts']}   Unexpected reply: {r['bad_replies']}",
        f"Average time per image (mostly UART transfer): {1000.0 * r['seconds'] / n:.1f} ms" if n else "",
    ]
    for (i, got, gold, lab) in r["mismatches"][:10]:
        got_s = "no reply" if got is None else ("unexpected reply" if got == -1 else str(got))
        lines.append(f"  mismatch: image {start + i}: board={got_s} golden={gold} label={lab}")
    return "\n".join(l for l in lines if l)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", help="serial port, e.g. COM5")
    ap.add_argument("--list", action="store_true", help="list serial ports and exit")
    ap.add_argument("--n", type=int, default=100, help="number of test images (default 100)")
    ap.add_argument("--start", type=int, default=0, help="index of the first test image")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--timeout", type=float, default=2.0, help="seconds to wait for a reply")
    ap.add_argument("--out", help="also write the summary to this file")
    args = ap.parse_args()

    if args.list:
        from serial.tools import list_ports
        ports = list(list_ports.comports())
        for p in ports:
            print(f"{p.device}: {p.description}")
        if not ports:
            print("No serial ports found.")
        return
    if not args.port:
        ap.error("--port is required (use --list to see the available ports)")

    x, y = load_mnist_u8(train=False)
    sel = slice(args.start, args.start + args.n)
    images, labels = x[sel], y[sel]
    golden = infer(images, load_params())["pred"]

    import serial
    with serial.Serial(args.port, args.baud, timeout=args.timeout, write_timeout=5) as port:
        time.sleep(0.2)
        port.reset_input_buffer()
        res = evaluate(port, images, labels, golden)

    text = format_summary(res, args.start, args.port)
    print()
    print(text)
    if args.out:
        with open(args.out, "a") as f:
            f.write(text + "\n\n")
        print(f"\nSummary appended to {args.out}")


if __name__ == "__main__":
    main()
