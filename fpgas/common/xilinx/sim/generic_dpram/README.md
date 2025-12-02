# `generic_dpram` parity test

`generic_dpram` (`libs/ip-library/fwft_fifos/sc_fifo/hdl/generic_dpram.v`) is
the simple dual-port memory leaf used by `generic_fifo_sc_a` (in turn used by
`fwft_sc_fifo` / `pmi_fifo_sc_fwft_v1_0`, all in the committed CS12
manifest). It has no separate Xilinx implementation and no reset pin (real
block RAM contents are undefined until written), so — like `scalar_memory` —
it is tested by directed vectors plus a deterministic fuzz test, run
identically on both simulators.

Unlike `scalar_memory`, this harness also self-checks the DUT every cycle
against a small, independently-written shadow model (`shadow_mem` +
`shadow_read_addr` in both `tb_generic_dpram_parity.sv` and
`verilator_generic_dpram_parity.cpp`), because reading the RTL closely
reveals a subtlety worth directly verifying: `dout` is an *asynchronous,
continuous* read of `mem[read_addr]` — only the read *address* is
registered, not the data — so writing to the address currently latched into
`read_addr` changes `dout` immediately, in the same cycle as the write, with
no extra pipeline delay. This is directly exercised by an "idle-cycle
write-to-currently-latched-read-address" directed test case.

Directed coverage: full-depth write with no reads, full-depth read-back,
same-cycle read/write collisions at the same address (confirms
write-then-immediately-visible "write-first" behavior — no `x`/undefined
collision hazard, since the read is address-latched rather than a true
same-cycle dual-port cell access), same-cycle read/write at different
addresses, the idle-cycle glitch-forwarding case described above, and `wce`
gating (writes must have no effect when `wce` is deasserted, even if `we` is
asserted). This is followed by a 2000-iteration deterministic xorshift fuzz
test.

As with `memory_slice`, `read_addr` is a genuinely-undefined register in
real hardware and in XSIM until the first `rce` pulse latches it (Verilator
zero-initializes registers instead); the self-check tracks whether `rce` has
fired at least once and treats `dout` as a don't-care before that, and
`make compare`'s shared `../compare_traces.py` treats the resulting `x`
fields in the XSIM trace the same way. Run `make verilator`, `make xsim`,
and `make compare`.
