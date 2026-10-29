---
trigger: always_on
description: >
---

# Project Core

## Repository & Tech Stack

- **HDL Standard:** Synthesizable Verilog-2001 (IEEE Std 1364-2001).
- **Target Hardware:** Cyclone V FPGA. DE0-CV Development Kit, 50 MHz clock.
- **Synthesis Toolchain:** Quartus Prime - Intel FPGA Edition.
- **Simulation:** Icarus Verilog / ModelSim.
- **Architecture:** Synchronous Digital Design. Top-Level to Control Unit FSM + Datapath to Submodules & M10K Memory.

# Testbenches & Simulation

- **Testbench Scope:** Every non-trivial module should have an accompanying self-checking testbench (`<module>_tb.v`).
- **Execution Workflow:**
  ```bash
  iverilog -o sim.vvp <module>.v tb_<module>.v
  vvp sim.vvp
  ```
- **Self-Checking Standard:** Testbenches must tally an `errors` integer and explicitly output sucess or failure.
- **Fast Simulation:** Override physical timing parameters to ensure simulations finish in milliseconds.

For deeper simulation harnesses, template, and waveform dumping: `docs/llm/testbench-guide.md`.