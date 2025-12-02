# `scalar_memory_xilinx` parity test

Run `make verilator` for the directed and deterministic 400-cycle fuzz test.
It uses a cycle driver compatible with the installed Verilator 4.016.  The
XSIM target runs the SystemVerilog harness; both drivers use the same directed
vectors, deterministic LFSR seed, defined memory contract, and CSV schema.
Run `make compare` to compare their traces.

The test initializes all addresses, covers concurrent non-colliding accesses,
write-first byte enables, reads, and idle cycles.  Same-address concurrent
writes and write/read collisions are intentionally omitted because the
original scalar memory does not define their behavior.
