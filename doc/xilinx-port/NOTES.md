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
  to DSP48E2.  `muladdsub` and `alu54b_wrapper`/`alu54b_wrapper_xilinx` now
  both have dedicated cross-simulator parity evidence (see below).
- `memory_slice_xilinx` (the XPM true-dual-port vector memory used by
  Q-engine piston) now has a directed-plus-fuzz legacy-vs-Xilinx parity
  harness at `fpgas/common/xilinx/sim/memory_slice/`.  Unlike
  `scalar_memory`'s simulator-only self-consistency check, this harness
  instantiates the legacy reference `memory_slice.v` and
  `memory_slice_xilinx.v` side by side (`memory_slice_dual_top.sv`) and
  self-checks their outputs directly against each other every cycle, in
  addition to XSIM-vs-Verilator CSV trace comparison.  Verilator 4.016
  cannot parse the real vendor `xpm_memory.sv`, so its build substitutes a
  small hand-written behavioral model
  (`xpm_memory_tdpram_verilator_model.sv`) implementing only the exact
  configuration this design uses; XSIM always uses the real vendor model.
  A throwaway probe against the real `xpm_memory_tdpram` confirmed: `ena=0`
  holds the previous output value, write-first shows new data at the same
  one-cycle latency as a read, and same-address same-cycle access across
  ports with at least one write yields `x` (hardware-undefined, matching the
  reference `dpram`).  Both the legacy `dpram` and `xpm_memory_tdpram` commit
  writes whenever `we` is asserted, independent of `valid`; an earlier
  version of the fuzz stimulus incorrectly gated its same-address collision
  avoidance on `valid && we` instead of `we` alone, which missed real
  collisions and was fixed.  `make compare` treats any field reporting `x` as
  a don't-care match; in practice `x` only appears in the first post-reset
  cycle for port-1 pipeline registers before their first real transaction
  (a benign Verilator-zero-init vs. XSIM-leaves-undefined convention
  difference, confirmed to never recur across all 522 traced cycles).
- `muladdsub` (the multiply-add/sub DSP macro instantiated 16 times in
  Q-engine `piston.v`) now has a directed-plus-fuzz parity harness at
  `fpgas/common/xilinx/sim/muladdsub/`.  Unlike `memory_slice`, it has no
  separate Xilinx implementation file: `HIGGS_FPGA_XILINX` and `VERILATE`
  both select the identical `HIGGS_MULADDSUB_BEHAVIORAL_IMPL` branch inside
  `muladdsub.v` (the real Lattice `ALU54B`/`MULT18X18D` primitive path is
  used only for the Lattice hardware build and cannot be simulated by either
  tool here).  Because both simulators run the same source lines, the test
  self-checks the DUT every cycle against an independent hand-written model
  of the 3-stage, per-stage-CE-gated pipeline (rather than relying only on
  cross-simulator trace agreement, which would not catch a bug common to
  both).  XSIM compiles with `-d HIGGS_FPGA_XILINX` (matching the real CS12
  Vivado build define) and Verilator with `+define+VERILATE` (this repo's
  existing convention); `make compare` shows their traces are byte-identical
  with zero `x` occurrences (this leaf's async `RST0` clears every pipeline
  stage immediately, so nothing is ever left undefined, unlike
  `memory_slice`).
- `alu54b_wrapper` (the Lattice `ALU54B` 55-bit add/sub wrapper) now has a
  directed-plus-fuzz legacy-vs-Xilinx parity harness at
  `fpgas/common/xilinx/sim/alu54b_wrapper/`, following the same
  dual-instantiation pattern as `memory_slice` since it *does* have a
  distinct Xilinx implementation file (`alu54b_wrapper_xilinx.sv`). Both
  testbenches force `alu54b_wrapper.v`'s `VERILATE` behavioral branch (the
  only branch either open-source simulator can elaborate; the real Lattice
  `ALU54B` primitive path is hardware-build-only). Verilator 4.016 rejects
  that branch's procedural assignment to the ANSI-declared `output wire c`
  port (`%Error-PROCASSWIRE`) even though Vivado's synthesizer already
  accepts it for the real CS12 build; the harness's build-only `gen` step
  patches this one port declaration to `reg` in a generated, renamed copy
  (no behavioral effect, and the committed legacy source is never modified)
  to unblock Verilator elaboration for both simulators' builds. Verilator
  also emits non-fatal `%Warning-WIDTH` notices about the add/sub only
  "naturally" computing at 36 bits before assignment-context sign-extension
  widens it to the 55-bit output; the harness's per-cycle self-check
  (`ref_c !== xil_c`) across signed-extreme-operand directed vectors and a
  1000-iteration fuzz test confirms the final stored value is always
  full-precision-correct regardless of that warning. As with `muladdsub`,
  `rst` is asynchronous and clears the output immediately, so traces are
  effectively byte-identical with zero `x` occurrences. `alu54b_wrapper`
  remains unused anywhere in the active CS12 dataflow (`muladdsub` is used
  instead); this harness closes the previously-flagged parity-evidence gap
  for it regardless, since it remains part of the committed
  `CS12_HDL_MANIFEST.md` closure.

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
