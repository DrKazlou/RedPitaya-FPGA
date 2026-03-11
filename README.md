# RedPitaya-FPGA — 4-Channel DAQ System

A custom FPGA firmware and C data acquisition system for the **4-channel RedPitaya** (STEMlab 125-14 Quad, Zynq xc7z020clg400-1). The design captures triggered ADC waveforms from all four channels simultaneously, streams them to DDR via AXI DMA, and writes them to disk for offline analysis with ROOT.

## Acknowledgements

The scripted Vivado project approach used here — driving the full build flow (block design assembly, synthesis, implementation, and bitstream generation) entirely from Tcl without the GUI — was inspired by and originally based on **Pavel Demin's** [red-pitaya-notes](https://github.com/pavel-demin/red-pitaya-notes) project. Adopting this methodology drastically reduces the time and effort required to recreate or modify a bitstream compared to the standard GUI-driven workflow, and makes the entire build fully reproducible from the command line.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Step 1 — Package Verilog Cores as IP](#step-1--package-verilog-cores-as-ip)
- [Step 2 — Build the Vivado Project and Bitstream](#step-2--build-the-vivado-project-and-bitstream)
- [Step 3 — Convert the Bitstream for RedPitaya](#step-3--convert-the-bitstream-for-redpitaya)
- [Step 4 — Load the FPGA on RedPitaya](#step-4--load-the-fpga-on-redpitaya)
- [Step 5 — Compile and Run the DAQ Program](#step-5--compile-and-run-the-daq-program)
- [Step 6 — Analyze Data with ROOT](#step-6--analyze-data-with-root)
- [FPGA Architecture](#fpga-architecture)
- [Memory Map](#memory-map)
- [Binary Data Format](#binary-data-format)
- [DAQ Configuration Reference](#daq-configuration-reference)

---

## Project Overview

The system implements a hardware-triggered multi-channel waveform recorder:

1. The FPGA continuously digitizes all four ADC inputs at **125 MHz**.
2. Each channel has an independent **threshold comparator**. When the ADC value crosses the threshold, the FPGA arms a **triggered buffer** that captures 1025 64-bit words (one header + 1024 ADC samples) around the trigger point.
3. The captured packet is pushed through a clock-domain-crossing **AXI stream FIFO** and transferred to a reserved **DDR memory region** via a dedicated **AXI DMA** engine — one per channel.
4. A C program running on the Zynq ARM processor polls all four DMA engines, extracts a configurable window of 128 samples centred on the trigger, and writes events to per-channel binary files using a **double-buffered, multi-threaded** I/O scheme.
5. An **AXI Hub** peripheral exposes a configuration register (arm bit + four thresholds) and a status register (per-channel busy flags + hardware event-rate counters) to the PS.

---

## Repository Structure

```
RedPitaya-FPGA/
├── source/
│   ├── core/               # Top-level Verilog modules (one file per IP)
│   │   ├── adc_deserializer.v
│   │   ├── axis_triggered_buffer.v
│   │   ├── freq_counter.v
│   │   ├── threshold_led.v
│   │   └── axi_hub.v
│   ├── modules/            # Shared sub-modules included by the cores above
│   ├── scripts/
│   │   ├── package_core.tcl   # Wraps one Verilog core into a Vivado IP
│   │   ├── project.tcl        # Creates project, runs synth + impl + bitstream
│   │   ├── block_design.tcl   # Full AXI block design (sourced by project.tcl)
│   │   ├── build.tcl          # Standalone impl + bitstream (legacy helper)
│   │   └── generate.sh        # Converts .bit → .bit.bin for fpgautil
│   ├── red_pitaya.xml      # Board preset for PS7 configuration
│   └── *.xdc               # Pin/timing constraints
├── IP/                     # Auto-generated packaged IPs (created by package_core.tcl)
├── project/                # Auto-generated Vivado project (created by project.tcl)
└── DAQ/
    ├── daq_dma_4ch.c       # 4-channel DMA acquisition program (C, runs on RedPitaya)
    └── raw_single.c        # ROOT macro for single-channel binary file analysis
```

---

## Prerequisites

**On your workstation (build machine):**

- Xilinx Vivado **2025.1 
- `bootgen` available in `PATH` (ships with Vivado/Vitis)
- Bash shell


**For analysis (any Linux/macOS machine):**

- [ROOT](https://root.cern) 6.x with C++ support

---

## Step 1 — Package Verilog Cores as IP

Each custom Verilog module must be packaged as a Vivado IP before the block design can use it. Run `package_core.tcl` once per core, passing the core name as an argument. The script reads `source/core/<name>.v` and any shared modules from `source/modules/`, then writes the packaged IP to `IP/<name>/`.

Run from the **repository root**:

```bash
vivado -nolog -nojournal -mode batch \
  -source source/scripts/package_core.tcl \
  -tclargs adc_deserializer

vivado -nolog -nojournal -mode batch \
  -source source/scripts/package_core.tcl \
  -tclargs axis_triggered_buffer

vivado -nolog -nojournal -mode batch \
  -source source/scripts/package_core.tcl \
  -tclargs freq_counter

vivado -nolog -nojournal -mode batch \
  -source source/scripts/package_core.tcl \
  -tclargs threshold_led

vivado -nolog -nojournal -mode batch \
  -source source/scripts/package_core.tcl \
  -tclargs axi_hub
```

Each invocation prints `SUCCESS! <name> IP packaged` on completion. The resulting `IP/` directory is then registered as a custom IP repository by `project.tcl`.

> **Note:** Re-run this step whenever you modify a Verilog source file.

---

## Step 2 — Build the Vivado Project and Bitstream

`project.tcl` is the single entry point that does everything: creates the Vivado project, sources `block_design.tcl` to assemble the full AXI block design, runs synthesis (24 parallel jobs), runs implementation (opt → place → phys_opt → route), and generates a **compressed** bitstream.

Run from the **repository root**:

```bash
vivado -nolog -nojournal -mode batch \
  -source source/scripts/project.tcl
```

Expected output on success:

```
Wrapping done!
Synthesis done!
Starting implementation...
Implementation done!
Bitstream generated: project/adc_dma_4ch.bit
```

The full build takes roughly **3–5 minutes** depending on your machine.

---

## Step 3 — Convert the Bitstream for RedPitaya

RedPitaya's `fpgautil` requires a binary `.bit.bin` file rather than the raw Xilinx `.bit` file. The `generate.sh` script uses Vivado's `bootgen` to perform this conversion automatically.

```bash
bash source/scripts/generate.sh project/adc_dma_4ch.bit
```

On success you will see:

```
Running bootgen to generate adc_dma_4ch.bit.bin ...
Success! Generated: adc_dma_4ch.bit.bin
Load with: fpgautil -b adc_dma_4ch.bit.bin
```

Copy `adc_dma_4ch.bit.bin` to the RedPitaya (e.g. via `scp`):

```bash
scp adc_dma_4ch.bit.bin root@<redpitaya-ip>:/home/folder/
```

---

## Step 4 — Load the FPGA on RedPitaya

SSH into the RedPitaya and program the FPGA:

```bash
ssh root@<redpitaya-ip>
fpgautil -b /home/folder/adc_dma_4ch.bit.bin
```

The FPGA is now configured. The design initialises with the arm bit **cleared** — no triggers are accepted until the DAQ program sets it.

---

## Step 5 — Compile and Run the DAQ Program

All commands are run **on the RedPitaya** as root.

### Compile

```bash
gcc -O4 -o daq_dma_4ch daq_dma_4ch.c -pthread
```

### Configure (edit before compiling)

Open `daq_dma_4ch.c` and adjust the constants at the top of the file:

| Constant | Default | Description |
|---|---|---|
| `ACQ_DURATION` | `3600` | Acquisition time in seconds |
| `THRESHOLD_0..3` | `200 / 500 / 100 / 50` | Per-channel trigger thresholds (ADC counts, 14-bit) |
| `WINDOW_START` | `236` | First sample of the saved window (trigger fires at sample 256 in FPGA) |
| `WINDOW_SIZE` | `128` | Number of samples saved per event |
| `BATCH_COUNT` | `10` | Events accumulated before a disk-write flush |

### Run

```bash
./daq_dma_4ch
```

The program prints a live status line each second:

```
T:42/3600s | SW[1203,980,420,310] Hz | HW[1200,978,418,309] | Total[50526,41160,17640,13020] | B[0]
```

- **SW** — software-counted event rates per channel (Hz)
- **HW** — hardware frequency counters read from the FPGA status register
- **Total** — cumulative event counts
- **B** — per-channel busy flags (bitmask; `0` = all idle)

### Output files

Four binary files are written to the current directory:

```
raw_data_ch0.bin
raw_data_ch1.bin
raw_data_ch2.bin
raw_data_ch3.bin
```

---

## Step 6 — Analyze Data with ROOT

`raw_single.c` is a **ROOT macro** that reads one binary channel file and fills a set of diagnostic histograms saved to a ROOT file.

### Configure the macro

Edit the file name and paths near the top of `raw_single()`:

```cpp
const char* fileName = "raw_data_ch0";   // base name without .bin

// Adjust these paths to your local setup:
sprintf(localFile,  "/path/to/input/%s.bin",  fileName);
sprintf(output,     "/path/to/output/%s.root", fileName);
```

Set `fCopy = true` if you want the macro to pull the file from the RedPitaya over SCP before analysing it (requires `sshpass` and the correct `remoteHost`).

### Run

```bash
root -l -b -q 'raw_single.C'
```

### Output histograms

The macro produces a 3×3 canvas saved inside the ROOT file:

| Panel | Content |
|---|---|
| Peak position | Distribution of the trigger sample index within the window |
| Amplitude spectrum | Pulse height (ADC counts) |
| Integral spectrum | Total pulse integral |
| Amplitude vs Integral (2D) | Correlation between height and charge |
| PSD vs Amplitude (2D) | Pulse-shape discrimination vs height |
| PSD vs Integral (2D) | Pulse-shape discrimination vs charge |
| Trace example | Single waveform (event index set by `N_CHOSEN`) |
| Accumulated traces (2D) | All waveforms overlaid as a heatmap |

#### Analysis functions

- **Baseline subtraction** — averages the first `BL_CUT` (10) samples and subtracts the mean from the entire trace.
- **Amplitude & integral** — locates the peak sample; computes the full-trace integral and the PSD ratio `1 − Qs/Ql` where `Qs` is the short-gate integral and `Ql` is the tail integral starting from the peak.
- **Pile-up detection** — scans the derivative of the trace; flags events with more than one rising edge exceeding `PILEUP_THR` (100 ADC counts) separated by at least `MIN_PEAK_SEPARATION` (10 samples).
- **Bit-flip correction** — detects and corrects isolated ADC bit-flip artefacts (single samples that differ from both neighbours by more than 3000 counts).

---

## FPGA Architecture

```
ADC pins ──► adc_deserializer ──► adc_ch0..3  (125 MHz, 14-bit signed)
                                       │
                    ┌──────────────────┼──────────────────┐
                    ▼                  ▼                   ▼
              threshold_comparator  freq_counter    threshold_led
                    │                  │                   │
                    ▼                  ▼                   ▼
             axis_triggered_buffer  hub_0/sts        LED[7:0]
                    │
             axis_data_fifo  (async FIFO, CDC: 125 MHz → 125 MHz PS)
                    │
               axi_dma (S2MM only, 64-bit)
                    │
             AXI HP0 interconnect
                    │
                  PS DDR
```

**Key IP cores:**

| Core | Function |
|---|---|
| `adc_deserializer` | LVDS deserialisation of the dual-channel ADC input bus; outputs four 14-bit signed streams at 125 MHz and provides a 200 MHz reference for IDELAYCTRL |
| `axis_triggered_buffer` | Circular buffer; on a threshold crossing it freezes, outputs a 1025-word packet (64-bit header + 1024 samples), then waits to be re-armed |
| `axi_hub` | AXI-lite slave exposing a 128-bit config register (arm + 4 × 14-bit thresholds) and a 128-bit status register (4-bit busy + 4 × 28-bit frequency counters) |
| `freq_counter` | Counts threshold crossings per second for all four channels; result feeds `hub_0/sts_data` |
| `threshold_led` | Drives the 8 on-board LEDs as activity indicators |

---

## Memory Map

| Address | Size | Description |
|---|---|---|
| `0x40000000` | 64 KB | AXI Hub — configuration registers |
| `0x41000000` | 64 KB | AXI Hub — status registers |
| `0x40020000` | 64 KB | AXI DMA 0 — channel 0 control |
| `0x40030000` | 64 KB | AXI DMA 1 — channel 1 control |
| `0x40040000` | 64 KB | AXI DMA 2 — channel 2 control |
| `0x40050000` | 64 KB | AXI DMA 3 — channel 3 control |
| `0x18000000` | per packet | DDR destination buffer — channel 0 |
| `0x1A000000` | per packet | DDR destination buffer — channel 1 |
| `0x1C000000` | per packet | DDR destination buffer — channel 2 |
| `0x1E000000` | per packet | DDR destination buffer — channel 3 |

### Configuration register layout (`hub_cfg[0..1]`, 64-bit total)

| Bits | Field |
|---|---|
| `[0]` | ARM — set to 1 to enable triggers |
| `[14:1]` | THRESHOLD_0 (14-bit, channel 0) |
| `[28:15]` | THRESHOLD_1 (14-bit, channel 1) |
| `[42:29]` | THRESHOLD_2 (14-bit, channel 2) |
| `[56:43]` | THRESHOLD_3 (14-bit, channel 3) |

### Status register layout (`hub_sts[0..3]`, 128-bit total)

| Bits | Field |
|---|---|
| `[3:0]` | Busy flags (one per channel) |
| `[31:4]` | Hardware frequency counter — channel 0 |
| `[59:32]` | Hardware frequency counter — channel 1 |
| `[87:60]` | Hardware frequency counter — channel 2 |
| `[115:88]` | Hardware frequency counter — channel 3 |

---

## Binary Data Format

Each binary file contains a stream of fixed-size **event records**. Each record consists of:

```
[ 8 bytes — header (uint64_t)          ]
[ WINDOW_SIZE × 8 bytes — ADC samples  ]
```

Total record size: `(1 + WINDOW_SIZE) × 8` bytes = **1032 bytes** at default settings.

**Header word:**
- Bits `[47:0]` — 48-bit timestamp in ADC clock ticks (divide by 125 × 10⁶ for seconds)
- Bits `[63:48]` — reserved / channel metadata

**Sample words (64-bit each):**
- Bits `[13:0]` — 14-bit ADC value in two's complement (`> 8191` → subtract 16384)
- Upper bits — padding / channel tag from the triggered buffer
