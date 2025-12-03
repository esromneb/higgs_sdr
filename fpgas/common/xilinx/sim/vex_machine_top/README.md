# `vex_machine_top` integration smoke-test parity harness

Unlike every other harness in `fpgas/common/xilinx/sim/`, which each
cross-check a single leaf module (`scalar_memory`, `memory_slice`,
`muladdsub`, `alu54b_wrapper`, `generic_dpram`, `generic_fifo_sc_a`) against
a directed/fuzzed self-check, this harness assembles the **entire real
design** reachable from `fpgas/common/modules/vex_machine_top.v` — the
VexRiscv core (`XbbRiscv.v`), `q_engine`'s bus/CSR decode, GPIO, all 32
vector memories, every piston/permutator leaf, `ring_bus`, `nco`, and the
DMA engines — and runs one real, compiled RISC-V program through it under
both Verilator and XSIM, comparing cycle-by-cycle traces. It exists to
close out PLAN item 7 ("CS12-level functional test") without depending on
the excluded `sim/verilator` test suite (out of scope per the task).

This is a system-level *integration* smoke test, not a substitute for the
leaf-level harnesses: it proves the whole assembled design boots, fetches
and executes real RISC-V instructions identically on both simulators, and
that a CSR write reaches a real peripheral (GPIO) — i.e. that top-level
wiring, bus decode, and instantiation parameters are all consistent
between the two toolchains. It is not exhaustive functional verification
of every leaf module in isolation (that is what the other six harnesses
are for).

## Scope

The test program (`riscv_prog/src/main.c`) deliberately only exercises:

1. CPU instruction fetch/execute (real compiled RV32I code, not synthetic
   idle/reset stimulus).
