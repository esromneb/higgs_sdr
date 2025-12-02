# Test
Test in place fft (best performing), located in `fft_1024_3914.h`.

# status
Passing, tested by jenkins

# XSIM parity harness

In addition to the Verilator regression above, this test now also has an
XSIM (Vivado `xvlog`/`xelab`/`xsim`) parity harness that runs the *exact
same* multi-FPGA DUT (`sim/hdl/tb_higgs_top.sv`, the same `VER_SOURCES`/
defines Verilator uses) under Vivado's simulator instead, driven by a
hand-written SystemVerilog testbench, `tb_higgs_top_xsim.sv`, that mirrors
`tb.cpp`'s reset sequencing, ADC/DAC stimulus, and ring-bus self-check
exactly (same pass/fail assertions: `data[0]==0xdeadbeef` and
`data[last]==0x0F`).

## Running it

```sh
source /opt/amd/2025.2/Vivado/settings64.sh   # provides xvlog/xelab/xsim on PATH
cd sim/verilator/test_fft_lib_1
make xsim_gen        # generate build-only patched copies of a handful of legacy files (see below)
make xsim_compile     # xvlog
make xsim_elab        # xelab
make xsim_run         # xsim tb_higgs_top_xsim -R, produces xsim_run.log
make xsim_compare      # (or: python3 ../compare_ringbus.py verilator_run.log xsim_run.log)
```

Confirmed result (2025-12-01): both simulators produce the identical
`Ring got out 8 items.` sequence, `[0xdeadbeef, 0x34, 0x6, 0x2, 0x1, 0x0,
0x0, 0xf]`, and both print `All Tests Passed`. Re-run twice for
determinism; no `X`/timing-dependent divergence observed across two
independent clean runs.

## Build-only fixes needed to get XSIM to compile/elaborate/simulate this DUT

None of these modify committed legacy RTL; every one is applied to a
generated, build-only copy under `xsim_gen/` (see the `Makefile` for the
exact list of patched files and the mechanism):

1. **`nco.v` forward net reference**, **`generic_fifo_sc_a.v`` duplicate
   declarations + stray `` `timescale``**, and **8x `csXX_top.sv` implicit
   net-type ports on an `inout gpio`** — the same three fixes already
   proven by `fpgas/common/xilinx/sim/vex_machine_top/`; reused verbatim
   since this design's source list is a superset of that harness's.
2. **Pervasive implicit-net-type ports** across a further ~12 legacy
   `.sv` files (`dac_top.sv`, `adc_top.sv`, `cfg_top.sv`, `cmd_cdc.sv`,
   `width_32_8.sv`/`width_8_32.sv`, `eth_mega_wrapper.sv`/
   `eth_rx_wrapper.sv`, and 4 files under `lattice_support/gbit_mac/`):
   Verilator tolerates a bare `input`/`output` with no explicit net type
   even under `` `default_nettype none``; XSIM's `xvlog` frontend does
   not. `xsim_net_type_fix.py` mechanically inserts `wire` after each such
   file's `` `default_nettype none`` line. `eth_top.sv` additionally has a
   genuine copy-paste duplicate declaration (`split_fb_data/_valid/_ready`
   declared both as ANSI ports and redeclared as `reg` internally),
   patched the same way.
3. **Missing register reset values (X-propagation) across three
   independent IP trees** — the single biggest issue found. Q-engine/
   piston (48 files), the RISC-V-baseband `fwft_sc_fifo.v` FIFO, and the
   8588-line SpinalHDL-generated `XbbRiscv.v` (497 regs) were all written
   and only ever verified against Verilator, whose 2-state engine
   implicitly starts every `reg` at `0`. XSIM is a real 4-state simulator:
   an unreset `reg` stays `X` forever until its first write, and every one
   of these IP trees has elastic-pipeline/handshake idioms that gate that
   first write behind an expression which itself reads the still-`X` reg,
   so the `X` can never resolve — this manifested as a permanent
   simulation hang (frozen PC, `xbaseband_cmd_ready` stuck low forever).
   On real silicon this is a non-issue: synthesis programs each flip-flop's
   power-on `INIT` bitstream attribute to `0` absent an explicit initial
   value, exactly matching Verilator's assumption; only XSIM's
   pre-synthesis behavioral semantics are uniquely pessimistic here.
   `xsim_reg_init_fix.py` mechanically adds `= 1'b0` to every internal,
   non-array `reg` declaration lacking one (conservatively skipping memory
   arrays and anything already reset/initialized) across all of these
   files in one pass. This finding is broadly applicable to any future
   XSIM harness that reaches these same IP trees (see
   `doc/xilinx-port/NOTES.md`).
4. **Testbench stimulus bug: permanent UART RX "break" condition.**
   `tb_higgs_top_xsim.sv` originally tied `snap_eth_io_uart_rxd = 0`
   (a permanent logic-0/break/framing-error condition) instead of
   matching `tb.cpp`'s (`inc/higgs_helper.hpp`'s `handle_uart_neg()`)
   idle-high (`1`) convention. (`snap_eth_io_uart_rxd` is the only
   genuine `input wire` UART RX port on `tb_higgs_top.sv`; all the
   `snap_cs*_io_uart_rxd` signals are loopback/monitor `output`s, not
   real inputs, so no other signal needed this fix.) The permanent break
   condition caused `eth_top`'s own onboard firmware
   (`fpgas/grav/eth/c/src/main.c`, a completely separate CPU tile/program
   from `cs20`'s FFT-test firmware) to repeatedly re-enter its periodic
   `queue_dma_out()` telemetry path, flooding the shared ring bus with
   hundreds of extra `0x54000000`-style items interleaved with (but never
   replacing) the real 8-item test sequence. This was not visible to
   `tb.cpp`'s own pass/fail check (which only asserts the first and last
   items, not the total count), so both the buggy 343-item run and the
   fixed 8-item run technically "pass" that narrow self-check — the
   fixed testbench is required to get an *exact* item-for-item match
   against Verilator, which was this porting effort's actual goal. Fixed
   by changing the initializer to `= 1`.

