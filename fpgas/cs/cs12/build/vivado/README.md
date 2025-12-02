# CS12 Vivado synthesis target

Run from this directory:

```sh
LD_PRELOAD=/lib/x86_64-linux-gnu/libudev.so.1 \
    /opt/amd/2025.2/Vivado/bin/vivado -mode batch -source build.tcl
```

The target uses `xczu7ev-ffvc1156-2-e`, matching the existing Xilinx proof.
It replaces the Lattice PLL, `core_top`, `pmi_fifo_dc`, Q-engine scalar
memory, and vector-memory `memory_slice` with Xilinx implementations.  It
synthesizes successfully with Vivado 2025.2.  Board-specific pin/I/O timing
constraints are still required before bitstream generation or hardware use.
