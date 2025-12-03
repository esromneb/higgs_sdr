# Q-engine SpinalHDL generators

This project contains the authoritative generator for the Xilinx-selected
VMEM DMA return arbiter.

Generate `hw/gen/VmemDatArbOut1_1.v` with:

```sh
make clean vao
```

The generated Verilog is checked in because it is consumed directly by the
CS12 Vivado source overlay and the XSIM/Verilator parity harness.
