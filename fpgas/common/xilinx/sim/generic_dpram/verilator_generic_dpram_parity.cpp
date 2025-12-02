// Verilator cycle-driver for `generic_dpram`
// (libs/ip-library/fwft_fifos/sc_fifo/hdl/generic_dpram.v).
//
// Mirrors tb_generic_dpram_parity.sv: same directed vectors (full-depth
// write/read-back, same-address collisions, idle-cycle glitch-forwarding,
// wce gating), the same deterministic xorshift fuzz sequence, and the same
// independent shadow-model self-check, so the two traces can also be
// diffed via ../compare_traces.py.
#include <cstdint>
#include <cstdio>
#include <string>
#include <verilated.h>
#include "Vgeneric_dpram.h"

static const int AW = 4;
static const int DW = 8;
static const int DEPTH = 1 << AW;

static Vgeneric_dpram *top_;
static FILE *trace_;
static uint8_t shadow_mem[DEPTH];
static uint8_t shadow_read_addr = 0;
static long cycle_ = 0;
static int errors_ = 0;

static uint32_t lfsr_ = 0xACE12024u;
static uint32_t next_lfsr() {
  uint32_t x = lfsr_;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  lfsr_ = x;
  return x;
}

static void step() {
  top_->rclk = 0;
  top_->wclk = 0;
  top_->eval();
  top_->rclk = 1;
  top_->wclk = 1;
  top_->eval();

  cycle_++;
  if (top_->wce && top_->we) {
    shadow_mem[top_->waddr & (DEPTH - 1)] = static_cast<uint8_t>(top_->di);
  }
  if (top_->rce) {
    shadow_read_addr = top_->raddr & (DEPTH - 1);
  }
  uint8_t expected = shadow_mem[shadow_read_addr];
  uint8_t got = static_cast<uint8_t>(top_->dout);
  if (expected != got) {
    errors_++;
    std::fprintf(stderr,
                 "MISMATCH cycle=%ld rce=%u wce=%u we=%u raddr=%u waddr=%u "
                 "di=%u dout=%u expected=%u\n",
                 cycle_, static_cast<unsigned>(top_->rce),
                 static_cast<unsigned>(top_->wce),
                 static_cast<unsigned>(top_->we),
                 static_cast<unsigned>(top_->raddr),
                 static_cast<unsigned>(top_->waddr),
                 static_cast<unsigned>(top_->di),
                 static_cast<unsigned>(top_->dout), expected);
  }
  std::fprintf(trace_, "%ld,%u,%u,%u,%u,%u,%u,%u\n", cycle_,
               static_cast<unsigned>(top_->rce),
               static_cast<unsigned>(top_->wce),
               static_cast<unsigned>(top_->we),
               static_cast<unsigned>(top_->raddr),
               static_cast<unsigned>(top_->waddr),
               static_cast<unsigned>(top_->di),
               static_cast<unsigned>(top_->dout));

  top_->eval();
}

static void drive(bool rce, bool wce, bool we, unsigned raddr, unsigned waddr,
                   unsigned di) {
  top_->rce = rce;
  top_->wce = wce;
  top_->we = we;
  top_->raddr = raddr & (DEPTH - 1);
  top_->waddr = waddr & (DEPTH - 1);
  top_->di = di & 0xFF;
  step();
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top_ = new Vgeneric_dpram;

  std::string trace_path = "trace.csv";
  for (int i = 1; i < argc; i++) {
    std::string arg = argv[i];
    const std::string prefix = "+TRACE=";
    if (arg.rfind(prefix, 0) == 0) trace_path = arg.substr(prefix.size());
  }
  trace_ = std::fopen(trace_path.c_str(), "w");
  std::fprintf(trace_, "cycle,rce,wce,we,raddr,waddr,di,dout\n");

  for (int a = 0; a < DEPTH; a++) shadow_mem[a] = 0;

  // Phase A: write every address, no reads.
  for (int a = 0; a < DEPTH; a++) {
    drive(false, true, true, a, a, (a * 7 + 3) & 0xFF);
  }

  // Phase B: read every address back in order.
  for (int a = 0; a < DEPTH; a++) {
    drive(true, false, false, a, 0, 0);
  }
  drive(false, false, false, 0, 0, 0);

  // Phase C: same-cycle read/write collisions, same address.
  for (int a = 0; a < DEPTH; a++) {
    drive(true, true, true, a, a, 0xA0 + (a & 0xF));
  }
  drive(false, false, false, 0, 0, 0);

  // Phase D: same-cycle read/write, different (non-colliding) addresses.
  drive(true, true, true, 0, 8, 0x55);
  drive(true, true, true, 8, 0, 0xAA);
  drive(false, false, false, 0, 0, 0);

  // Phase E: idle-cycle write-to-currently-latched-read-address glitch
  // forwarding.
  drive(true, false, false, 3, 0, 0);
  drive(false, true, true, 0, 3, 0xDE);
  drive(false, false, false, 0, 0, 0);
  drive(false, true, true, 0, 3, 0xEF);
  drive(false, false, false, 0, 0, 0);

  // Phase F: wce gating.
  drive(true, false, false, 5, 0, 0);
  drive(false, false, true, 0, 5, 0x11);
  drive(false, false, false, 0, 0, 0);
  drive(false, true, true, 0, 5, 0x22);
  drive(false, false, false, 0, 0, 0);

  // Phase G: deterministic fuzz.
  for (int i = 0; i < 2000; i++) {
    uint32_t r = next_lfsr();
    drive((r & 1) != 0, ((r >> 1) & 1) != 0, ((r >> 2) & 1) != 0,
          (r >> 4) & 0xF, (r >> 8) & 0xF, (r >> 16) & 0xFF);
  }

  if (errors_ == 0) {
    std::printf("PASS: generic_dpram matches independent shadow model\n");
  } else {
    std::printf("FAIL: %d mismatches\n", errors_);
  }
  std::fclose(trace_);
  top_->final();
  delete top_;
  return errors_ == 0 ? 0 : 1;
}
