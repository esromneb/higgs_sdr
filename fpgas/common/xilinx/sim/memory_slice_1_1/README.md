# memory_slice_1_1 XSIM test

This self-checking test covers the defined independent-port contract of the
Xilinx `memory_slice_1_1`: writes, tagged reads, stable responses under
backpressure, back-to-back requests, and simultaneous accesses to different
addresses. Simultaneous same-address dual-port accesses are intentionally
excluded because their result is not part of the portable contract.

Run with:

```sh
PATH=/opt/amd/2025.2/Vivado/bin:$PATH make xsim
```
