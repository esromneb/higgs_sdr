# Piston DMA-path parity harness

This harness verifies the production `piston` hierarchy with
`HIGGS_FPGA_XILINX` selecting `vmem_dat_6_5_1_1`. It drives all four external
DMA ports through piston's generated control/data elastic edges, creates bank
conflicts and valid gaps, independently backpressures all four outputs, and
asserts reset with responses in flight. A per-DMA scoreboard checks 512
ordered reads after concurrent initialization writes.

XSIM uses the vendor XPM memory model. Verilator 4.016 uses the existing
configuration-specific behavioral XPM substitute. Defined transactions are
compared cycle-for-cycle:

```sh
PATH=/opt/amd/2025.2/Vivado/bin:$PATH make clean compare
```

This focused boundary keeps the instruction input idle, so it proves the
external DMA-to-VMEM path through piston's generated control/data network. It
does not replace the existing instruction-driven `vex_machine_top` and
platform regressions for the arithmetic and vector-processing paths.
