# q_engine firmware-driven DMA parity harness

This harness runs real RV32I firmware in `q_engine` and verifies the complete
external stream loop:

```text
t0 stream -> DMA-in -> piston/VMEM -> DMA-out -> demapper/slicer -> i0 stream
```

The firmware configures DMA-in and DMA-out through the real CSR bus and waits
for the DMA-in interrupt before starting DMA-out. The independently written
XSIM and Verilator drivers apply deterministic input-valid gaps and output
backpressure. A transaction scoreboard checks all 64 payloads, ordering,
`last`, stability under backpressure, and timeout behavior. Cycle traces must
match between simulators.

Run with:

```sh
PATH=/opt/amd/2025.2/Vivado/bin:$PATH make clean compare
```
