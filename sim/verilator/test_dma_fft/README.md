# Purpose
Found a random bug where input dma affects output dma even though they are writing to different addresses.  tests can pick a time based random seed, or a fixed seed.  Input from eth is randomized.  We only dump the vcd file in the affected time range.

# Instructions
Run this to show the error:
* `make` or `make quick`
* Test bench will say `Breaking early at 1952040 (976000)`
* `make show` to see the truncated wave file

# Notes
* CS20 sends mapped/moved data to CS10
* CS10 is made of a hacked ping-pong streaming fft code, which sends an ringbus msg with value of `0xc000001` which signals an error.
   * it does this by a modified `pet_fft()` which is looking for the specific counter at the specific place
* The output data from CS20 should be a fft with data on channels `111, 122, 133, 144, 866, 877, 888, 899`
  * This means that the output is in chunks of 1024, where every index above is non-zero

# The Issue
Look at cs20_out.hex: 
* on line `111728`  we find our pattern,  `(111728-1) % 1024` is `111`
* on line `111728 + 1024` we would expect to find the same pattern, but it has shifted

# Tracing
This test is an example of partial vcd partial wave dump partial gtk wave dumps.

# XSIM parity harness

In addition to the Verilator regression above, this test now also has an
XSIM (Vivado `xvlog`/`xelab`/`xsim`) parity harness that runs the *exact
same* DUT (`sim/hdl/tb_higgs_top.sv`, same 9-tile configuration as
`test_cs20_dma`, but with CS11/CS12/CS02/CS01 running real firmware
instead of CS20) under Vivado's simulator, driven by a hand-written
SystemVerilog testbench, `tb_higgs_top_xsim.sv`. See that file's header
comment for the full derivation.

This test is fundamentally different from the other three DMA ports: it's
a **randomized glitch-detection regression**, not a fixed-stimulus/fixed-
output self-check. `tb.cpp`'s default mode reseeds from wall-clock time
every run, which is not reproducible across simulators. For genuine
XSIM/Verilator parity, `tb.cpp` now sets `fixed_seed = 1525241634` (a
value the file's own author had already recorded as historically
interesting, "After 1900"); with this seed the current codebase's
Verilator baseline reproducibly passes (does not hit the historical DMA
glitch bug described above). To get true bit-exact stimulus parity (not
just a similarly-shaped random pattern), `tb_higgs_top_xsim.sv`
reimplements glibc's `rand()`/`srand()` TYPE_3 algorithm exactly (verified
bit-for-bit against libc for this seed), reproducing the identical
`cs11in` injection-timing schedule in both simulators.

The expected ring-bus sequence is CS11 firmware's 4 boot markers
(`ring_block_send_eth(0xdead)` followed by 3 VMEM pointer sends), emitted
near the very start of `main()`, well before any FFT/DMA_1/slicer
processing -- see `override/fpgas/cs/cs11/c/src/main.c`.

## Running it

```sh
source /opt/amd/2025.2/Vivado/settings64.sh   # provides xvlog/xelab/xsim on PATH
cd sim/verilator/test_dma_fft
make xsim_compare      # builds+runs both simulators and diffs their ring-bus logs
```

Confirmed result (2025-12-02, re-run twice for determinism): both
simulators produce the identical 4-item sequence
`[0xdead, 0x8000, 0x8400, 0x8800]`, and both print `All Tests Passed`.

## Build-only fixes needed

Uses the shared XSIM build logic in `scripts/make_include/xsim_common.mk`
(see that file and `test_fft_lib_1/README.md` for the general list of
build-only, non-committed-RTL patches). This test additionally surfaced
one **genuine, permanent fix** to that shared file:

**`EXTRA_RINGBUS` compile-order bug.** `fpgas/grav/eth/hdl/eth_top.sv`
locally declares `` `define EXTRA_RINGBUS `` immediately before its
`q_engine` instantiation, intending to enable `q_engine.v`'s second
ring-bus (`ring_bus_inst_2`, guarded by `` `ifdef EXTRA_RINGBUS``) for
every q_engine instance. Verilog `` `define `` has file-compile-order-
dependent (not instantiation-site-scoped) effect: a module is analyzed
exactly once, so whatever `` `ifdef`` state existed when `xvlog` reached
*that file* applies to every instantiation. Since `q_engine.v` compiles
before `eth_top.sv` in `XSIM_SOURCES` (confirmed via `xvlog.log`), XSIM
never instantiated `ring_bus_inst_2` for any q_engine, leaving `o_ringbus`
floating and `eth_top`'s `HS_EAST_OUT_RB[47]` register (no reset) latching
`X`/`Z` every cycle -- silently breaking the CS-tile-to-ETH ring-bus
return path for every test, not just this one (the other 3 DMA tests
never send anything over this path, so they never observed it). Verilator
already instantiates `ring_bus_inst_2` for every q_engine instance
(confirmed via `obj_dir/*ring_bus*` symbols for all 5 parameterized
variants), so the fix is to define `EXTRA_RINGBUS` globally via `xvlog`'s
`-d EXTRA_RINGBUS` command-line flag (order-independent) in
`xsim_common.mk`, exactly matching Verilator's actual compiled behavior.
Verified this only adds previously-missing functionality: `test_eth_dma`,
`test_dma_slicer`, and `test_cs20_dma` were rebuilt clean and re-verified
to still pass identically after this change.