# Purpose

Test if test bench can read dma out of cs30.  I introduced a regression where testbench would only allow cs30 to output ~1024. and testbench would not see any samples.

# XSIM parity harness

In addition to the Verilator regression above, this test now also has an
XSIM (Vivado `xvlog`/`xelab`/`xsim`) parity harness that runs the *exact
same* DUT (`sim/hdl/tb_higgs_top.sv`, configured identically to `tb.cpp`:
all 9 FPGA tiles -- eth + 8x CS -- with only CS20 running real firmware,
the rest ring-bus passthrough only) under Vivado's simulator, driven by a
hand-written SystemVerilog testbench, `tb_higgs_top_xsim.sv`. This is the
largest port list of any XSIM harness so far (9 tiles). See that file's
header comment for the full per-tile port-bundle derivation (cs11/cs31
monitor-only riscv_in taps, cs22/cs21 tied-off inject_riscv_in inputs,
etc). This test's own self-check is a 0-item ring-bus stream (no
`ring_block_send_eth()` calls are reachable in this configuration); both
simulators are still required to independently self-report
`All Tests Passed`, so the comparison is not vacuous.

## Running it

```sh
source /opt/amd/2025.2/Vivado/settings64.sh   # provides xvlog/xelab/xsim on PATH
cd sim/verilator/test_cs20_dma
make xsim_compare      # builds+runs both simulators and diffs their ring-bus logs
```

Confirmed result (2025-12-02): both simulators produce 0 ring-bus items
and both print `All Tests Passed`.

## Build-only fixes needed

Uses the shared XSIM build logic in `scripts/make_include/xsim_common.mk`
(see that file and `test_fft_lib_1/README.md` for the full list of
build-only, non-committed-RTL patches). This test additionally surfaced
one genuine testbench bug (not a DUT bug), found because this test's
data volume (14000+ items) is far larger than the other tests':

**`i_rx_ready_eth` tie-off bug.** `i_rx_ready_eth` (wired to `eth_top`'s
`split_fb_ready` input, which gates whether `eth_top`'s `cs20_in_buffer`
FIFO ever drains via `fb_eq_split_0`) was tied to constant `0` in
`tb_higgs_top_xsim.sv`, but the reference Verilator harness
(`higgs_helper.hpp`'s `eth_rx` port, `control_ready=1`, `random_ready`
unset) always drives it constant-`1`. Tied to `0`, `cs20_in_buffer` never
drains, fills up, and asserts backpressure that propagates all the way
back through `cs20_top`'s own output buffer, silently stalling CS20's DMA
output after only ~78 items — invisible in the other, much smaller-volume
tests, but fatal here. Fixed by tying `i_rx_ready_eth = 1` (applied to
all 5 XSIM testbenches, including retroactively to `test_fft_lib_1`'s).