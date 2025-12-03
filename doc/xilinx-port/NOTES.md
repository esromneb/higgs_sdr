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
  implementation with zero errors.  This is no longer just a follow-up
  review item: building the `generic_fifo_sc_a` parity harness (see below)
  confirmed XSIM's `xvlog` frontend treats the same duplicate declarations
  as a hard `ERROR: [VRFC 10-9364]` that drops the whole module, i.e. it
  actually blocks simulation (not merely synthesis diagnostics). The
  harness works around this via a build-only, sed-patched copy that strips
  exactly the four duplicate lines; the committed legacy source is
  unmodified, and this same patch should be applied to any future
  simulation build of `generic_fifo_sc_a.v` on XSIM.
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
- `generic_dpram` and `generic_fifo_sc_a`
  (`libs/ip-library/fwft_fifos/sc_fifo/hdl/`, used via `fwft_sc_fifo` /
  `pmi_fifo_sc_fwft_v1_0` in the committed CS12 manifest) now have
  directed-plus-fuzz parity harnesses at
  `fpgas/common/xilinx/sim/generic_dpram/` and
  `fpgas/common/xilinx/sim/generic_fifo_sc_a/`.  Neither has a separate
  Xilinx implementation, so both are tested by self-checking against an
  independent shadow model on both simulators (same approach as
  `muladdsub`).  `generic_dpram`'s `dout` is an asynchronous, continuous
  read of `mem[read_addr]` (only the address is registered), so writing to
  the currently-latched read address changes `dout` immediately with no
  extra pipeline delay — directly exercised by a dedicated directed case.
  `generic_fifo_sc_a`'s shadow model discovered that its
  `fillcount`/`afull`/`afull_n`/`o_afull_n_d` register block responds only
  to `rst`, never to `clr`, unlike every other status register in the
  module (`wp`/`rp`/`gb`/`gb2`/`cnt`/`full_r`/`empty_r`/`full_n_r`/
  `empty_n_r`, which all respond to both); this asymmetry is faithfully
  reproduced rather than corrected.  Building this harness also surfaced a
  general Verilator caveat worth recording: `--top-module X` elaborates `X`
  with its own RTL-declared default parameters, silently ignoring any
  `#(...)` override written in a non-root SV testbench — the fix is
  explicit `-Gname=value` command-line flags at the Verilator invocation,
  and elaborated parameter values should always be spot-checked (e.g. via a
  `%Warning-WIDTH` log line) whenever this pattern is used with
  non-default parameters.
- **Investigated and scoped out: `pmi_fifo_dc` (the Lattice dual-clock
  async FIFO macro, replaced for the Xilinx CS12 build by an
  `xpm_fifo_async`-based wrapper at `fpgas/cs/cs12/build/vivado/hdl/pmi_fifo_dc.sv`,
  reached from the manifest via `mib_cdc.sv` → `pmi_fifo_dc_fwft_v1_0.sv`).**
  Traced its actual reachability: `mib_cdc.sv`'s own `VERILATE` generate
  branch (independent of `pmi_fifo_dc_fwft_v1_0`'s internal `VERILATE`
  parameter, which `mib_cdc.sv` never overrides) bypasses
  `pmi_fifo_dc_fwft_v1_0`/`pmi_fifo_dc` entirely whenever `VERILATE=1'b0` is
  not forced, substituting the single-clock `fwft_sc_fifo` (which
  unconditionally instantiates `generic_fifo_sc_a`, already covered by its
  own harness) for *any* simulation run with `VERILATE=1` — the same
  convention this whole session's Verilator/XSIM parity harnesses rely on.
  This means the real dual-clock `pmi_fifo_dc` macro (and, for Xilinx, the
  real `xpm_fifo_async`/`xpm_fifo_base` primitive it maps to) is a
  hardware-synthesis-only path never exercised by either toolchain's
  logic simulation in this repo's existing flow (confirmed Verilator 4.016
  cannot even parse the real `xpm_fifo.sv`, same class of limitation as
  `xpm_memory.sv`).  Building a bit-exact legacy-vs-Xilinx trace-parity
  harness for it would therefore not be preserving any existing simulated
  behavior (there is none to preserve) and is out of scope for this port's
  simulation-parity contract; the existing successful CS12 synthesis and
  routed implementation (zero errors, see above) is the only functional
  evidence available for this leaf pending real hardware bring-up.  A scan
  of the remaining CS12-manifest Q-engine/piston leaves (DMA, ring bus,
  `vmem_dat_6_5`/`vmem_ctrl_6_5`, and the rest of the piston control/data
  chain) found no other vendor memory or DSP macros beyond what is already
  covered; `vmem_dat_6_5.v`'s `n_mem_payload_*`/`q_mem_payload_*` arrays are
  small (16-deep) plain register arrays with no macro dependency, and the
  actual vector-memory RAM leaf is `memory_slice` (already covered).
