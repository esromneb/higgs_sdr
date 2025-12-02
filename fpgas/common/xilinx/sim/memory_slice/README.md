# `memory_slice` (XPM vector memory) parity test

Unlike the `scalar_memory_xilinx` test (which only checks a single Xilinx
implementation for cross-simulator self-consistency), this harness directly
compares the **legacy reference** `memory_slice` (`libs/q-engine/piston/hdl/memory_slice.v`,
inferred `dpram`) against the **Xilinx-selected** `memory_slice_xilinx.v`
(built on `xpm_memory_tdpram`).  `memory_slice_dual_top.sv` instantiates both,
renamed at build time (`memory_slice_ref`/`memory_slice_xil`) to avoid module
collisions, and exposes `ref_*`/`xil_*` outputs side by side.

Run `make verilator` for the directed and 500-iteration deterministic LFSR
fuzz test under Verilator, `make xsim` for the same stimulus under XSIM, and
`make compare` to diff their CSV traces of the Xilinx-side outputs.

## Why Verilator gets a behavioral stand-in for `xpm_memory_tdpram`

Verilator 4.016 cannot parse the real vendor `xpm_memory.sv` (it uses SV
assertions, `$rose`, and other constructs the installed version doesn't
support). `xpm_memory_tdpram_verilator_model.sv` is a hand-written,
Verilator-only substitute that implements *only* the exact configuration this
design actually uses: common clock, write-first on both ports, one cycle of
read latency, `regcea`/`regceb` tied high, no ECC/reset/sleep pins. XSIM
always uses the real vendor model
(`$XILINX_VIVADO/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv`); only the
Verilator build substitutes it.

## Empirically-confirmed behavior baked into the tests

A throwaway probe against the real `xpm_memory_tdpram` (not committed)
confirmed:

* `ena=0` holds the previous output-register value.
* Write-first: a write shows up at the output with the same one-cycle latency
  as an ordinary read.
* Same-address, same-cycle access across the two ports, where at least one
  side is writing, produces `x` on the colliding port's output. This is
  genuinely hardware-undefined (matches the reference `dpram`'s behavior
  too), so the fuzz stimulus deliberately perturbs one address whenever
  `we0 || we1` would otherwise create such a collision. Same-address
  concurrent *reads* are safe and are not excluded.
* Writes commit whenever `we` is asserted, **independent of `valid`**, in
  both the legacy `dpram` and the Xilinx/XPM path
  (`if (we_0) mem[addr_0] <= din_0; ...`, no `valid` gate). The fuzz
  collision-avoidance logic keys off `we0 || we1` for exactly this reason
  (an earlier version of this test incorrectly gated on `valid && we` and
  missed real collisions, corrupting one port's storage to `x` while the
  reference retained a race-winner value).

## Don't-care masking

Both the self-checking assertions (inside each simulator, `ref_*` vs.
`xil_*`) and the cross-simulator `compare_traces.py` script treat any field
reporting `x` as a match against anything. This is not papering over bugs:
in this design, `x` only ever appears in the very first post-reset cycle for
the port-1 skid/pipeline register outputs (before their first real
transaction loads them), reflecting a benign Verilator-zero-initializes vs.
XSIM-leaves-undefined convention difference, not a functional divergence.
`compare_traces.py` also verifies traces have matching headers/row counts.
Data fields are additionally only asserted equal (in the live self-check)
when the corresponding `valid` output is asserted, since data has no defined
meaning while invalid.
