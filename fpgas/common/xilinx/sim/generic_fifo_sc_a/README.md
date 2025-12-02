# `generic_fifo_sc_a` parity test

`generic_fifo_sc_a` (`libs/ip-library/fwft_fifos/sc_fifo/hdl/generic_fifo_sc_a.v`)
is the single-clock synchronous FIFO control logic used by `fwft_sc_fifo`
(in turn used by `pmi_fifo_sc_fwft_v1_0`, all in the committed CS12
manifest). It wraps `generic_dpram` for storage and adds write/read
pointers, guard bits, full/empty/almost-full status, and a `clr`
(synchronous clear) input in addition to `rst`. It has no separate Xilinx
implementation, so — like `generic_dpram` — it is tested by directed
vectors plus a deterministic fuzz test, run identically on both simulators,
self-checked every cycle against an independent, hand-derived control-plane
shadow model (`tb_generic_fifo_sc_a_parity.sv` and
`verilator_generic_fifo_sc_a_parity.cpp`).

Parameters under test: `dw=8`, `aw=4` (`n=4`, i.e. depth 16), `ALMOST_FULL=5`
(overriding the RTL's own defaults of `n=32`/`aw=8`).

## Scope: `dout` is intentionally excluded from this self-check

`generic_fifo_sc_a` forwards `generic_dpram`'s `dout` unmodified; that
memory's read/write/glitch-forwarding behavior is already independently
verified by the `generic_dpram` harness. This harness's shadow model tracks
only the control-plane state (`wp`, `rp`, `gb`, `gb2`, `cnt`, `full_r`,
`empty_r`, `full_n_r`, `empty_n_r`, `fillcount`, `afull`, `afull_n`,
`o_afull_n_d`); `dout` is still traced to CSV for the cross-simulator
`make compare` diff, but is not asserted against a shadow value.

## Discovered RTL subtleties, faithfully reproduced (not "fixed")

- **The `fillcount`/`afull`/`afull_n`/`o_afull_n_d`/`temp` register block
  responds only to `rst`, never to `clr`** — unlike every other status
  register in the module (`wp`, `rp`, `gb`, `gb2`, `cnt`, `full_r`,
  `empty_r`, `full_n_r`, `empty_n_r`), which all respond to both `rst` and
  `clr`. This asymmetry is reproduced as-is in the shadow model (see Phase C
  below) rather than treated as a bug, since the task is behavior-preserving
  porting, not RTL correction.
- **The `afull` threshold check and `o_afull_n_d` both read the pre-edge
  (old) `fillcount`/`temp` register values**, not the newly-computed ones,
  within the same always block that also updates `fillcount` — a
  parallel/pre-edge-read semantic (same class of subtlety as `muladdsub`'s
  pipeline). Both shadow models capture the old values before computing any
  new state, matching this.

## Directed coverage

Reset; fill-to-full (Phase A); drain-to-empty (Phase B); `clr`
mid-operation, verifying `wp`/`rp`/`gb`/`gb2`/`cnt` clear immediately while
`fillcount`/`afull` do not (Phase C); simultaneous `we`&`re` at partial fill
(Phase D); explicit `ALMOST_FULL` threshold crossing (Phase E); mid-run
reset re-assertion (Phase F). Followed by a 5000-iteration deterministic
xorshift fuzz test (Phase G), gated to only defined transactions (`we` only
when `!full`, `re` only when `!empty`), matching this repo's existing "RAM
behavior is compared through defined read/write transactions" convention
for avoiding explicitly-undefined stimulus (per the module's own doc
comment: writing while full or reading while empty is undefined).

## Build-only fixes (legacy source never modified)

- **Duplicate declarations, XSIM-blocking (not just cosmetic).**
  `generic_fifo_sc_a.v`'s body re-declares six signals already declared in
  its own ANSI-style port list (`full_r`, `empty_r`, `full_n`/`empty_n`,
  `full_n_r`/`empty_n_r`). Vivado's synthesizer tolerates this as a
  non-fatal warning (as previously noted in `doc/xilinx-port/NOTES.md`), but
  XSIM's `xvlog` frontend treats it as a hard `ERROR: [VRFC 10-9364]` and
  drops the whole module — i.e. this diagnostic actually blocks simulation,
  not just synthesis. The `gen` Makefile target sed-strips exactly those
  four declaration lines from a build-only renamed copy (verified via
  `diff` to touch nothing else); the committed legacy source is untouched.
- **Timescale consistency, XSIM-only.** `generic_fifo_sc_a.v` carries its
  own `` `timescale 1ns / 100ps `` directive, but `generic_dpram.v` (compiled
  alongside it) has none; XSIM's `xvlog` requires a consistent
  timescale-directive presence across all modules in one compilation.
  Verilator has no such requirement. The `gen` target additionally produces
  a build-only copy of `generic_dpram.v` with a matching timescale
  directive prepended, used only by the `xsim` recipe (the `verilator`
  recipe still compiles the raw, untouched `generic_dpram.v`).
- **Verilator parameter overrides via `-G` flags, not testbench
  `#(...)`.** Verilator's `--top-module generic_fifo_sc_a` elaborates that
  module directly with its own default parameters, ignoring any `#(...)`
  override written in a non-root testbench. The intended `dw=8 aw=4 n=4
  ALMOST_FULL=5` parameterization is passed explicitly via
  `-Gdw=8 -Gaw=4 -Gn=4 -GALMOST_FULL=5` on the Verilator command line.

## Running

`make verilator`, `make xsim`, `make compare` (or `make clean && make
compare` for a full rebuild). As with `generic_dpram`, a handful of `dout`
values are genuinely `x` in the XSIM trace during the initial cycles before
`generic_dpram`'s internal `read_addr` is first latched; `../compare_traces.py`
treats these as don't-care, matching the already-established precedent.
