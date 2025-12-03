# NCO platform parity regression

This test verifies the production CS20 numerically controlled oscillator
through the complete firmware-controlled platform path:

```text
RISC-V CSR -> NCO -> DMA2 -> piston/VMEM -> DMA1 -> CS20 stream output
```

The firmware generates 32,768 complex samples with start angle `0xbfffffff`
and delta `1<<20`. Both simulator drivers independently require:

- exactly 32,768 samples;
- an exact 4,096-sample period across all eight repetitions;
- exact phase/quadrant anchor samples;
- FNV-1a digest `0x6248f48c3198f9f5`.

The comparison step then verifies every emitted 32-bit sample is identical
between Verilator and XSIM. This replaces the old plot-only Python script,
which contained no assertions and could exit successfully for incorrect data.

Run:

```sh
PATH=/opt/amd/2025.2/Vivado/bin:$PATH make xsim_compare
```

Successful output includes:

```text
All Tests Passed
PASS: 32768 NCO samples match exactly and both simulator self-checks passed
```

XSIM uses the shared build-only compatibility transformations in
`scripts/make_include/xsim_common.mk`. The legacy FIFO assertions are gated
during active reset in the generated XSIM copy; post-reset FIFO violations
remain enabled. No production RTL is modified.

This is an exact regression for one historically defined frequency,
start-angle, and length configuration. Additional frequencies, phase
increments, and lengths remain future coverage.
