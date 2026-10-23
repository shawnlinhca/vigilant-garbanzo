# FPGA Neural-Network Digit Classifier

A small MNIST digit classifier (784 → 32 → 10, int8 weights) implemented in SystemVerilog on a Digilent Basys 3 FPGA.

## Goal

Build a complete, measurable hardware inference pipeline: train a small model in Python, quantize it to int8, and run it on an FPGA using a MAC unit, block RAM for weights, a state-machine controller, ReLU, and argmax. Images are sent to the board over UART and the predicted digit is shown on the seven-segment display.

The project emphasizes clean SystemVerilog, self-checking testbenches, a bit-exact integer golden model, and measured results (accuracy, cycle count, resource usage, clock speed).

## Hardware and Tools

- **Board:** Digilent Basys 3 (Artix-7 XC7A35T-1CPG236C)
- **FPGA toolchain:** Xilinx Vivado 2026.1 (xsim for simulation)
- **Hardware language:** SystemVerilog
- **Training and golden model:** Python 3.13 (PyTorch, NumPy)
- **Development environment:** Windows, Git Bash, VS Code

## Roadmap

- [ ] 1. Basics: switches-to-LEDs warm-up and UART (both simulated; hardware run pending)
- [x] 2. Train a small model in Python (96.70% test accuracy, float32)
- [x] 3. Quantize to int8, write a pure-integer golden model, export `.mem` weights (96.73% test accuracy)
- [x] 4. One MAC unit with a self-checking testbench
- [x] 5. One layer with a single MAC, compared to the golden model
- [x] 6. Full network in simulation: 100/100 predictions match the golden model
- [ ] 7. Run on the board over UART (design, simulation, and bitstream done; hardware run pending)
- [ ] 8. Parallel MACs (4, 8, 16): measure cycles, LUT/DSP/BRAM, and clock speed

## Results

Measured so far (Python, simulation, and Vivado synthesis):

| Metric | Result | Measured by |
| --- | --- | --- |
| Float32 test accuracy (10,000 images) | 96.70% | `python/train.py` |
| Int8 test accuracy (10,000 images) | 96.73% | `python/golden.py` |
| Float vs. int8 prediction agreement | 99.85% | `python/golden.py` |
| Hardware vs. golden model (simulation) | 100/100 predictions identical | `tb/tb_network.sv` |
| Latency, one MAC per layer | 25,587 cycles per image | `tb/tb_network.sv` |
| Latency at the board's 100 MHz clock (timing met with margin) | about 256 µs per image | derived from cycle count |
| Accumulator width needed (worst case) | 26 bits (layer 1), 21 bits (layer 2) | analysis |
| Resources, `network` module only (post-route, out-of-context) | 1,487 LUTs (7.2%), 1,327 registers (3.2%), 9.5 BRAM tiles (19%), 2 DSPs (2.2%) | `scripts/synth.sh` |
| Timing, `network` module at a 125 MHz target (8 ns) | Met, worst setup slack +0.850 ns | `scripts/synth.sh` |
| Resources, full board design (post-route) | 1,586 LUTs (7.6%), 1,465 registers (3.5%), 9.5 BRAM tiles (19%), 2 DSPs (2.2%) | `scripts/build.sh` |
| Timing, full board design at 100 MHz | Met: setup slack +1.563 ns, hold slack +0.164 ns | `scripts/build.sh` |
| Bitstream | Generated; not yet run on hardware | `scripts/build.sh` |

Network-only numbers come from an out-of-context run of the `network` module (Vivado 2026.1, Artix-7 -1 speed grade), which does not model clock-buffer delay or skew. The full-board numbers come from `scripts/build.sh`, which implements `board_top` with the real pin constraints and clock buffer.

### Multiplier mapping: LUTs vs. DSP blocks

_Both runs below used a 10 ns target, before the timing fix in the next section._

By default Vivado built the 8x9-bit multiplier from LUTs. Adding `(* use_dsp = "yes" *)` to `src/mac.sv` moves each MAC's multiply-add into a DSP48 block. The network has two MACs (one per layer), hence 2 DSPs.

| | LUT multiplier | DSP-mapped | Change |
| --- | --- | --- | --- |
| LUTs | 1,726 | 1,552 | -174 (-10.1%) |
| Registers | 1,183 | 1,103 | -80 (-6.8%) |
| Block RAM tiles | 9.5 | 9.5 | none |
| DSPs | 0 | 2 | +2 |
| Worst setup slack at 10 ns | +0.562 ns | +0.975 ns | +0.413 ns |
| Estimated max clock | 106.0 MHz | 110.8 MHz | +4.5% |

The clock gain is small, so the multiplier was not the only limit on speed; the critical path is examined in `docs/reports/critical_path.rpt`.

### Timing: critical-path fix

With DSP-mapped MACs the worst path at the 10 ns target (8.58 ns, 55% routing) ran from a stored layer-1 accumulator through the ReLU/shift/clamp logic and a 32:1 read mux into layer 2's DSP. Registering the 32 hidden activations splits that into two short paths. It costs 224 registers and no latency (the cycle count is unchanged at 25,587). The design then meets an 8 ns target (125 MHz) with +0.850 ns slack, and the critical path moves to the image block RAM feeding layer 1's DSP. The board clock is 100 MHz and the full board build meets it with margin, so no further clock tuning is planned; DSP-internal pipeline registers plus an MMCM would be the next step to run faster.

Pending: on-board accuracy over UART, and the same measurements for 4, 8, and 16 parallel MACs.

## Architecture

```
image (784 x uint8) -> [image RAM] -> layer 1 (784 -> 32, one MAC) -> ReLU/shift/clamp
                                   -> layer 2 (32 -> 10, one MAC) -> argmax -> digit 0..9
```

