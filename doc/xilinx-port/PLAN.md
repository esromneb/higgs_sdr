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
2. **Port leaf memories first.** Start with Q-engine `scalar_memory`, then
   Q-engine `dpram`/`elastic_dpram`, RISC-V `generic_dpram`, and FIFO storage.
   Use inferred block RAM with explicit read-during-write tests.  Do not
   instantiate XPM memories until inference fails timing or resource goals.
3. **Port leaf arithmetic and clock/reset primitives.** Replace the Lattice
   PLL and any vendor DSP/IP only after their portable behavior is covered.
4. **Assemble Q-engine bottom-up.** Verify each leaf, then DMA, ring bus,
   piston/vector memory, and `q_engine`.
   Before porting `vmem_dat_6_5_1_0`, inspect `fixcrossbar_higgs`; it may be
   necessary to take that complete, known-good commit rather than recreate its
   crossbar/memory changes piecemeal.
5. **Assemble VexRiscv bottom-up.** Verify generated `XbbRiscv`, its program
   memory, and `vex_machine_top` against the existing CS12 interfaces.
6. **Create the CS12 Vivado target.** Done for synthesis and routed
   implementation: `build/vivado/build.tcl`, `implement.tcl`, 125 MHz clock
   constraint, and the Xilinx overlay produce a routed checkpoint.  Add the
   board-specific XDC before bitstream use.
7. **Integrate and prove.** Run shared XSIM/Verilator regressions from leaves
   through CS12, add a CS12-level functional test, generate/program a
   board-constrained bitstream, then run the existing hardware bring-up tests.
   Repeat the same proof for CS21 only after CS12 is stable.

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
Functional parity is now proven for `scalar_memory` and `memory_slice`
(XPM vector memory), each with directed-plus-fuzz simulator evidence; the
DSP, FIFO, full Q-engine, VexRiscv, CS12, and CS21 layers still need their
planned simulator and hardware-level evidence.
