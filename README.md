# FPGA Neural-Network Digit Classifier

A small MNIST digit classifier (784 → 32 → 10, int8 weights) implemented in SystemVerilog on a Digilent Basys 3 FPGA.

## Goal

Build a complete, measurable hardware inference pipeline: train a small model in Python, quantize it to int8, and run it on an FPGA using MAC units, block RAM for weights, a state-machine controller, ReLU, and argmax. Images are sent to the board over UART and the predicted digit is shown on the seven-segment display.

The project emphasizes clean SystemVerilog, self-checking testbenches, a bit-exact integer golden model, and measured results (accuracy, cycle count, resource usage, clock speed).

## Hardware and Tools

- **Board:** Digilent Basys 3 (Artix-7 XC7A35T-1CPG236C)
- **FPGA toolchain:** Xilinx Vivado
- **Hardware language:** SystemVerilog
- **Training and golden model:** Python
- **Development environment:** Windows, Git Bash, VS Code

## Planned Roadmap

- [X] 1. Basics: switches-to-LEDs warm-up, UART
- [X] 2. Train a small model in Python (about 96.7% accuracy)
- [ ] 3. Quantize to int8, write a pure-integer golden model, export `.mem` weights
- [ ] 4. One MAC unit with a self-checking testbench
- [ ] 5. One layer with a single MAC, compared to the golden model
- [ ] 6. Full network in simulation, hardware accuracy vs Python
- [ ] 7. Run on the board over UART
- [ ] 8. Parallel MACs (4, 8, 16): measure cycles, LUT/DSP/BRAM, and clock speed; polish README

## Repo Layout

| Folder         | Contents                                         |
| -------------- | ------------------------------------------------ |
| `python/`      | Model training and the integer golden model      |
| `weights/`     | Quantized weight files (`.mem`)                  |
| `src/`         | SystemVerilog design sources                     |
| `tb/`          | Self-checking testbenches                        |
| `constraints/` | Basys 3 pin constraints (`.xdc`)                 |
| `docs/`        | Diagrams, waveforms, and notes                   |
| `scripts/`     | Helper scripts, including the Vivado Tcl rebuild |
| `vivado_proj/` | Generated Vivado project (git-ignored)           |

## How to Run

_Coming soon: instructions for training the model, running simulations, and building and programming the Basys 3._