- **Quantization:** int8 weights with one scale per layer; inputs stay as raw 0..255 pixel bytes; 32-bit biases and accumulators. Between layers the accumulator is rounded, shifted right by a constant (a power of two, so no multiplier is needed), and clamped to 0..127.
- **MAC unit** (`src/mac.sv`): signed 8-bit weight times signed 9-bit input, 32-bit accumulator, with a load input used to start each neuron at its bias.
- **Layer** (`src/layer.sv`): weights and biases are read from `.mem` files into block-RAM-style memories with a registered read. A state machine computes one neuron at a time and takes N_OUT × (N_IN + 4) cycles.
- **Argmax** (`src/argmax.sv`): sequential, one comparator, ties go to the lowest digit (same as NumPy).
- **UART receiver** (`src/uart_rx.sv`): 8N1 at 115,200 baud from the 100 MHz clock (868 clocks per bit), with a two-flop input synchronizer, mid-bit sampling, glitch rejection, and a framing-error flag.
- **UART loader** (`src/uart_loader.sv`): writes the 784 received bytes into the network's image memory, then starts the network. Framing errors, mid-image stalls (timeout), and bytes arriving while the network is busy discard the partial image so the stream always resyncs.
- **UART transmitter** (`src/uart_tx.sv`): same 8N1 format and baud generator as the receiver; sends the predicted digit back to the PC.
- **Seven-segment driver** (`src/seg7.sv`): shows the predicted digit (or "-" before a result) on the rightmost display digit.
- **Board top level** (`src/board_top.sv`): ties it together for the Basys 3. A PC sends 784 pixel bytes over the USB-UART; the board classifies the image, shows the digit on the seven-segment display, and replies with the digit as an ASCII character. LEDs show the last prediction, an image counter, and error/busy flags; the center button is reset.
- **Network** (`src/network.sv`): chains the pieces. Images are written in through a byte-wide write port, which the UART receiver will drive.

## Verification

Every testbench is self-checking and prints PASS or FAIL.

| Testbench | What it checks |
| --- | --- |
| `tb/tb_top.sv` | Switches-to-LEDs warm-up: fixed, walking-one, and random patterns |
| `tb/tb_mac.sv` | MAC against a reference model: priorities, worst-case sums, 200 random neurons (83,378 checks) |
| `tb/tb_layer1.sv` | Layer 1 against the Python golden model: all 32 raw accumulators and activations for 10 images, plus cycle count |
| `tb/tb_network.sv` | Full network against the golden model on real MNIST test images, loaded through the write port |
| `tb/tb_uart_rx.sv` | UART receiver: all 256 byte values back-to-back, bad stop bit, glitch rejection, and the real 868-clock bit time |
| `tb/tb_uart_loader.sv` | UART loader: full image, start only after the last write lands, and recovery from a framing error, a stall, and a busy network |
| `tb/tb_uart_tx.sv` | UART transmitter: all 256 values decoded by an independent line decoder, exact busy time, send-while-busy ignored, real baud rate |
| `tb/tb_seg7.sv` | Seven-segment driver: every digit, the error pattern, and the blank state, specified by lit-segment letters |
| `tb/tb_board_top.sv` | Whole board end to end: real MNIST images sent over a serial line, checking the ASCII reply, display, and LEDs, including recovery from a framing error mid-image |

The golden model (`python/golden.py`) is pure integer arithmetic and reads the same `.mem` files the hardware loads. `python/export_vectors.py` writes its expected values into `tb/vectors/`.

## Repo Layout

| Folder | Contents |
| --- | --- |
| `python/` | Training, quantization, integer golden model, test-vector export |
| `weights/` | Quantized weights and biases (`.mem`), float model, `quant_params.json` |
| `src/` | SystemVerilog design sources |
| `tb/` | Self-checking testbenches; `tb/vectors/` holds exported test vectors |
| `constraints/` | Basys 3 pin constraints: `board_top.xdc` (full build), `basys3.xdc` (old switches-to-LEDs warm-up) |
| `docs/` | Plots (`training_curve.png`) and Vivado synthesis/timing reports (`docs/reports/`) |
| `scripts/` | `create_project.tcl` (Vivado rebuild), `sim.sh` (run a testbench), `synth.sh` / `synth.tcl` (out-of-context synthesis and timing), `build.sh` / `build.tcl` (full board build and bitstream) |
| `vivado_proj/`, `sim_build/`, `synth_build/` | Generated, git-ignored |

## How to Run

All commands run from the repo root in Git Bash. Adjust the Vivado path if yours differs.

**1. Python environment** (once)

```bash
python -m venv .venv
source .venv/Scripts/activate
pip install -r requirements.txt
```

**2. Train, quantize, and check the golden model**

```bash
python python/train.py
python python/quantize.py
python python/golden.py
python python/export_vectors.py 100
```

**3. Simulate** (point `VIVADO_BIN` at your Vivado `bin` folder if it is not the default)

```bash
bash scripts/sim.sh tb_mac
bash scripts/sim.sh tb_layer1
bash scripts/sim.sh tb_network
```

**4. Synthesize and measure resources and timing** (no board needed; `CLK_NS` is the target clock period in ns)

```bash
bash scripts/synth.sh
CLK_NS=8.0 bash scripts/synth.sh
```

Reports land in `docs/reports/`.

**5. Build the bitstream** (full design with real pins; writes `synth_build/board_top.bit`)

```bash
bash scripts/build.sh
```

**6. Rebuild the Vivado project**

```bash
"/c/AMDDesignTools/2026.1/Vivado/bin/vivado.bat" -mode batch -source scripts/create_project.tcl
```

_Building and programming the Basys 3 will be documented once the UART and display modules are done._
