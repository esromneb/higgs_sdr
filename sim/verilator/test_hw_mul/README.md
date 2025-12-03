# Hardware multiply/divide platform regression

This Jenkins regression boots real CS11 firmware on the complete nine-tile
platform and confirms that the generated RISC-V core includes the hardware
multiply/divide implementation.

The self-check requires the exact five-word ring-bus sequence:

```text
0000dead 0000002d 00000499 0000000c 0102c5a0
```

The measured divide latency must remain below 60 cycles and multiply latency
below 40 cycles. The current reference values are 45 and 12 cycles.

Run both simulators and compare their complete ring-bus streams with:

```sh
PATH=/opt/amd/2025.2/Vivado/bin:$PATH make xsim_compare
```

XSIM uses only the shared build-time compatibility copies documented in
`scripts/make_include/xsim_common.mk`; production RTL is unchanged.
