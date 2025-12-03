# Test
This test makes sure that VMEM_SECTION will always align to a 16 word boundary.

# Notes
* This was copied from some old fft version and hacked up.  The twiddle factors are used
* We set `tw3f` to be length `15` instead of `16`. With the old version for VMEM_SECTION this causes everything here to be off by 1

# Jenkins
* Under Jenkins Test

# XSIM parity

Both simulator-local checks require the exact ring-bus sequence:

```text
0xdeadbeef
0x00040400
0x00040400
0x0000000f
```

Run Verilator and XSIM and compare their complete streams with:

```sh
PATH=/opt/amd/2025.2/Vivado/bin:$PATH make xsim_compare
```
