# `muladdsub` parity test

`muladdsub` (`libs/datapath/rtl/muladdsub.v`) is the multiply-add/sub DSP
macro instantiated throughout Q-engine `piston.v` (16 instances). Unlike
`memory_slice`, it has **no separate Xilinx implementation file**:
`HIGGS_FPGA_XILINX` and `VERILATE` both select the exact same
`HIGGS_MULADDSUB_BEHAVIORAL_IMPL` branch inside `muladdsub.v`. The original
Lattice `ALU54B`/`MULT18X18D` primitive path (the ``else`` branch) is used
only for the real Lattice hardware build and cannot be simulated by either
open-source tool available here, so it is intentionally excluded from this
test's scope.

Because both simulators run identical source lines for this leaf, byte-level
cross-simulator agreement alone would be a weak proof (a bug in the shared
RTL would reproduce identically in both traces). This harness therefore adds
an independent, hand-written behavioral model of the same 3-stage,
per-stage-CE-gated pipeline (input latch on `CE0`, multiply latch on `CE1`,
final add/sub latch on `CE2`, async `RST0` clearing every stage), self-checks
the DUT against that model every cycle in both `tb_muladdsub_parity.sv`
(XSIM) and `verilator_muladdsub_parity.cpp` (Verilator), and *also* compares
their CSV traces of the DUT's stimulus/output for cross-simulator agreement.

- XSIM compiles `muladdsub.v` with `-d HIGGS_FPGA_XILINX`, matching the real
  CS12 Vivado build (`set_property verilog_define {HIGGS_FPGA_XILINX}`).
- Verilator compiles it with `+define+VERILATE`, this repo's existing
  Verilator convention (see `scripts/make_include/tb_common.mk` and
  `libs/q-engine/piston/Makefile`).
- Both selected defines route to the identical behavioral source lines, so
  this also proves the shared implementation used for CS12 Xilinx synthesis
  is exactly what every other Verilator-based regression in this repo already
  exercises.

Run `make verilator` and `make xsim` for the directed (reset, CE0/CE1/CE2
gating, signed-extreme operands) plus 1000-iteration deterministic LFSR fuzz
test, and `make compare` to diff their CSV traces via the shared
`../compare_traces.py`. Unlike `memory_slice`, no field in this leaf's trace
is ever undefined (`RST0` is asynchronous and clears every pipeline stage
immediately), so the traces are always byte-identical, not merely
`x`-tolerant.
