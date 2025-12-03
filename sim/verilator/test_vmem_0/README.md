# Test
Test if we can load a VMEM_SECTION veriable at compile time.  This test is in eth (should be moved as eth does not have vmem on board).  Eth dma's out the counter and TB catches it

# FPGA
* Just eth

# Jenkins
* Under Jenkins Test

# XSIM parity

The XSIM harness runs the same ETH-only platform configuration and firmware.
Both simulator-local self-checks require exactly 16 ring-bus words with the
complete ordered sequence `0xf0` through `0xff`; the shared comparator then
requires both streams to match exactly.

```sh
PATH=/opt/amd/2025.2/Vivado/bin:$PATH make xsim_compare
```
