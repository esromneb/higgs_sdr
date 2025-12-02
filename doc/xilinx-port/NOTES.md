# Xilinx port notes

## 2025-12-01: baseline inspection

- The `higgs_sdr_rev2:xil` branch contains a working CS01 timing-only Vivado
  target.  Its selected part is `xczu7ev-ffvc1156-2-e`, and it replaces only
  the PLL, `core_top`, and the dual-clock FIFO for that configuration.
- The reference uses `HIGGS_FPGA_XILINX`, a 125 MHz input constraint, and a
  generated 125 MHz system-clock constraint.  Its README explicitly says
  board pin/I/O constraints are still required before bitstream programming.
- CS12 uses `vex_machine_top`, which brings in Q-engine and generated
  `XbbRiscv`.  The current first leaf is Q-engine `scalar_memory`.
- XSIM/Vivado 2025.2 is available at `/opt/amd/2025.2/Vivado/bin`; the
  shared SystemVerilog scalar-memory harness passed there.  The installed
  Verilator is 4.016 and does not support its timing scheduler, so the
  Verilator target uses an equivalent cycle driver with the same vectors,
  LFSR seed, checks, and CSV schema.  No newer Verilator or Cocotb is needed.
- When the port reaches `vmem_dat_6_5_1_0`, inspect `fixcrossbar_higgs` and
  consider importing its complete relevant commit.  This is an explicit
  implementation dependency, not a request to duplicate the change manually.
- The `fixcrossbar_higgs` `42eeee2` crossbar change was inspected when Vivado
  reached vector memory.  It still instantiates `memory_slice`, so it does not
  solve the unsupported RAM template and is intentionally not imported into
  the CS12 Xilinx port.
- CS12 synthesis completed successfully on 2025-12-01 for
  `xczu7ev-ffvc1156-2-e`.  The generated artifacts are
  `cs12_synth.dcp`, `cs12_synth_utilization.rpt`, and
  `cs12_synth_timing_summary.rpt` beneath `fpgas/cs/cs12/build/vivado/out`.
  They are intentionally ignored build products.
- CS12 place-and-route completed successfully on 2025-12-01.  The routed
  `sys_clk` constraint is 125 MHz with `WNS = +2.751 ns`, `TNS = 0.000 ns`,
  and no failing endpoints.  The routed utilization is 25,902 CLB LUTs
  (11.24%), 72 RAMB36E2 (23.08%), and 38 DSP48E2 (2.20%) on
  `xczu7ev-ffvc1156-2-e`.  The artifacts are `cs12_routed.dcp`,
  `cs12_routed_timing_summary.rpt`, `cs12_routed_utilization.rpt`,
  `cs12_clocks.rpt`, and `cs12_clock_interaction.rpt`.
- The routed result excludes board I/O timing signoff.  Pin locations,
  I/O standards, external interface clocks, configuration properties, a
  bitstream, programming, and hardware bring-up are not complete.
- Vivado reports duplicate declarations in the existing
  `generic_fifo_sc_a.v` during source processing, but completed synthesis and
  implementation with zero errors.  Treat these diagnostics as a follow-up
  review item before release rather than evidence of FIFO functional parity.
- The datapath portability change is committed in the `libs/datapath`
  submodule (`973676c`).  `HIGGS_FPGA_XILINX` selects behavioral
  `muladdsub` and `alu54b_wrapper_xilinx`, allowing Vivado to map the design
  to DSP48E2.  These replacements are integrated and routed but do not yet
  have dedicated cross-simulator parity tests.

## Memory policy

`scalar_memory_xilinx` uses four independent byte-wide arrays marked
`ram_style = "block"`.  This retains the original module's write-first,
byte-enable behavior while allowing Vivado to infer block RAM.  It avoids an
XPM dependency at this leaf.  Same-address simultaneous accesses through both
ports are unspecified by the original RTL and are not parity requirements;
the test fuzzes only defined transactions.

`memory_slice_xilinx` uses `xpm_memory_tdpram` because Vivado rejected the
original inferred true-dual-port template.  It uses a common clock, one-cycle
read latency, and write-first behavior on both ports.  Its memory
initialization is disabled because the original only loads MIF files when
`LOAD_VMEM` is defined; the CS12 Vivado target does not define it.  As with
the original RTL, same-address simultaneous-port behavior is not a contract.

## Overall goal and status

The overall goal is a board-ready Xilinx CS12 image with functional parity to
the Lattice/Verilator VexRiscv/Q-engine platform, followed by CS21 parity.
CS12 now has a routed integration checkpoint, but that is not functional or
board signoff.  The remaining proof is leaf-to-top simulator parity,
board-specific constraints, bitstream generation, programming, hardware
bring-up, and the subsequent CS21 port.
