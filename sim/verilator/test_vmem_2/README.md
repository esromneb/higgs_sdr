# VMEM compile-time data regression

This active Jenkins regression boots CS20 firmware and checks three
compile-time VMEM data cases through the production Q-engine/piston path.

Both simulator-local checks require exactly the order-independent set:

- `0x00000e0a`
- `0x00000e1a`
- `0x00000e2a`

The shared comparator additionally requires the complete emitted ring-bus
stream to match exactly between Verilator and XSIM.

```sh
PATH=/opt/amd/2025.2/Vivado/bin:$PATH make xsim_compare
```
