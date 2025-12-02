// Verilator cycle-driver for `generic_fifo_sc_a`
// (libs/ip-library/fwft_fifos/sc_fifo/hdl/generic_fifo_sc_a.v).
//
// Mirrors tb_generic_fifo_sc_a_parity.sv: same directed phases (fill,
// drain, clr-mid-operation, simultaneous we&re, ALMOST_FULL threshold
// crossing, mid-run reset), the same deterministic xorshift fuzz sequence
// gated to defined transactions only, and the same independent
// control-plane shadow model, so the two traces can also be diffed via
// ../compare_traces.py.
#include <cstdint>
#include <cstdio>
#include <string>
#include <verilated.h>
#include "Vgeneric_fifo_sc_a.h"

static const int DW = 8;
static const int AW = 4;
static const int N = 4;
static const int ALMOST_FULL = 5;
static const int MAX_SIZE = 1 << AW;
static const unsigned WMASK = (1u << AW) - 1;
static const unsigned CMASK = (1u << (AW + 1)) - 1;

static Vgeneric_fifo_sc_a *top_;
static FILE *trace_;
static long cycle_ = 0;
static int errors_ = 0;

// ---- Independent control-plane shadow model (mirrors the SV testbench) ----
static unsigned m_wp = 0, m_rp = 0;
static bool m_gb = false, m_gb2 = false;
static unsigned m_cnt = 0;
static bool m_full_r = false, m_empty_r = true, m_full_n_r = false, m_empty_n_r = true;
static uint32_t m_fillcount = 0;
static bool m_afull = false, m_afull_n = false, m_o_afull_n_d = false, m_temp = false;
static bool m_full = false, m_empty = false, m_full_n = false, m_empty_n = false;
static unsigned m_level = 0;

static void model_reset() {
  m_wp = 0; m_rp = 0; m_gb = false; m_gb2 = false; m_cnt = 0;
  m_full_r = false; m_empty_r = true; m_full_n_r = false; m_empty_n_r = true;
  m_fillcount = 0; m_afull = false; m_afull_n = false; m_o_afull_n_d = false;
  m_temp = false;
}

static void model_update(bool i_rst, bool i_clr, bool i_we, bool i_re) {
  unsigned o_wp = m_wp, o_rp = m_rp;
  bool o_gb = m_gb, o_gb2 = m_gb2;
  unsigned o_cnt = m_cnt;
  uint32_t o_fillcount = m_fillcount;
  bool o_temp = m_temp;
  unsigned wp_pl1 = (o_wp + 1) & WMASK;
  unsigned wp_pl2 = (o_wp + 2) & WMASK;
  unsigned rp_pl1 = (o_rp + 1) & WMASK;

  if (!i_rst) {
    model_reset();
    return;
  }

  if (i_clr) {
    m_wp = 0; m_rp = 0; m_gb = false; m_gb2 = false; m_cnt = 0;
    m_full_r = false; m_empty_r = true; m_full_n_r = false; m_empty_n_r = true;
    // fillcount/afull/afull_n/o_afull_n_d/temp deliberately do NOT respond
    // to clr in the RTL (only to rst) -- see README.
  } else {
    if (wp_pl1 == o_rp && i_we) m_gb = true;
    else if (i_re) m_gb = false;

    if (wp_pl2 == o_rp && i_we) m_gb2 = true;
    else if (o_wp != o_rp && i_re) m_gb2 = false;

    if (i_we) m_wp = wp_pl1;
    if (i_re) m_rp = rp_pl1;

    if (i_re && !i_we) m_cnt = (o_cnt - 1) & CMASK;
    else if (!i_re && i_we) m_cnt = (o_cnt + 1) & CMASK;

    if (i_we && (wp_pl1 == o_rp) && o_gb2 && !i_re) m_full_r = true;
    else if (i_re && ((wp_pl1 != o_rp) || !o_gb2) && !i_we) m_full_r = false;

    if (i_we && ((o_wp != rp_pl1) || o_gb2) && !i_re) m_empty_r = false;
    else if (i_re && ((o_wp == rp_pl1) && !o_gb2) && !i_we) m_empty_r = true;

    if (i_we && (static_cast<int>(o_cnt) >= (N - 1)) && !i_re) m_empty_n_r = false;
    else if (i_re && (static_cast<int>(o_cnt) <= N) && !i_we) m_empty_n_r = true;

    if (i_we && (static_cast<int>(o_cnt) >= (MAX_SIZE - N)) && !i_re) m_full_n_r = true;
    else if (i_re && (static_cast<int>(o_cnt) <= (MAX_SIZE - N + 1)) && !i_we) m_full_n_r = false;
  }

  if (o_fillcount >= static_cast<uint32_t>(ALMOST_FULL)) {
    m_afull = true; m_afull_n = false; m_temp = false;
  } else {
    m_afull = false; m_afull_n = true; m_temp = true;
  }
  m_o_afull_n_d = o_temp;
  if (o_wp > o_rp) m_fillcount = o_wp - o_rp;
  else if (o_rp > o_wp) m_fillcount = (1u << AW) - o_rp + o_wp;
  else m_fillcount = 0;
}

