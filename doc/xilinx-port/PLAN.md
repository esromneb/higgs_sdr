# CS12 Xilinx port plan

## Scope and completion criteria

Port CS12 first, using `xczu7ev-ffvc1156-2-e`.  The overall goal is a
board-ready Xilinx image with functional parity at the VexRiscv/Q-engine
transaction interfaces, followed by the same proof for CS21.  The final CS12
image must implement with Vivado, meet the board-specific timing constraints,
program successfully, and function like the Lattice/Verilator configuration.
The request's reference to CS21 is a later parity gate; it does not change the
initial CS12 source closure.

## Ordered work

1. **Record the CS12 closure.** Done in `CS12_HDL_MANIFEST.md`; retain the
   existing Lattice list as the baseline and turn it into a Vivado source list.
2. **Port leaf memories first.** Done: `scalar_memory`, `memory_slice`
   (Q-engine vector memory), `generic_dpram`, and `generic_fifo_sc_a` (the
   FIFO storage leaves actually reachable from the CS12 manifest — Q-engine's
   own `dpram.sv`/`elastic_dpram.sv` and RISC-V's `dp_ram/generic_dpram.v`
   were confirmed unreachable from any CS12-manifest file and are out of
   scope) all have directed-plus-fuzz simulator evidence.  Inferred block RAM
   is used throughout; XPM memory is only used where `memory_slice_xilinx.v`
   requires it.
3. **Port leaf arithmetic and clock/reset primitives.** Done for the
   dataflow-reachable leaves: `muladdsub` and
   `alu54b_wrapper`/`alu54b_wrapper_xilinx` have directed-plus-fuzz
   simulator evidence.  The Lattice PLL (`sys_pll`) and the dual-clock FIFO
   macro (`pmi_fifo_dc`, reached via `mib_cdc.sv`) are replaced for the
   Xilinx build but are hardware-synthesis-only paths never exercised by
   either toolchain's logic simulation (`mib_cdc.sv`'s own `VERILATE`
   generate branch bypasses `pmi_fifo_dc_fwft_v1_0`/`pmi_fifo_dc` entirely
   for any simulated run, substituting the already-covered
   `fwft_sc_fifo`/`generic_fifo_sc_a`); see `NOTES.md` for the full
   investigation.  No further simulator-parity work is planned for
   `sys_pll`/`pmi_fifo_dc` pending real hardware bring-up.
4. **Assemble Q-engine bottom-up.** Verify each leaf, then DMA, ring bus,
   piston/vector memory, and `q_engine`.
   `fixcrossbar_higgs` (`42eeee2`) was inspected and found to still
   instantiate `memory_slice`; it does not solve the unsupported RAM
   template and was intentionally not imported.  A scan of the remaining
   piston/DMA/ring-bus leaves in the manifest found no other vendor memory
   or DSP macros needing dedicated parity harnesses.  Parent-level
   verification started with `fwft_sc_fifo`, the first wrapper above the
   already-covered `generic_fifo_sc_a`/`generic_dpram` leaves.  Its
   transaction-scoreboard harness proves first-word fall-through, payload
   ordering, output stability under backpressure, simultaneous traffic,
   effective capacity, reset in flight, and deterministic fuzz under both
   simulators.  The Xilinx-selected `vmem_dat_6_5_1_1` parent is also
   integrated and verified: its generated Spinal return arbiter has matching
   512-transaction XSIM/Verilator traces, its tagged XPM memory slice has a
   focused XSIM contract test, and the complete four-DMA/16-lane/16-bank
   parent passes vector write/read checks plus a 512-read DMA scoreboard with
   bank conflicts, valid gaps, output stalls, and reset in flight. Continue
   upward with `dma_out`, ring bus, and `q_engine`. The next composed boundary,
   `piston`, now also has a four-DMA external-interface harness: the XSIM and
   Verilator runs pass independent scoreboards and emit identical traces
   through piston's generated control/data elastic network. Its instruction
   input is intentionally idle in this focused test; instruction-driven
   arithmetic/vector coverage remains in the existing `vex_machine_top` and
   platform regressions.
5. **Assemble VexRiscv bottom-up.** Done: `XbbRiscv.v` (the generated
   VexRiscv wrapper) and its surrounding files were inspected and contain no
   vendor-specific memory or DSP macros — pure portable Verilog — so no
   dedicated leaf-level parity harness is needed for `XbbRiscv` itself;
   its correctness is instead exercised as part of the `vex_machine_top`
   integration harness (item 7).
6. **Create the CS12 Vivado target.** Done for synthesis and routed
   implementation: `build/vivado/build.tcl`, `implement.tcl`, 125 MHz clock
   constraint, and the Xilinx overlay produce a routed checkpoint.  Add the
   board-specific XDC before bitstream use.
7. **Integrate and prove.** Done: the `sim/verilator` regression suite was
   marked explicitly out of scope for this port, so a purpose-built
   `vex_machine_top`-level integration smoke test was written instead
   (`fpgas/common/xilinx/sim/vex_machine_top/`) — a real, compiled RISC-V
   program is run through the entire assembled design (VexRiscv, `q_engine`
   bus/CSR decode, GPIO, all piston/DMA/ring-bus/NCO/vector-memory leaves)
   under both Verilator and XSIM, with matching cycle traces (see that
   harness's `README.md` for full scope, discovered issues, and
   validation). Remaining: generate/program a board-constrained bitstream
   and run the existing hardware bring-up tests, then repeat the same proof
   for CS21 only after CS12 is stable.
