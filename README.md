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

- [ ] 1. Basics: switches-to-LEDs warm-up (simulated), UART (pending)
- [x] 2. Train a small model in Python (96.70% test accuracy, float32)
- [x] 3. Quantize to int8, write a pure-integer golden model, export `.mem` weights (96.73% test accuracy)
- [x] 4. One MAC unit with a self-checking testbench
- [x] 5. One layer with a single MAC, compared to the golden model
- [x] 6. Full network in simulation: 100/100 predictions match the golden model
- [ ] 7. Run on the board over UART
- [ ] 8. Parallel MACs (4, 8, 16): measure cycles, LUT/DSP/BRAM, and clock speed

## Results

Measured so far (simulation and Python):

| Metric | Result | Measured by |
| --- | --- | --- |
| Float32 test accuracy (10,000 images) | 96.70% | `python/train.py` |
| Int8 test accuracy (10,000 images) | 96.73% | `python/golden.py` |
| Float vs. int8 prediction agreement | 99.85% | `python/golden.py` |
| Hardware vs. golden model (simulation) | 100/100 predictions identical | `tb/tb_network.sv` |
| Latency, one MAC | 25,587 cycles per image | `tb/tb_network.sv` |
| Latency at an assumed 100 MHz clock | about 256 µs per image | derived from cycle count |
| Accumulator width needed (worst case) | 26 bits (layer 1), 21 bits (layer 2) | analysis |

Pending (needs synthesis and the board): achieved clock speed, LUT / DSP / BRAM usage, on-board accuracy over UART, and the same measurements for 4, 8, and 16 parallel MACs.

## Architecture

```
image (784 x uint8) -> [image RAM] -> layer 1 (784 -> 32, one MAC) -> ReLU/shift/clamp
                                   -> layer 2 (32 -> 10, one MAC) -> argmax -> digit 0..9
```

- **Quantization:** int8 weights with one scale per layer; inputs stay as raw 0..255 pixel bytes; 32-bit biases and accumulators. Between layers the accumulator is rounded, shifted right by a constant (a power of two, so no multiplier is needed), and clamped to 0..127.
- **MAC unit** (`src/mac.sv`): signed 8-bit weight times signed 9-bit input, 32-bit accumulator, with a load input used to start each neuron at its bias.
- **Layer** (`src/layer.sv`): weights and biases are read from `.mem` files into block-RAM-style memories with a registered read. A state machine computes one neuron at a time and takes N_OUT × (N_IN + 4) cycles.
- **Argmax** (`src/argmax.sv`): sequential, one comparator, ties go to the lowest digit (same as NumPy).
- **Network** (`src/network.sv`): chains the pieces. Images are written in through a byte-wide write port, which the UART receiver will drive.

## Verification

Every testbench is self-checking and prints PASS or FAIL.

| Testbench | What it checks |
| --- | --- |
| `tb/tb_top.sv` | Switches-to-LEDs warm-up: fixed, walking-one, and random patterns |
| `tb/tb_mac.sv` | MAC against a reference model: priorities, worst-case sums, 200 random neurons (83,378 checks) |
| `tb/tb_layer1.sv` | Layer 1 against the Python golden model: all 32 raw accumulators and activations for 10 images, plus cycle count |
| `tb/tb_network.sv` | Full network against the golden model on real MNIST test images, loaded through the write port |

The golden model (`python/golden.py`) is pure integer arithmetic and reads the same `.mem` files the hardware loads. `python/export_vectors.py` writes its expected values into `tb/vectors/`.

## Repo Layout

| Folder | Contents |
| --- | --- |
| `python/` | Training, quantization, integer golden model, test-vector export |
| `weights/` | Quantized weights and biases (`.mem`), float model, `quant_params.json` |
| `src/` | SystemVerilog design sources |
| `tb/` | Self-checking testbenches; `tb/vectors/` holds exported test vectors |
| `constraints/` | Basys 3 pin constraints (`.xdc`) |
| `docs/` | Diagrams, waveforms, and plots (`training_curve.png`) |
| `scripts/` | `create_project.tcl` (Vivado rebuild) and `sim.sh` (run a testbench) |
| `vivado_proj/`, `sim_build/` | Generated, git-ignored |

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

**4. Rebuild the Vivado project**

```bash
"/c/AMDDesignTools/2026.1/Vivado/bin/vivado.bat" -mode batch -source scripts/create_project.tcl
```

_Building and programming the Basys 3 will be documented once the UART and display modules are done._
