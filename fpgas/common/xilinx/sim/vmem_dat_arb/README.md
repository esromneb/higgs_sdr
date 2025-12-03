# VMEM DMA return-arbiter parity harness

This harness verifies the generated `VmemDatArbOut1_1` used by the Xilinx
`vmem_dat_6_5_1_1` overlay. It independently varies order reservations,
memory-return timing, per-slice buffering, and all four DMA output ready
signals. A transaction scoreboard checks output routing, ordering, payload
stability, loss, and duplication for 512 deterministic transactions.

The SpinalHDL source is authoritative:

```sh
make -C libs/spinal vao
```

The generated RTL is checked in at `libs/spinal/hw/gen/VmemDatArbOut1_1.v`.
Run the cross-simulator test with:

```sh
export PATH=/opt/amd/2025.2/Vivado/bin:$PATH
make compare
```