8. **Port `sim/verilator/test_fft_lib_1` to XSIM.** Done: a real,
   pre-existing multi-FPGA Verilator regression (not a synthetic leaf
   harness) now also runs under XSIM via `tb_higgs_top_xsim.sv`, a
   hand-written SystemVerilog testbench mirroring `tb.cpp`'s exact
   stimulus/self-check. Confirmed an exact 8-item ring-bus match to
   Verilator's reference output on two independent runs. This surfaced
   two broadly-applicable findings recorded in `NOTES.md`: a systemic
   missing-register-reset (X-propagation) issue across Q-engine/piston,
   `fwft_sc_fifo.v`, and generated `XbbRiscv.v` (fixed via a reusable
   build-only patch script, `xsim_reg_init_fix.py`), and a UART-RX
   idle-level testbench-stimulus convention that any future SV testbench
   must match. See that test's `README.md` for full detail.
9. **Port four more `sim/verilator` DMA regressions to XSIM.** Done:
   `test_eth_dma`, `test_dma_slicer`, `test_cs20_dma`, and `test_dma_fft`
   each now have their own `tb_higgs_top_xsim.sv`, all confirmed exact
   ring-bus parity with Verilator. The shared, DUT-config-independent
   XSIM build logic from `test_fft_lib_1` was factored out into
   `scripts/make_include/xsim_common.mk` (included by all 5 tests'
   Makefiles), and `compare_ringbus.py` was generalized to check for a
   literal `All Tests Passed` self-report from each simulator rather than
   hardcoding one test's specific first/last-item values. This work
   surfaced and fixed one more genuine, broadly-applicable XSIM
   correctness bug: an `` `define EXTRA_RINGBUS`` compile-order/scope
   issue that silently disabled the CS-tile-to-ETH ring-bus return path
   for every XSIM test (see `NOTES.md` for the full root-cause
   derivation); fixed via a global `-d EXTRA_RINGBUS` in
   `xsim_common.mk`, verified non-breaking against all 4 other tests.
   `test_dma_fft` additionally needed a fixed PRNG seed
   (`fixed_seed = 1525241634` in `tb.cpp`) plus a from-scratch,
   bit-verified reimplementation of glibc's `rand()`/`srand()` in the SV
   testbench, since it is a randomized-stimulus regression. See each
   test's `README.md` for full detail.

## Milestone rule

Each new specialized RTL file and each simulator harness is committed as its
own milestone.  A test must include targeted boundary cases and deterministic
fuzzing.  XSIM-vs-Verilator is CSV equality for ordinary logic; RAM behavior
is compared through defined read/write transactions rather than unspecified
same-address, dual-write timing.

## Current implementation boundary

The routed CS12 checkpoint is an important integration result, but it is not a
release image.  There are no board pin, I/O voltage, external-interface
timing, configuration, or hardware bring-up constraints in the target.
Functional parity is now proven for `scalar_memory`, `memory_slice`
(XPM vector memory), `muladdsub`, `alu54b_wrapper`/`alu54b_wrapper_xilinx`
(currently unused in the CS12 dataflow, but part of the committed manifest
closure), and `generic_dpram`/`generic_fifo_sc_a` (the FIFO storage leaves
used via `fwft_sc_fifo`/`pmi_fifo_sc_fwft_v1_0`), each with
directed-plus-fuzz simulator evidence. Parent-level gates are complete for `fwft_sc_fifo` and the
Xilinx-selected `vmem_dat_6_5_1_1`; the latter includes focused memory-slice
testing, cross-simulator return-arbiter parity, a complete parent scoreboard,
and a fresh routed CS12 checkpoint. The external piston DMA boundary is also
covered with cross-simulator scoreboard and trace parity through the generated
piston control/data network. `XbbRiscv` (generated VexRiscv) needed no
dedicated leaf harness (portable Verilog, no vendor macros). System-level
integration is now proven at the `vex_machine_top` level: a real, compiled
RISC-V program runs identically on both simulators through the entire
assembled Q-engine/VexRiscv design (`fpgas/common/xilinx/sim/vex_machine_top/`).
A real pre-existing Verilator regression, `sim/verilator/test_fft_lib_1`,
now also has full XSIM parity (exact 8-item ring-bus match), which
surfaced and fixed a systemic missing-register-reset (X-propagation)
issue reusable by any future harness touching Q-engine/piston,
`fwft_sc_fifo`, or generated VexRiscv, plus a UART-RX testbench-stimulus
convention finding (see `NOTES.md`).
Four more real, pre-existing Verilator DMA regressions
(`test_eth_dma`, `test_dma_slicer`, `test_cs20_dma`, `test_dma_fft`) now
also have full XSIM parity, sharing `test_fft_lib_1`'s build logic via
`scripts/make_include/xsim_common.mk`. This surfaced and fixed one more
genuine XSIM-only correctness bug (an `` `define`` compile-order/scope
issue disabling the ring-bus's CS-tile-to-ETH return path), reusable by
any future harness reaching `eth_top.sv`/`q_engine.v` (see `NOTES.md`).
The full CS12 and CS21 layers still need their planned hardware-level
evidence (board-constrained bitstream, programming, and bring-up tests).
