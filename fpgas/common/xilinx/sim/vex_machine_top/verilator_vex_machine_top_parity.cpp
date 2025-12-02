// Verilator cycle-driver for `vex_machine_top`
// (fpgas/common/modules/vex_machine_top.v), the real VexRiscv+Q-engine
// integration point named by doc/xilinx-port/PLAN.md items 4/5/7.
//
// Unlike the other harnesses under fpgas/common/xilinx/sim/*, this is not
// a per-leaf vendor-macro parity check: every leaf reachable from this
// module was already independently verified (see NOTES.md/PLAN.md), and
// none of them differ between the Verilator and Xilinx builds at the RTL
// level (no dual implementation exists for this module). Instead, this is
// a system-level smoke test: it runs the *same* real, compiled RISC-V
// program (riscv_prog/) through the *entire* assembled design -- VexRiscv
// core, bus/CSR decode, and the GPIO peripheral inside q_engine -- under
// both Verilator and XSIM, and diffs the resulting traces. Agreement is
// strong evidence that the whole integrated design (not just isolated
// leaves) behaves identically under both toolchains.
//
// Scope: the test program only exercises CPU fetch/execute, CSR bus
// decode, and GPIO. It deliberately never touches DMA, ring bus, NCO, or
// vector memory (piston) -- see riscv_prog/src/main.c and README.md.
#include <cstdint>
#include <cstdio>
#include <string>
#include <verilated.h>
#include "Vvex_machine_top.h"

static const int RESET_CYCLES = 20;
// Skip this many post-reset cycles before recording samples: enough for
// the RISC-V program's startup code (BSS clear, register clear, stack
// pointer setup) and its first GPIO_WRITE_EN/GPIO_WRITE CSR writes to
// definitely have executed, so every recorded `gpio` sample is a fully
// driven, defined value (never floating/high-Z from the DUT).
static const int WARMUP_CYCLES = 500;
static const int CAPTURE_CYCLES = 6000;

static Vvex_machine_top *top_;
static FILE *trace_;
static long cycle_ = 0;

static void tick() {
  top_->clk = 0;
  top_->eval();
  top_->clk = 1;
  top_->eval();
  cycle_++;
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top_ = new Vvex_machine_top;

  std::string trace_path = "trace.csv";
  for (int i = 1; i < argc; i++) {
    std::string arg = argv[i];
    const std::string prefix = "+TRACE=";
    if (arg.rfind(prefix, 0) == 0) trace_path = arg.substr(prefix.size());
  }
  trace_ = std::fopen(trace_path.c_str(), "w");
  std::fprintf(trace_, "cycle,t0_ready,i0_valid,i0_data,io_uart_txd,gpio\n");

  // Tie off all stimulus inputs to fixed, benign values: no input stream
  // traffic, output stream always ready (so a spurious i0_valid would be
  // observed rather than silently backpressured), sat_detect/outside_status
  // deasserted (unlike the un-instrumented `gpio` port, cs12_top.sv leaves
  // these two floating in the real design; tying them to 0 here is a
  // deliberate, documented testbench-only choice for determinism -- see
  // README.md), UART RX idle-high, and ring bus idle.
  top_->reset = 1;
  top_->debugReset = 0;
  top_->t0_data = 0;
  top_->t0_last = 0;
  top_->t0_valid = 0;
  top_->i0_ready = 1;
  top_->outside_status = 0;
  top_->io_uart_rxd = 1;
  top_->sat_detect = 0;
  top_->i_ringbus = 0;
  // `gpio` is an inout; leaving it unconnected on the testbench side (no
  // assignment at all) lets the DUT's own tri-state drivers be the sole
  // driver, matching how Verilator resolves inout nets with one driver.

  for (int i = 0; i < RESET_CYCLES; i++) tick();
  top_->reset = 0;

  for (int i = 0; i < WARMUP_CYCLES; i++) tick();

  // The trace's "cycle" column is capture-relative (restarts at 1 once
  // warmup ends), matching tb_vex_machine_top_parity.sv's `cycle` counter,
  // so the two traces' cycle columns line up exactly despite the
  // reset/warmup phases being driven by independent code in each language.
  for (int i = 0; i < CAPTURE_CYCLES; i++) {
    tick();
    long sample = i + 1;
    // i0_data is architecturally meaningless whenever i0_valid is low (this
    // test never drives real stream traffic, so i0_valid should stay 0
    // throughout); reporting a fixed sentinel instead of the raw signal
    // there avoids the comparison being sensitive to don't-care upstream
    // register content that isn't part of what this smoke test checks.
    unsigned i0_valid = static_cast<unsigned>(top_->i0_valid);
    unsigned i0_data = i0_valid ? static_cast<unsigned>(top_->i0_data) : 0;
    std::fprintf(trace_, "%ld,%u,%u,%08x,%u,%06x\n", sample,
                 static_cast<unsigned>(top_->t0_ready), i0_valid, i0_data,
                 static_cast<unsigned>(top_->io_uart_txd),
                 static_cast<unsigned>(top_->gpio) & 0x3fffffu);
  }

  std::printf("vex_machine_top: ran %ld cycles, wrote %d trace samples\n",
              cycle_, CAPTURE_CYCLES);
  std::fclose(trace_);
  top_->final();
  delete top_;
  return 0;
}
