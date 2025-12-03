# vmem_dat_6_5_1_1 XSIM parent test

This self-checking parent-level test drives all four DMA request ports and the
16-lane vector port through the 16-bank VMEM hierarchy. It covers bank
conflicts, input valid gaps, independent DMA and vector-output backpressure,
response ordering, vector writes/reads, reset with queued reads, and
deterministic randomized reads after concurrent initialization writes.
Same-address dual-port memory collisions are excluded from the portable
contract.

Run with:

```sh
PATH=/opt/amd/2025.2/Vivado/bin:$PATH make xsim
```
