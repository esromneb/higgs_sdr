# `scalar_memory_xilinx` parity test

Run `make verilator` for the directed and deterministic 400-cycle fuzz test.
This target requires Verilator 5 or newer because it uses its native
SystemVerilog timing scheduler.  On a Vivado host, run `make compare` to
execute the identical SystemVerilog testbench under Verilator and XSIM and
compare their CSV traces.

The test initializes all addresses, covers concurrent non-colliding accesses,
write-first byte enables, reads, and idle cycles.  Same-address concurrent
writes and write/read collisions are intentionally omitted because the
original scalar memory does not define their behavior.