- **Confirmed the same simulation-bypass pattern independently for
  `core_reset`/`sys_pll`.** `core_top.sv` (the CS12 manifest's replaced
  top-level module) gates its own `core_reset` instantiations behind
  `if (VERILATE) assign o_sys_clk_srsts = i_fpga_ext_arst; else core_reset
  #(...) ...`, i.e. `core_reset` (and therefore its internal
  `` `ifdef VERILATE_DEF `` branch, which itself has a real, pre-existing
  bug-compatible divergence — it hardcodes a fixed 1-clock reset-hold
  delay instead of honoring the real, per-output `EXTRA_RESET_CLOCKS`
  parameter) is never instantiated at all for CS12 under any `VERILATE=1`
  simulation run.  Combined with the `pmi_fifo_dc`/`sys_pll` finding above,
  every clock/reset-domain primitive this port's overlay replaces is
  architecturally bypassed for simulation the same way, for both
  toolchains, predating this porting effort — confirming PLAN.md item 3
  ("leaf arithmetic and clock/reset primitives") has no further
  vendor-macro leaves needing dedicated parity harnesses beyond
  `muladdsub`/`alu54b_wrapper` (the only two clock/reset-adjacent leaves
  actually exercised under `VERILATE=1`).  Also confirmed (via targeted
  `` `ifdef VERILATE_DEF ``/`HIGGS_FPGA_XILINX` greps across every
  manifest-closure file) that `ring_bus.v`, `dma_out.v`, and `q_engine.v`'s
  own `VERILATE_DEF` blocks are exclusively `` /*verilator public*/ ``
  debug-accessor hooks or a debug counter, with no functional divergence.

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

As of the `generic_dpram`/`generic_fifo_sc_a` milestone, every CS12-manifest
leaf with a genuine Lattice-vs-Xilinx or simulator-divergent behavior under
`VERILATE=1` (the convention every simulated run in this repo uses) has a
directed-plus-fuzz parity harness: `scalar_memory`, `memory_slice`,
`muladdsub`, `alu54b_wrapper`, `generic_dpram`, `generic_fifo_sc_a`.  A
systematic sweep of every remaining manifest file for `HIGGS_FPGA_XILINX`/
`VERILATE`/`VERILATE_DEF` conditionals (see above) found no further leaves
needing dedicated harnesses: the clock/reset/dual-clock-FIFO primitives
(`sys_pll`, `core_reset`, `pmi_fifo_dc`) are all bypassed for simulation by
design (both toolchains, predating this port), and the remaining
`VERILATE_DEF` occurrences in `ring_bus.v`/`dma_out.v`/`q_engine.v` are
debug-only accessor hooks.  What remains toward "leaf-to-top simulator
parity" is therefore integration-level, not per-leaf: assembling and running
functional test vectors through the composed Q-engine (DMA, ring bus,
piston/vector memory) and VexRiscv against both toolchains.  A large,
mature Verilator-based multi-FPGA system test suite already exists under
`sim/verilator/` (hundreds of tests); porting it to XSIM is a substantial,
separate undertaking and was intentionally not started without explicit
scope confirmation, since it is a different order of effort than the
leaf-harness work above.

## 2025-12-01: `XbbRiscv`/VexRiscv sweep and `vex_machine_top` integration harness

- **`XbbRiscv.v` (the generated VexRiscv wrapper, `libs/riscv-baseband/hdl/generated/`)
  needs no dedicated leaf parity harness.** Inspected in full: pure portable
  Verilog with no vendor-specific memory or DSP macros, no
  `HIGGS_FPGA_XILINX`/`VERILATE`/`VERILATE_DEF` conditionals of its own.
  Its correctness (real instruction fetch/execute, bus/CSR decode reaching
  a real peripheral) is instead proven as part of the new
  `vex_machine_top` integration harness below, which is a stronger, more
  direct test than an isolated leaf harness would have been (a leaf
  harness would have needed synthetic bus stimulus; running a real
  compiled program exercises the same logic paths for real).
