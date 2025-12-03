# `fwft_sc_fifo` parent-level parity harness

This harness verifies the first parent above the already-covered
`generic_fifo_sc_a` and `generic_dpram` leaves in the CS12 dependency
closure. `fwft_sc_fifo` has no Xilinx-specific implementation; both
simulators exercise the same portable RTL while independent transaction
scoreboards verify its externally observable FIFO contract.

The directed phases cover single-word first-word fall-through, output
stability during backpressure, burst ordering with valid gaps, simultaneous
read/write traffic, full-capacity fill and drain, and reset with transactions
in flight. A deterministic 5,000-cycle xorshift fuzz phase varies writes,
reads, idle cycles, backpressure, and reset. Writes are suppressed while
`full` is asserted because the underlying legacy FIFO explicitly declares
write-while-full undefined.

For `DEPTH=16`, the externally observable capacity is 18 words: the backing
FIFO stores 16 while the FWFT output and holding registers can each retain
one prefetched word. The scoreboard checks every consumed and presented
payload, not merely the number of outputs. It also checks that a valid output
does not change while `rden` is low, that `o_afull`/`o_afull_n` apply the
configured threshold to the prior-cycle `fillcount`, and that
`o_afull_n_d` is the documented one-cycle delayed form.

XSIM rejects duplicate declarations and mixed timescale usage in the legacy
`generic_fifo_sc_a.v`. The `gen` target therefore creates a build-only copy
that removes the redundant declarations and its lone timescale directive.
The production source is not modified.

Run:

```sh
export PATH=/opt/amd/2025.2/Vivado/bin:$PATH
make compare
```

The command builds independent Verilator and XSIM drivers, runs identical
directed/fuzz sequences with seed `0x6d2b79f5`, and compares their CSV traces.