static void model_derive_outputs() {
  m_full = (m_wp == m_rp) && m_gb;
  m_empty = (m_wp == m_rp) && !m_gb;
  m_full_n = !(static_cast<int>(m_cnt) < (MAX_SIZE - N + 1));
  m_empty_n = (static_cast<int>(m_cnt) < N);
  bool msb = (m_cnt >> AW) & 1;
  unsigned upper2 = (m_cnt >> (AW - 2)) & 0x3;
  m_level = (msb ? 0x3 : 0x0) | upper2;
}

static void check_field(const char *name, bool exp, bool got) {
  if (exp != got) {
    errors_++;
    std::fprintf(stderr, "MISMATCH cycle=%ld field=%s expected=%d got=%d\n",
                 cycle_, name, exp, got);
  }
}

static void step(bool i_we, bool i_re, bool i_clr, uint8_t i_din) {
  top_->we = i_we;
  top_->re = i_re;
  top_->clr = i_clr;
  top_->din = i_din;

  top_->clk = 0;
  top_->eval();
  top_->clk = 1;
  top_->eval();

  cycle_++;
  bool rst_now = top_->rst;
  model_update(rst_now, i_clr, i_we, i_re);
  model_derive_outputs();

  check_field("full", m_full, top_->full);
  check_field("empty", m_empty, top_->empty);
  check_field("full_r", m_full_r, top_->full_r);
  check_field("empty_r", m_empty_r, top_->empty_r);
  check_field("full_n", m_full_n, top_->full_n);
  check_field("empty_n", m_empty_n, top_->empty_n);
  check_field("full_n_r", m_full_n_r, top_->full_n_r);
  check_field("empty_n_r", m_empty_n_r, top_->empty_n_r);
  check_field("level0", (m_level & 1) != 0, (top_->level & 1) != 0);
  check_field("level1", (m_level & 2) != 0, (top_->level & 2) != 0);
  check_field("afull", m_afull, top_->afull);
  check_field("afull_n", m_afull_n, top_->afull_n);
  check_field("o_afull_n_d", m_o_afull_n_d, top_->o_afull_n_d);
  if (m_fillcount != top_->fillcount) {
    errors_++;
    std::fprintf(stderr, "MISMATCH cycle=%ld field=fillcount expected=%u got=%u\n",
                 cycle_, m_fillcount, static_cast<unsigned>(top_->fillcount));
  }

  std::fprintf(trace_,
               "%ld,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u\n",
               cycle_, static_cast<unsigned>(top_->rst), static_cast<unsigned>(i_clr),
               static_cast<unsigned>(i_we), static_cast<unsigned>(i_re),
               static_cast<unsigned>(i_din), static_cast<unsigned>(top_->dout),
               static_cast<unsigned>(top_->full), static_cast<unsigned>(top_->empty),
               static_cast<unsigned>(top_->full_r), static_cast<unsigned>(top_->empty_r),
               static_cast<unsigned>(top_->full_n), static_cast<unsigned>(top_->empty_n),
               static_cast<unsigned>(top_->full_n_r), static_cast<unsigned>(top_->empty_n_r),
               static_cast<unsigned>(top_->level), static_cast<unsigned>(top_->afull),
               static_cast<unsigned>(top_->afull_n), static_cast<unsigned>(top_->o_afull_n_d),
               static_cast<unsigned>(top_->fillcount));

  top_->eval();
}

