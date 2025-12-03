# Test
Test different modes of output slicer.

# Modes:

* 1:1 (normal mode)
* 16:1
* 8:1
* 4:1
* 2:1

# Jenkins
Yes under jenkins

# XSIM parity harness

In addition to the Verilator regression above, this test now also has an
XSIM (Vivado `xvlog`/`xelab`/`xsim`) parity harness that runs the *exact
same* DUT (`sim/hdl/tb_higgs_top.sv`, `eth_top` only) under Vivado's
simulator, driven by a hand-written SystemVerilog testbench,
`tb_higgs_top_xsim.sv`, that mirrors `tb.cpp`'s reset/stimulus/self-check
exactly (a fixed 7500-cycle wait, then assert the exact 235-item ring-bus
sequence covering all 5 output-slicer modes back to back). See that
file's header comment for the full derivation.

## Running it

```sh
source /opt/amd/2025.2/Vivado/settings64.sh   # provides xvlog/xelab/xsim on PATH
cd sim/verilator/test_dma_slicer
make xsim_compare      # builds+runs both simulators and diffs their ring-bus logs
```

Confirmed result (2025-12-02): both simulators produce the identical
235-item sequence, and both print `All Tests Passed`.

## Build-only fixes needed

Uses the shared XSIM build logic in `scripts/make_include/xsim_common.mk`
(see that file and `test_fft_lib_1/README.md` for the full list of
build-only, non-committed-RTL patches). No test-specific RTL fixes were
needed beyond what that shared file already handles.