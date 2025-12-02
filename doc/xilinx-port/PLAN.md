# CS12 Xilinx port plan

## Scope and completion criteria

Port CS12 first, using `xczu7ev-ffvc1156-2-e`.  The final image must elaborate,
implement with Vivado, and function at the CS12 transaction interfaces with
the same behavior as the Lattice/Verilator configuration.  The request's
reference to CS21 is treated as a later parity gate after CS12 is proven; it
does not change the initial CS12 source closure.

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
6. **Create the CS12 Vivado target.** Adapt the CS01 pattern: a CS12
   `build/vivado/build.tcl`, source manifest, portable replacement overlay,
   125 MHz clock constraint, and board-specific XDC before bitstream use.
7. **Integrate and prove.** Run shared XSIM/Verilator regressions from leaves
   through CS12, synthesize/place/route, then run the existing hardware
   bring-up tests.  Repeat the same proof for CS21 only after CS12 is stable.

## Milestone rule

Each new specialized RTL file and each simulator harness is committed as its
own milestone.  A test must include targeted boundary cases and deterministic
fuzzing.  XSIM-vs-Verilator is CSV equality for ordinary logic; RAM behavior
is compared through defined read/write transactions rather than unspecified
same-address, dual-write timing.
