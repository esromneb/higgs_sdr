# Vector fill library platform regression

This Jenkins regression boots CS20 firmware and exercises `fill.h`/`fill.c`
through the production Q-engine/piston vector-memory path.

Both simulator-local checks require:

- ring-bus completion sequence `0xdeadbeef`, `0x00000000`;
- all 16 banks in VMEM rows 0 through 7 equal `0x0000dead`;
- all 16 banks in VMEM row 8 equal `0x0000cafe`.

Run Verilator and XSIM and compare their complete ring-bus streams with:

```sh
PATH=/opt/amd/2025.2/Vivado/bin:$PATH make xsim_compare
```
