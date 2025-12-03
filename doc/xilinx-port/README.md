# Xilinx port worklog

This directory is the committed record for the CS12 Xilinx port.  The target
part is `xczu7ev-ffvc1156-2-e`, matching the existing `xil` branch proof of
concept.  The reference branch was inspected only with read-only Git commands.

## Overall goal

Produce a board-ready Xilinx CS12 image that preserves the observable
Lattice/Verilator behavior of the VexRiscv and Q-engine platform: the stream,
ring-bus, reset, memory, and processor interfaces must functionally match.
The work proceeds from proven leaves to their parents.  A successful routed
checkpoint is an integration gate, not completion: board-specific XDC,
bitstream generation, hardware bring-up, and CS21 parity remain required
before the overall goal is met.

The work is deliberately dependency-first: a parent is not ported until every
changed child has a simulator parity test.  `PLAN.md` is the execution order,
`CS12_HDL_MANIFEST.md` is the current Lattice build closure, and
`NOTES.md` records evidence and unresolved hardware-specific decisions.

Simulator tests belong alongside the specialized RTL in
`fpgas/common/xilinx/sim`.  XSIM uses a SystemVerilog harness; the installed
Verilator 4.016 uses an equivalent cycle driver with the same vectors, seed,
checks, and CSV schema.  The emitted traces must compare byte-for-byte.  For
RAMs, the contract is functional behavior at the transaction interface;
same-address dual-port collisions are deliberately excluded unless the
production architecture defines them.  `NOTES.md` records evidence,
deviations, and unresolved signoff work; update it at every synthesis,
routing, test, or hardware milestone.  Parent-level verification includes
`fpgas/common/xilinx/sim/fwft_sc_fifo/` and
`fpgas/common/xilinx/sim/vmem_dat_6_5/`.  The production CS12 overlay selects
`vmem_dat_6_5_1_1`, its generated SpinalHDL return arbiter, and the tagged
Xilinx memory slice.  The return arbiter has XSIM/Verilator trace parity, the
memory slice has a focused XSIM contract test, and the full parent has a
four-DMA/16-bank transaction scoreboard. The next boundary at
`fpgas/common/xilinx/sim/piston/` drives the same four DMA streams through the
real generated piston control/data edges and has matching XSIM/Verilator
traces. The direct parent boundary at
`fpgas/common/xilinx/sim/q_engine/` runs real RV32I firmware to configure
DMA-in and DMA-out over the production CSR bus, then verifies a deterministic
64-word backpressured stream loop through piston/VMEM, demapper, and slicer
with matching XSIM/Verilator traces.

Platform-level XSIM parity now also includes `sim/verilator/test_nco/`.
Its CS20 firmware configures the production NCO and DMA engines, and both
simulators independently verify and then exactly compare the complete
32,768-sample complex waveform.
