# `alu54b_wrapper` parity test

`alu54b_wrapper` (`libs/datapath/rtl/alu54b_wrapper.v`) wraps the Lattice
`ALU54B` 55-bit add/sub primitive. Unlike `muladdsub`, it *does* have a
separate Xilinx implementation file, `libs/datapath/rtl/alu54b_wrapper_xilinx.sv`
(the `HIGGS_FPGA_XILINX` branch instantiates it as a sub-shim), so this
harness follows the `memory_slice`-style dual-instantiation pattern: both the
legacy reference RTL and the Xilinx replacement are instantiated side by side
in `alu54b_dual_top.sv` and driven with identical stimulus every cycle.

`alu54b_wrapper.v` is a three-way `` `ifdef ``: `HIGGS_FPGA_XILINX` selects the
Xilinx sub-shim; `elsif VERILATE` selects a simple behavioral
`c <= subadd ? a-b : a+b`; the final `` `else `` instantiates the real Lattice
`ALU54B` primitive for hardware builds only, which neither open-source
simulator can elaborate, so it is out of scope here. Both testbenches force
the `VERILATE` branch of the reference file (via `+define+VERILATE` /
`-d VERILATE`) so only the one simulatable legacy branch is ever exercised.

**Note:** `alu54b_wrapper` is not instantiated anywhere in the active CS12
design (`muladdsub` is used instead, 16x in `piston.v`); only its own
testbench (`alu54b_wrapper_tb.v`) references it. It remains part of the
committed `CS12_HDL_MANIFEST.md` closure and was explicitly flagged in
`doc/xilinx-port/NOTES.md` as an untested leaf, so this harness closes that
gap even though the leaf is currently dead code in the synthesized dataflow.

## Build-only RTL patch

`alu54b_wrapper.v`'s `VERILATE` branch does a procedural (nonblocking)
assignment to `c`, but the module's ANSI port list declares
`output wire [54:0] c`. This is accepted by Vivado's synthesizer (the
manifest already builds this file for CS12) but is a genuine IEEE Verilog
violation — only `reg`/`var`-typed ports may be procedural-assignment
targets — and Verilator 4.016 correctly rejects it with
`%Error-PROCASSWIRE`. The `gen` Makefile target produces a build-only,
renamed copy of the reference file (already needed to avoid a module-name
clash with the Xilinx implementation) and, in the same step, additionally
patches this one port declaration from `wire` to `reg`. This is a pure
syntax/type correction with no behavioral effect (the signal is driven only
by that one always-block in the `VERILATE` branch in either case); the
committed legacy source `libs/datapath/rtl/alu54b_wrapper.v` is never
modified. The same generated copy is used for both the Verilator and XSIM
builds.

Verilator additionally emits (non-fatal) `%Warning-WIDTH` notices about the
`$signed` add/sub only "naturally" computing at 36 bits before being stored
into the 55-bit `c`. This was checked empirically: the live self-check in
both testbenches (`ref_c !== xil_c`, checked every cycle) passes with zero
mismatches across directed signed-extreme-operand vectors (e.g.
`max_pos + max_pos`, `max_neg - max_pos`) and a 1000-iteration fuzz test,
confirming Verilator's assignment-context sign-extension still produces the
full-precision 55-bit result despite the warning.

## Running

`make verilator` and `make xsim` run the directed (reset, signed extremes,
`ce`-toggling) plus 1000-iteration fuzz test, self-checking the two
instantiations against each other every cycle inside each simulator.
`make compare` diffs their CSV stimulus/output traces via the shared
`../compare_traces.py`. As with `muladdsub`, no field in this leaf's trace is
ever undefined (`rst` is asynchronous and clears the output immediately), so
the traces are effectively byte-identical, not merely `x`-tolerant.
