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
   or DSP macros needing dedicated parity harnesses; the next step is
   functional (not per-leaf-macro) verification: assembling and running the
   existing Q-engine-level test vectors against both toolchains.
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
directed-plus-fuzz simulator evidence. `XbbRiscv` (generated VexRiscv) needed
no dedicated leaf harness (portable Verilog, no vendor macros). System-level
integration is now proven at the `vex_machine_top` level: a real, compiled
RISC-V program runs identically on both simulators through the entire
assembled Q-engine/VexRiscv design (`fpgas/common/xilinx/sim/vex_machine_top/`).
The full CS12 and CS21 layers still need their planned hardware-level
evidence (board-constrained bitstream, programming, and bring-up tests).