- **Built `fpgas/common/xilinx/sim/vex_machine_top/`**, a system-level
  integration smoke test (not a per-leaf harness) satisfying PLAN item 7 in
  place of porting `sim/verilator` (explicitly out of scope for this
  port). Assembles the entire real design reachable from
  `fpgas/common/modules/vex_machine_top.v` (VexRiscv, `q_engine` bus/CSR
  decode, GPIO, all piston/DMA/ring-bus/NCO/vector-memory leaves) and runs
  one real, compiled RISC-V program (built with the real
  `/opt/riscv/bin/riscv32-unknown-elf-gcc` toolchain against the existing,
  previously-unused `libs/riscv-baseband/c/inc/crt_standard.S`/`ld_standard`
  infrastructure) through it under both Verilator and XSIM, comparing
  cycle traces. See that harness's `README.md` for full scope, the
  discovered `nco.v` forward-reference bug (tolerated by Verilator/Vivado,
  rejected by XSIM; fixed via a build-only generated copy, no legacy
  source modified), the XSIM "timescale mixing is all-or-nothing" rule
  (distinct from, and broader than, the single-pair fix already used for
  `generic_dpram`/`generic_fifo_sc_a`), and full validation results
  (`make compare` passes deterministically across repeated clean rebuilds;
  all six pre-existing leaf harnesses re-confirmed passing afterward, no
  cross-contamination).
- Fixed a real, pre-existing typo in `doc/xilinx-port/CS12_HDL_MANIFEST.md`
  (line 86: `perm_full_data_dat_1_1.v` → `perm_full_data_dat_2_1.v`,
  matching the file that actually exists), discovered while cross-checking
  this harness's Verilog manifest against that document.

## 2025-12-01/02: `sim/verilator/test_fft_lib_1` ported to XSIM (full ring-bus parity)

- Despite the "porting `sim/verilator` is out of scope" note above, this
  one existing Verilator test (`sim/verilator/test_fft_lib_1`, a real
  multi-FPGA CS20 FFT-library regression, not a synthetic leaf harness)
  was explicitly requested and ported to XSIM, reusing `tb.cpp`'s exact
  reset/stimulus/self-check logic in a new hand-written SystemVerilog
  testbench, `tb_higgs_top_xsim.sv`, against the unmodified
  `sim/hdl/tb_higgs_top.sv` DUT. See that test's own `README.md` for the
  full write-up; the two findings below are broadly applicable beyond
  this one test and are recorded here for that reason.
- **Missing register reset values (X-propagation) is a systemic issue
  across (at least) three independent IP trees**: Q-engine/piston
  (48 files), RISC-V-baseband's `fwft_sc_fifo.v`, and the generated
  8588-line `XbbRiscv.v` (497 regs). All were written and only verified
  against Verilator's 2-state engine (which implicitly starts every `reg`
  at `0`); XSIM is a real 4-state simulator where an unreset `reg` stays
  `X` until its first write, and elastic-pipeline handshake idioms in
  this codebase routinely gate that first write behind an expression that
  itself reads the still-`X` reg, causing permanent, unresolvable `X`
  propagation (observed as a full simulation hang). This is a
  pre-synthesis-simulation-only artifact — real silicon's flip-flop
  power-on `INIT` state is `0` absent an explicit initializer, matching
  Verilator's assumption — so the fix (`xsim_reg_init_fix.py`, mechanically
  adding `= 1'b0` to every internal, non-array `reg` declaration lacking
  one) is applied only to build-only generated copies, never to committed
  legacy RTL. **Any future XSIM harness reaching these same three IP
  trees (Q-engine/piston, `fwft_sc_fifo`, generated VexRiscv) should
  expect to need the same class of fix**, and can reuse
  `sim/verilator/test_fft_lib_1/xsim_reg_init_fix.py` directly.
