# Test
Test if output dma with 4 items actually sends correct items

# XSIM parity harness

In addition to the Verilator regression above, this test now also has an
XSIM (Vivado `xvlog`/`xelab`/`xsim`) parity harness that runs the *exact
same* DUT (`sim/hdl/tb_higgs_top.sv`, `eth_top` only -- no CS tiles/DAC/ADC
in this test's configuration) under Vivado's simulator, driven by a
hand-written SystemVerilog testbench, `tb_higgs_top_xsim.sv`, that mirrors
`tb.cpp`'s reset/stimulus/self-check exactly (a fixed 1000-cycle wait, then
assert exactly 4 ring-bus items `[1, 2, 3, 4]`). See that file's header
comment for the full derivation.

## Running it

```sh
source /opt/amd/2025.2/Vivado/settings64.sh   # provides xvlog/xelab/xsim on PATH
cd sim/verilator/test_eth_dma
make xsim_compare      # builds+runs both simulators and diffs their ring-bus logs
```

Confirmed result (2025-12-02): both simulators produce the identical
4-item sequence `[0x1, 0x2, 0x3, 0x4]`, and both print `All Tests Passed`.

## Build-only fixes needed

Uses the shared XSIM build logic in `scripts/make_include/xsim_common.mk`
(see that file and `test_fft_lib_1/README.md` for the full list of
build-only, non-committed-RTL patches: forward net references, implicit
net-type ports, `X`-propagation register-reset fixes, etc). No
test-specific RTL fixes were needed beyond what that shared file already
handles.
