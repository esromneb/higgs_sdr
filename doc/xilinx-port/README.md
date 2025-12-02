# Xilinx port worklog

This directory is the committed record for the CS12 Xilinx port.  The target
part is `xczu7ev-ffvc1156-2-e`, matching the existing `xil` branch proof of
concept.  The reference branch was inspected only with read-only Git commands.

The work is deliberately dependency-first: a parent is not ported until every
changed child has a simulator parity test.  `PLAN.md` is the execution order,
`CS12_HDL_MANIFEST.md` is the current Lattice build closure, and
`NOTES.md` records evidence and unresolved hardware-specific decisions.

Simulator tests belong alongside the specialized RTL in
`fpgas/common/xilinx/sim`.  They use one SystemVerilog testbench for XSIM and
Verilator, emit CSV traces, and compare those traces byte-for-byte.  For RAMs,
the contract is functional behavior at the transaction interface; same-address
dual-port collisions are deliberately excluded unless the production
architecture defines them.