- **Testbench-only bug, not a DUT bug**: the new `tb_higgs_top_xsim.sv`
  initially tied the DUT's only genuine UART RX input
  (`snap_eth_io_uart_rxd`) to a permanent logic-0 "break" condition
  instead of matching `tb.cpp`'s idle-high (`1`) convention
  (`inc/higgs_helper.hpp`'s `handle_uart_neg()`). This caused `eth_top`'s
  own onboard firmware (a separate CPU tile from the FFT-test firmware
  under test) to spuriously re-trigger its periodic ring-bus telemetry
  path hundreds of extra times, an artifact invisible to `tb.cpp`'s loose
  first/last-item self-check but which prevented an exact item-for-item
  match against Verilator. Fixed by tying it to `1`. This is a testbench-
  stimulus lesson (any new XSIM/SV testbench must idle-drive UART-style
  RX inputs high, not low/zero, to match the reference C++ harness), not
  a finding about the DUT itself.
- **Result**: confirmed exact match — both simulators produce
  `Ring got out 8 items.`, `[0xdeadbeef, 0x34, 0x6, 0x2, 0x1, 0x0, 0x0,
  0xf]`, and `All Tests Passed`, reproduced across two independent clean
  `xsim_run` invocations (determinism check).

## 2025-12-02: four more `sim/verilator` DMA regressions ported to XSIM

Following `test_fft_lib_1`'s pattern, four more pre-existing, CI-active
Verilator regressions under `sim/verilator/` were given XSIM parity
harnesses: `test_eth_dma`, `test_dma_slicer`, `test_cs20_dma`, and
`test_dma_fft`. Each got its own hand-written `tb_higgs_top_xsim.sv`
mirroring its `tb.cpp`'s exact reset/stimulus/self-check; see each test's
`README.md` for its specific expected ring-bus sequence and any
test-specific notes.

- **Shared build logic extracted.** `test_fft_lib_1`'s ~320-line
  `xsim_gen`/`xsim_compile`/`xsim_elab`/`xsim_run`/`xsim_compare` Makefile
  block (all of it DUT-config-independent: same `sim/hdl/tb_higgs_top.sv`,
  same set of build-only legacy-file patches) was factored out into
  `scripts/make_include/xsim_common.mk`, included by all 5 tests'
  Makefiles with one line each. Each test still owns its own
  `tb_higgs_top_xsim.sv` (the only genuinely test-specific piece) and
  `README.md`.
- **`compare_ringbus.py` generalized.** Originally hardcoded
  `test_fft_lib_1`'s own self-check (`first==0xdeadbeef`,
  `last==0xf`). Now it only requires both logs to independently contain
  the literal string `All Tests Passed` (each test's own `tb.cpp`/
  `tb_higgs_top_xsim.sv` already enforces its own specific pass/fail
  criteria internally) and that both simulators' captured ring-bus item
  streams match exactly. This makes the same script reusable, unmodified,
  across all 5 (and future) XSIM ports.
