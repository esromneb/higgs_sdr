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
- No XSIM/Vivado executable is available in this environment.  Its installed
  Verilator is 4.016, which predates the SystemVerilog timing scheduler needed
  by the shared testbench.  The harness requires Verilator 5+ and has an
  `xsim` target for a Vivado host; cross-simulator comparison remains pending
  on a host with both tools.
- When the port reaches `vmem_dat_6_5_1_0`, inspect `fixcrossbar_higgs` and
  consider importing its complete relevant commit.  This is an explicit
  implementation dependency, not a request to duplicate the change manually.

## Memory policy

`scalar_memory_xilinx` uses four independent byte-wide arrays marked
`ram_style = "block"`.  This retains the original module's write-first,
byte-enable behavior while allowing Vivado to infer block RAM.  It avoids an
XPM dependency at this leaf.  Same-address simultaneous accesses through both
ports are unspecified by the original RTL and are not parity requirements;
the test fuzzes only defined transactions.
