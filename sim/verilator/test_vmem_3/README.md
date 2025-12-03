# VMEM MIF generation regression

This active Jenkins regression boots CS20 firmware, verifies compile-time VMEM
contents produced by `hex2mif_vmem.py`, and waits for the firmware completion
PC.

Both simulator-local checks require completion before timeout and the exact
ring-bus sequence:

```text
0xdeadbeef
0x00000000
0x00000001
```

Run Verilator and XSIM and compare their complete streams with:

```sh
PATH=/opt/amd/2025.2/Vivado/bin:$PATH make xsim_compare
```