- **`EXTRA_RINGBUS` XSIM compile-order bug (genuine correctness fix,
  applies to all 5 tests).** `fpgas/grav/eth/hdl/eth_top.sv` locally
  declares `` `define EXTRA_RINGBUS `` immediately before its own
  `q_engine` instantiation, intending to enable `q_engine.v`'s second
  ring-bus submodule (`ring_bus_inst_2`, guarded by
  `` `ifdef EXTRA_RINGBUS``) for that instance. Verilog `` `define`` is a
  single global preprocessor stream, not instantiation-site-scoped: a
  module is compiled/elaborated exactly once, so whatever `` `ifdef``
  state existed when *that file* was analyzed applies uniformly to every
  instantiation. Because `q_engine.v` is analyzed by `xvlog` before
  `eth_top.sv` in `XSIM_SOURCES` order (confirmed via `xvlog.log`:
  `q_engine.v` at line 121, `eth_top.sv` at line 244), `eth_top.sv`'s
  local `` `define`` was always too late to affect `q_engine.v`'s own
  guard — XSIM silently never instantiated `ring_bus_inst_2` for *any*
  q_engine instance, leaving `o_ringbus` permanently floating and
  `eth_top`'s `HS_EAST_OUT_RB[47]` register (an `always_ff` with no
  reset) latching `X`/`Z` every cycle. This broke the CS-tile-to-ETH
  ring-bus return path for every test using it; only `test_dma_fft`
  actually exercises it (CS11's firmware sends 4 boot-marker ring-bus
  messages that must transit CS11→CS01→CS02→CS12→CS22→CS21→CS20→ETH),
  so the other tests never observed it as a failure. Verilator's build
  already instantiates `ring_bus_inst_2` for every q_engine instance
  (confirmed via `obj_dir/*.h`/`.cpp` symbols for all 5 parameterized
  variants, `q_engine__pi30/32/33/34/35`), so XSIM was diverging from
  Verilator's actual (and evidently intended) behavior, not the reverse.
  **Fix**: added `-d EXTRA_RINGBUS` to `XSIM_DEFINES` in
  `xsim_common.mk`, defining it globally on the `xvlog` command line
  (order-independent), matching Verilator's behavior exactly. Verified
  safe: `test_eth_dma`, `test_dma_slicer`, and `test_cs20_dma` were
  rebuilt clean and re-verified to still pass identically (this define
  only newly activates previously-dead logic; it does not change any
  other test's observable behavior).
- **`test_dma_fft`'s randomized stimulus made deterministic across
  simulators.** This test is a randomized glitch-detection regression
  (not fixed-stimulus/fixed-output). `tb.cpp`'s default mode reseeds
  from wall-clock time, which cannot be reproduced across separate
  Verilator invocations, let alone across simulators. `tb.cpp` was
  changed to set `fixed_seed = 1525241634` (a value the file's own
  author had already recorded as historically interesting, "After
  1900"); the current codebase's Verilator baseline reproducibly passes
  with this seed. To get true bit-exact stimulus parity,
  `tb_higgs_top_xsim.sv` reimplements glibc's `rand()`/`srand()` TYPE_3
  algorithm (deg=31, sep=3 additive feedback generator) from scratch,
  verified bit-for-bit against actual glibc output for this seed via a
  standalone C cross-check, producing the identical `cs11in`
  injection-timing schedule as Verilator's libc-backed `rand()`.
- **Two more testbench/build fixes found while porting these 4 tests
  (both broadly applicable, documented in-line in `xsim_common.mk`):**
  - `eth_top.sv`'s own instantiation of `core_top` passes a bare scalar
    `1'b0` to the unpacked-array parameter `MIB_CLK_SRSTS_EXTRA_CLOCKS`
    (size 1) — a call-site instance of the same packed-vs-unpacked-array
    literal issue already patched at `core_top.sv`/`core_reset.sv`'s own
    parameter *declarations*, but XSIM only rejected it here (`VRFC
    10-395`), not in `test_fft_lib_1`'s build, for the same design
    elaborated slightly differently — likely `xelab` optimizer-order
    nondeterminism rather than a real code difference. Fixed via one more
    `sed` patch in `xsim_common.mk`'s `eth_top.sv` generation rule.
  - `i_rx_ready_eth` (a `tb_higgs_top_xsim.sv` testbench signal wired to
    `eth_top`'s `split_fb_ready` input, gating whether `eth_top`'s
    `cs20_in_buffer` FIFO ever drains) was tied to constant `0` in every
    existing XSIM testbench (including `test_fft_lib_1`'s, retroactively
    fixed here too), but the reference Verilator harness
    (`higgs_helper.hpp`'s `eth_rx` port, `control_ready=1`) always drives
    it constant-`1`. Tying it to `0` silently backpressure-stalled
    CS20's DMA output after only ~78 items once the FIFO filled — latent
    but harmless in the low-volume tests (`test_fft_lib_1`/`test_eth_dma`/
    `test_dma_slicer`) but fatal in `test_cs20_dma`'s high-volume
    (14000+ item) scenario, which is how it was found. Fixed by tying
    `i_rx_ready_eth = 1` in all testbenches.
- **Physical ring-bus topology note.** While debugging `test_dma_fft`,
  traced the ring bus's actual physical daisy-chain path (distinct from
  the DMA/data path, `HS_*_IN/OUT`, which is unrelated): it is a genuine
  9-tile loop, `eth→cs11→cs01→cs02→cs12→cs22→cs21→cs20→eth`, not a
  simple linear chain. All 9 tiles are instantiated in this test
  (`CSxx_NO_RISCV=1` for the 5 tiles without real firmware — ring-bus
  relay present, RISC-V core absent).
- **Result**: all 4 tests confirmed exact XSIM/Verilator ring-bus
  match — `test_eth_dma`: `[0x1, 0x2, 0x3, 0x4]`; `test_dma_slicer`:
  235-item sequence; `test_cs20_dma`: 0 items (both self-checks still
  pass); `test_dma_fft`: `[0xdead, 0x8000, 0x8400, 0x8800]`, reproduced
  across two independent clean `xsim_compare` runs (determinism check).

## 2025-12-02: `fwft_sc_fifo` parent-level directed/fuzz parity

- Added `fpgas/common/xilinx/sim/fwft_sc_fifo/`, the first parent-level
  harness above the already-proven `generic_fifo_sc_a` and `generic_dpram`
  leaves.  This is the portable single-clock FIFO selected by the
  `VERILATE_DEF` branch of `pmi_fifo_sc_fwft_v1_0` and used directly by
  CS12-reachable `vex_machine_top` and `dma_out` paths.
- Both the XSIM testbench and Verilator cycle driver maintain independent
  transaction scoreboards.  They check every presented and consumed payload,
  first-word fall-through, stable output while backpressured, burst ordering
  with valid gaps, simultaneous reads and writes, reset with buffered
  transactions in flight, and a deterministic 5,000-cycle fuzz sequence
  using seed `0x6d2b79f5`.  Writes while `full` are excluded because the
  underlying legacy FIFO explicitly declares that transaction undefined.
- Directed filling characterized the wrapper's externally observable
  capacity as `DEPTH + 2`: the backing FIFO retains `DEPTH` entries while
  the FWFT output and holding registers each retain one prefetched word.
  The harness asserts this boundary for `DEPTH=16` and verifies complete
  ordered drain afterward.
- `make clean compare` passed with Verilator 4.016 and XSIM/Vivado 2025.2;
  the generated traces matched exactly under the shared
  `compare_traces.py`.  A deliberately corrupted cycle field was rejected
  by the comparator, confirming the comparison target fails on a real
  mismatch.
- As in the `generic_fifo_sc_a` leaf harness, XSIM uses a build-only copy
  that removes the legacy module's redundant declarations.  This parent
  harness also removes its lone `` `timescale`` directive so all three RTL
  modules use a consistent implicit timescale; no production source is
  modified.

## 2025-12-02: valid/ready-correct `vmem_dat_6_5_1_1`

- Imported the existing SpinalHDL VMEM work into `libs/spinal/` and made
  `VmemDatArbOut1_1.scala` authoritative for the generated
  `libs/spinal/hw/gen/VmemDatArbOut1_1.v`. SBT 1.10.2, Scala 2.13.14,
  SpinalHDL 1.11.0, and Java 17 regenerate the RTL with
  `make -C libs/spinal clean vao`.
- Corrected the generated arbiter's stream contract. Input `ready` now
  reports FIFO capacity independently of `valid`; order and data FIFOs pop
  only on an actual downstream `valid && ready` transfer. The order FIFO's
  readiness is exposed through `vmem_dat_arb_out_spinal_wrapper.v` and gates
  read acceptance in `vmem_dat_6_5_1_1`, so every accepted read reserves an
  ordering slot.
- `fpgas/common/xilinx/sim/vmem_dat_arb/` drives order reservations, memory
  returns, and four independently stalled DMA outputs with 512 deterministic
  transactions. Both simulators self-check against transaction scoreboards;
  `make clean compare` passes on Verilator 4.016 and XSIM 2025.2 with matching
  cycle traces.
- Added `memory_slice_1_1_xilinx.sv`, preserving the two DMA tag bits above
  the 12-bit RAM address and holding response address/data/valid stable under
  backpressure. Its focused XSIM test covers writes, reads, tags,
  backpressure, back-to-back requests, and defined simultaneous accesses on
  different addresses. Same-address dual-port collisions remain outside the
  portable contract.
- `fpgas/common/xilinx/sim/vmem_dat_6_5/` verifies the complete four-DMA,
  16-bank parent. It initializes through concurrent DMA writes, exercises a
  16-lane vector write/read with output backpressure, creates DMA bank
  conflicts and valid gaps, independently stalls all DMA outputs, asserts
  reset with queued reads, and then checks 512 ordered read responses. XSIM
  2025.2 passes.
- `piston.v` selects `vmem_dat_6_5_1_1` only under
  `HIGGS_FPGA_XILINX`. The CS12 Vivado overlay explicitly excludes
  `vmem_dat_6_5.v` and adds the replacement parent, wrapper, generated
  SpinalHDL RTL, `eb15`, and tagged XPM memory slice.
- Vivado 2025.2 synthesizes the selected hierarchy successfully for
  `xczu7ev-ffvc1156-2-e`. The log confirms elaboration of
  `vmem_dat_6_5_1_1`, `VmemDatArbOut1_1`, and `memory_slice_1_1`.
  Routed implementation also passes: `WNS = +2.186 ns`, `TNS = 0.000 ns`,
  zero unconstrained internal endpoints, 28,061 CLB LUTs, 72 RAMB36E2, and
  38 DSP48E2. Board I/O timing remains intentionally incomplete: 37 input
  and 37 output ports have no external delay constraints.
- On this host, unmodified Vivado repeatedly completed routing and then
  crashed in the licensing/WebTalk host probe inside system `libudev`, before
  writing the checkpoint. Scoping
  `LD_PRELOAD=/lib/x86_64-linux-gnu/libudev.so.1` to the `vivado` invocation
  avoided the allocator crash and produced all routed reports/checkpoints.
  Do not export this workaround globally.

## 2025-12-02: piston external-DMA parent parity

- Added `fpgas/common/xilinx/sim/piston/`, which instantiates the production
  `piston` with `HIGGS_FPGA_XILINX`, `MEMORY_SLICE_1_1`, and
  `VMEM_DAT_ARB_OUT_1_1`. Unlike the direct VMEM harness, requests and
  responses traverse piston's generated control/data elastic edges before
  reaching the Xilinx-selected VMEM hierarchy.
- The deterministic test concurrently initializes memory through all four
  DMA inputs, creates bank conflicts and input-valid gaps, queues reads before
  reset, verifies reset discards the queued responses, and checks 512 ordered
  reads while independently backpressuring all four DMA outputs.
- `make clean compare` passes with Verilator 4.016 and XSIM 2025.2. Both
  implementations pass their transaction scoreboards and emit identical
  414-cycle CSV traces. A deliberately corrupted trace is rejected by
  `compare_traces.py`.
- XSIM uses the vendor `xpm_memory_tdpram`; Verilator uses the existing
  configuration-specific model from the `memory_slice` harness. The model was
  extended only with the four disabled ECC status outputs required by
  `memory_slice_1_1_xilinx.sv`; the original `memory_slice` differential
  regression still passes.
- This is a focused external-DMA piston gate. `t_instr_req` remains low, so
  instruction-driven arithmetic, vector scheduling, and permutation behavior
  continue to rely on the existing `vex_machine_top` and platform regression
  evidence rather than being claimed by this harness.
- Compilation reports existing width warnings in the instruction/vector path,
  including 68-bit generated permutation edges connected to 64-bit
  `perm_full_*` ports and several legacy vector-slice expression widths. They
  occur in both simulator frontends, predate this harness, and are outside
  its idle-instruction DMA boundary; they are recorded rather than suppressed
  or treated as covered by this test.

## 2025-12-02: q_engine firmware-driven DMA parity

- Added `fpgas/common/xilinx/sim/q_engine/`, a direct production-`q_engine`
  harness using the Xilinx-selected scalar memory and valid/ready-correct
  VMEM hierarchy. A compiled RV32I program runs on the real generated
  `XbbRiscv`, configures DMA0 through the CSR bus, waits for its completion
  interrupt, then configures DMA1 and its final-`last` behavior.
- The external transaction path is
  `t0 -> dma_in -> piston/VMEM -> dma_out -> demapper/slicer -> i0`.
  The two independently written simulator drivers use seed `0x8c274a19`,
  add deterministic input-valid gaps, independently backpressure `i0`, and
  scoreboard all 64 payloads, ordering, final `last`, and timeout behavior.
- `make clean compare` passes with Verilator 4.016 and XSIM 2025.2. Both
  simulator-local scoreboards pass and their 454-cycle CSV traces match under
  `compare_traces.py`; XSIM's initially uninitialized output-valid field is
  the only don't-care. A deliberate defined-field corruption is rejected by
  the comparator.
- The test initially exposed an incomplete firmware setup: DMA1's `last` CSR
  was not programmed, so the final output correctly lacked `last`. The test
  firmware now writes `DMA_1_LAST_RTL=1`; no DUT behavior was changed.
- XSIM uses build-only copies for the already documented NCO forward
  declaration, duplicate FIFO declarations, and mixed-timescale
  `muladdsub` directive. These compatibility transformations do not alter
  committed production RTL. Verilator uses the existing configuration-specific
  XPM substitute because Verilator 4.016 cannot parse the vendor model.
- This gate covers the CPU/CSR-controlled external DMA loopback and composes
  DMA-in, piston/VMEM, DMA-out, demapper, and slicer. It does not newly claim
  ring-bus traffic, NCO operation, or instruction-driven vector/arithmetic
  behavior; those remain covered by the existing focused and platform tests.