static uint32_t lfsr_ = 0x12345678u;
static uint32_t next_lfsr() {
  uint32_t x = lfsr_;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  lfsr_ = x;
  return x;
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top_ = new Vgeneric_fifo_sc_a;

  std::string trace_path = "trace.csv";
  for (int i = 1; i < argc; i++) {
    std::string arg = argv[i];
    const std::string prefix = "+TRACE=";
    if (arg.rfind(prefix, 0) == 0) trace_path = arg.substr(prefix.size());
  }
  trace_ = std::fopen(trace_path.c_str(), "w");
  std::fprintf(trace_, "cycle,rst,clr,we,re,din,dout,full,empty,full_r,empty_r,"
                       "full_n,empty_n,full_n_r,empty_n_r,level,afull,afull_n,"
                       "o_afull_n_d,fillcount\n");

  top_->rst = 0; // assert reset (active low)
  top_->clr = 0;
  top_->we = 0;
  top_->re = 0;
  top_->din = 0;
  model_reset();
  for (int i = 0; i < 3; i++) step(false, false, false, 0);

  top_->rst = 1; // release reset
  step(false, false, false, 0);

  // Phase A: fill to full.
  for (int i = 0; i < MAX_SIZE; i++) step(true, false, false, 0x10 + i);

  // Phase B: drain to empty.
  for (int i = 0; i < MAX_SIZE; i++) step(false, true, false, 0);

  // Phase C: clr mid-operation.
  for (int i = 0; i < 6; i++) step(true, false, false, 0x20 + i);
  step(false, false, true, 0); // clr pulse
  step(false, false, false, 0);

  // Phase D: simultaneous we&re at a partial fill level.
  for (int i = 0; i < 4; i++) step(true, false, false, 0x30 + i);
  for (int i = 0; i < 8; i++) step(true, true, false, 0x40 + i);
  for (int i = 0; i < 4; i++) step(false, true, false, 0);

  // Phase E: cross the ALMOST_FULL threshold and back.
  for (int i = 0; i < MAX_SIZE; i++) step(true, false, false, 0x50 + i);
  for (int i = 0; i < MAX_SIZE; i++) step(false, true, false, 0);

  // Phase F: mid-run reset re-assertion.
  top_->rst = 0;
  step(false, false, false, 0);
  top_->rst = 1;
  step(false, false, false, 0);

  // Phase G: deterministic fuzz, gated to defined transactions only.
  for (int i = 0; i < 5000; i++) {
    uint32_t r = next_lfsr();
    bool want_we = (r & 1) != 0;
    bool want_re = ((r >> 1) & 1) != 0;
    bool want_clr = ((r >> 2) & 0xFF) == 0xFF; // rare
    bool fifo_we = want_we && !top_->full;
    bool fifo_re = want_re && !top_->empty;
    step(fifo_we, fifo_re, want_clr, (r >> 16) & 0xFF);
  }

  if (errors_ == 0) {
    std::printf("PASS: generic_fifo_sc_a matches independent control-plane model\n");
  } else {
    std::printf("FAIL: %d mismatches\n", errors_);
  }
  std::fclose(trace_);
  top_->final();
  delete top_;
  return errors_ == 0 ? 0 : 1;
}