2. The real memory-mapped CSR bus decode path (`csrw`/`csrrs` via
   `libs/riscv-baseband/c/inc/csr_control.h`'s `CSR_WRITE`).
3. The real GPIO peripheral inside `q_engine` (`GPIO_WRITE_EN` /
   `GPIO_WRITE`), producing a distinctive rotating one-hot output pattern
   that is easy to diff between simulators.

It deliberately does **not** exercise DMA, `ring_bus`, NCO, vector memory
(piston) functional correctness, or interrupts — those remain out of
scope for this smoke test (kept bounded on purpose; see `main.c`'s own
comments). All 32 vector memories are still elaborated and reset (see
"VMEM stub files" below), but the program never issues a vector op, so
their functional correctness is untested here.

## Building and running

```
make verilator   # build + run under Verilator only
make xsim        # build + run under XSIM only
make compare      # build + run both, diff the traces (the main target)
make clean
```

Vivado (`xvlog`/`xelab`/`xsim`) must be on `PATH`, e.g.:
`export PATH=/opt/amd/2025.2/Vivado/bin:$PATH`. A real RISC-V toolchain
must be present at `/opt/riscv/bin/riscv32-unknown-elf-gcc` (used to build
`riscv_prog/`).

Trace CSV columns: `cycle,t0_ready,i0_valid,i0_data,io_uart_txd,gpio`.
`i0_data` is masked to `0` whenever `i0_valid` is low, since it is
architecturally don't-care in that cycle and would otherwise produce
false mismatches (`compare_traces.py` only special-cases the substring
`"x"`, not `"z"` or don't-care masking, so testbenches must never emit an
undriven/high-Z sample).

## The RISC-V test program

Built with the real toolchain (`riscv32-unknown-elf-gcc -march=rv32i
-mabi=ilp32`, no M-extension — matches `libs/riscv-baseband/Makefile`'s
`MUL?=no` default) using the existing (previously unused end-to-end)
`crt_standard.S` / `ld_standard` infrastructure in
`libs/riscv-baseband/c/inc/`, then converted from Intel-hex to the 4
byte-lane `.mif` files `scalar_memory_xilinx.sv`'s `$readmemh` expects via
`libs/riscv-baseband/scripts/hex2mif.py` (format confirmed to be plain
`$readmemh`-compatible `@addr` syntax, not a proprietary MIF format).
Correctness was independently verified by reconstructing 32-bit
instruction words from the 4 generated `.mif` banks and diffing them
against `objdump -d`'s disassembly of the linked ELF — exact match,
including the `csrw` GPIO CSR writes.

## VMEM stub files

`q_engine`'s 32 Xilinx-selected vector-memory
(`memory_slice_1_1_xilinx.sv`) instances each request a `vmemN.mif`
initialization file at time 0, regardless of
whether the running program performs any vector op. `vex_machine_top.v`
only exposes override parameters for `VMEM0..VMEM15`; `VMEM16..VMEM31`
always resolve to `q_engine.v`'s own literal defaults
(`"vmem16.mif".."vmem31.mif"`), which cannot be overridden from this
level. Rather than pass 32 path parameters (impossible for the upper 16
anyway), the `vmem_stubs` Makefile target simply generates all 32 default
filenames as trivial one-byte-zero stub files
(`fpgas/common/xilinx/sim/vex_machine_top/build/gen/vmemN.mif`) in each
simulator's working directory before running.

The harness now follows the production `HIGGS_FPGA_XILINX` selection:
`piston` instantiates `vmem_dat_6_5_1_1`, the Spinal-generated
valid/ready-correct return arbiter, and the tagged XPM memory slice. XSIM
uses the vendor XPM library; Verilator 4.016 uses the same narrow XPM
substitute as the focused memory and piston tests.

## Deliberate testbench-only deviation from production wiring

`cs12_top.sv`'s real `vex_machine_top` instantiation leaves `sat_detect`
and `outside_status` unconnected (floating) — a pre-existing real-hardware
characteristic, not something introduced by this port. Both testbenches
(`tb_vex_machine_top_parity.sv` and
`verilator_vex_machine_top_parity.cpp`) instead tie both to `0`, for
simulation determinism; this is a testbench-only choice, not a change to
any committed source.

## Discovered issues, fixed via build-only generated copies (no legacy source modified)

### `nco.v`: genuine forward-reference bug, tolerated by Verilator/Vivado, rejected by XSIM

`libs/q-engine/hdl/nco/nco.v` uses the wire `node1_addr` in a `casez`
several hundred lines before that wire's own declaration — legal,
tolerated Verilog-2001 implicit-net usage that both Verilator and (for
CS12's real hardware sign-off flow) Vivado's synthesizer accept without
complaint, but that XSIM's `xvlog` frontend hard-errors on
(`VRFC 10-3380`, "used before its declaration") in both `-sv` and
plain-Verilog modes. Fixed via a build-only generated copy
(`build/gen/nco.v`, produced by the `nco_patch` Makefile target) that
hoists a single `wire [8:0] node1_addr;` forward declaration to just after
the port list and deletes the now-redundant original declaration further
down, leaving the `assign` untouched. No behavioral effect; verified by
diffing the generated file and confirming Verilator still builds/runs
correctly from the same patched copy (used for both toolchains, for
consistency).

### `generic_fifo_sc_a.v`: duplicate declarations (same issue as the standalone harness)

Already documented in `../generic_fifo_sc_a/README.md`: the module body
re-declares four signals (`full_r`, `empty_r`, `full_n`/`empty_n`,
`full_n_r`/`empty_n_r`) already declared by its own ANSI-style output port
list — redundant but harmless duplicates that Verilator/Vivado only
warn about, but that XSIM's `xvlog` rejects as a hard error. Reuses the
exact same `sed`-based deletion patch as that harness, applied here via
the `fifo_patch` Makefile target.

### Timescale mixing: XSIM's all-or-nothing rule

XSIM's `xelab` hard-errors (`XSIM 43-4099`, "doesn't have a timescale but
at least one module in design has a timescale") if *any* module in the
elaborated design declares a `` `timescale `` directive while others do
not — a strict all-or-nothing rule, unlike Verilator/Vivado which allow a
mix (each module simply uses its own declared timescale, or the tool
default if none is declared).

Of the ~55 leaf files reachable from `vex_machine_top`, only two declare
their own `` `timescale ``: `generic_fifo_sc_a.v`
(`` `timescale 1ns / 100ps ``) and `muladdsub.v`
(`` `timescale 1 ns / 1 ps ``). Neither file contains any `#`-delay
statement that would be affected by its timescale value (confirmed by
inspection), so — rather than adding a matching directive to every one of
the ~50+ other timescale-less files (as was done for the much smaller,
2-file `generic_dpram`/`generic_fifo_sc_a` harness) — the much simpler and
equally-safe fix here is to *drop* the directive from build-only copies of
just these two files (`fifo_patch` and `muladdsub_patch` Makefile
targets), so every module in this design implicitly shares the same
(simulator-default) time unit. `tb_vex_machine_top_parity.sv` likewise
declares no `` `timescale `` of its own, for the same reason; its `#5
clk=~clk` clock generator only relies on relative edge counts (matched
1:1 against Verilator's manually-toggled clock), never absolute
simulation time, so the exact time unit in effect is immaterial to the
comparison.

## Verilog manifest

The `Makefile`'s `SOURCES` list mirrors
`libs/q-engine/scripts/make_include/verilog_paths.mk`'s
`Q_ENGINE_ALL_VERILOG`, with two corrections discovered while assembling
it (also relevant to `doc/xilinx-port/CS12_HDL_MANIFEST.md`, which had a
related typo fixed alongside this harness):

- **Dropped `alu54b_wrapper.v`**: not instantiated anywhere in this
  reachable design (only `muladdsub.v` is, and it does not reference
  `alu54b_wrapper`).
- **Added `fpgas/common/modules/demapper/demapper.sv`**: instantiated by
  `q_engine.v` but missing from that canonical list.

## Cross-simulator testbench synchronization

As with all harnesses in this directory, the Verilator driver
(`verilator_vex_machine_top_parity.cpp`) and the XSIM testbench
(`tb_vex_machine_top_parity.sv`) are two independently-written stimulus
implementations wrapping the same DUT — not one shared file — so they
must be kept manually in sync (reset/warmup/capture cycle counts,
tie-offs, trace CSV columns). This harness's C++ driver tracks cycles
using a capture-relative `sample` counter (matching the SV testbench's
`cycle`, which restarts counting after warmup) rather than a raw running
total from time 0, to keep the `cycle` column numerically identical
between the two traces.

## Validation performed

- `riscv_prog`'s compiled machine code independently verified against
  `objdump -d`'s disassembly by reconstructing 32-bit instruction words
  from the 4 generated `.mif` banks (exact match).
- `make verilator`: builds cleanly, runs 6000 capture cycles, produces the
  expected rotating one-hot GPIO waveform.
- `make xsim`: builds cleanly (after the fixes above), runs the same 6000
  capture cycles.
- `make compare`: traces match exactly (`PASS: traces match`), across
  three independent clean rebuild-and-compare runs (determinism check).
- All six pre-existing leaf harnesses in this directory re-run via
  `make clean && make compare` after these changes: all still pass (no
  cross-contamination from this harness's build-only patches, which are
  each scoped to their own `build/gen/` directory).
