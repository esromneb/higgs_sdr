#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <string>

#include <verilated.h>
#include "Vfwft_sc_fifo.h"

static constexpr unsigned kDepth = 16;
static constexpr unsigned kEffectiveCapacity = kDepth + 2;

static Vfwft_sc_fifo *top;
static FILE *trace_file;
static std::deque<uint8_t> expected;
static uint8_t held_data;
static bool held_valid;
static uint64_t cycle_count;
static int errors;

static void fail(const std::string &message) {
  ++errors;
  std::fprintf(stderr, "MISMATCH cycle=%llu: %s\n",
               static_cast<unsigned long long>(cycle_count), message.c_str());
}

static void step(bool rst, bool wren, bool rden, uint8_t wdata) {
  top->clk = 0;
  top->rst = rst;
  top->wren = wren;
  top->rden = rden;
  top->wdata = wdata;
  top->eval();

  const bool pre_valid = top->rdata_vld;
  const bool pre_full = top->full;
  const bool pre_afull_n = top->o_afull_n;
  const uint8_t pre_data = top->rdata;
  const uint32_t pre_fillcount = top->fillcount;

  top->clk = 1;
  top->eval();
  ++cycle_count;

  if (rst) {
    expected.clear();
    held_valid = false;
  } else {
    if (pre_valid && rden) {
      if (expected.empty()) {
        fail("read handshake occurred with an empty scoreboard");
      } else {
        const uint8_t expected_front = expected.front();
        expected.pop_front();
        if (pre_data != expected_front) {
          char buffer[128];
          std::snprintf(buffer, sizeof(buffer),
                        "consumed payload expected=0x%02x got=0x%02x",
                        expected_front, pre_data);
          fail(buffer);
        }
      }
    }

    if (wren && !pre_full)
      expected.push_back(wdata);

    if (expected.size() > kEffectiveCapacity)
      fail("accepted occupancy exceeds effective capacity");

    if (top->rdata_vld) {
      if (expected.empty()) {
        fail("rdata_vld asserted with an empty scoreboard");
      } else if (top->rdata != expected.front()) {
        char buffer[128];
        std::snprintf(buffer, sizeof(buffer),
                      "presented payload expected=0x%02x got=0x%02x",
                      expected.front(), static_cast<unsigned>(top->rdata));
        fail(buffer);
      }
    }

    if (held_valid && !rden) {
      if (!top->rdata_vld) {
        fail("rdata_vld dropped while output was backpressured");
      } else if (top->rdata != held_data) {
        fail("rdata changed while output was backpressured");
      }
    }

    if (static_cast<bool>(top->o_afull) != (pre_fillcount >= 11))
      fail("o_afull does not match the prior-cycle fillcount threshold");
    if (static_cast<bool>(top->o_afull_n) != (pre_fillcount < 11))
      fail("o_afull_n does not match the prior-cycle fillcount threshold");
    if (static_cast<bool>(top->o_afull_n_d) != pre_afull_n)
      fail("o_afull_n_d does not match the prior o_afull_n value");

    held_valid = top->rdata_vld;
    held_data = top->rdata;
  }

  std::fprintf(trace_file, "%llu,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u\n",
               static_cast<unsigned long long>(cycle_count),
               static_cast<unsigned>(rst), static_cast<unsigned>(wren),
               static_cast<unsigned>(rden), static_cast<unsigned>(wdata),
               static_cast<unsigned>(top->rdata),
               static_cast<unsigned>(top->rdata_vld),
               static_cast<unsigned>(top->full),
               static_cast<unsigned>(top->o_afull),
               static_cast<unsigned>(top->o_afull_n),
               static_cast<unsigned>(top->o_afull_n_d),
               static_cast<unsigned>(top->fillcount));
}

static void wait_for_valid(unsigned timeout) {
  unsigned waited = 0;
  while (!top->rdata_vld && waited < timeout) {
    step(false, false, false, 0);
    ++waited;
  }
  if (!top->rdata_vld)
    fail("timed out waiting for FWFT output");
}

static uint32_t lfsr = 0x6d2b79f5u;
static uint32_t next_lfsr() {
  uint32_t x = lfsr;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  lfsr = x;
  return x;
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top = new Vfwft_sc_fifo;

  std::string trace_path = "trace.csv";
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    const std::string prefix = "+TRACE=";
    if (arg.rfind(prefix, 0) == 0)
      trace_path = arg.substr(prefix.size());
  }

  trace_file = std::fopen(trace_path.c_str(), "w");
  if (!trace_file) {
    std::perror("fopen");
    return 2;
  }
  std::fprintf(trace_file,
               "cycle,rst,wren,rden,wdata,rdata,rdata_vld,full,o_afull,"
               "o_afull_n,o_afull_n_d,fillcount\n");

  held_valid = false;
  for (int i = 0; i < 3; ++i)
    step(true, false, false, 0);
  step(false, false, false, 0);

  step(false, true, false, 0xa5);
  wait_for_valid(5);
  for (int i = 0; i < 4; ++i)
    step(false, false, false, 0);
  step(false, false, true, 0);

  for (int i = 0; i < 8; ++i)
    step(false, true, false, 0x20 + i);
  for (int i = 0; i < 24; ++i)
    step(false, false, (i % 3) != 0, 0);

  while (!top->full && expected.size() <= kEffectiveCapacity)
    step(false, true, false, 0x80 + expected.size());
  if (!top->full)
    fail("full did not assert at the bounded capacity");
  if (expected.size() != kEffectiveCapacity)
    fail("full asserted at an unexpected occupancy");

  while (!expected.empty())
    step(false, false, true, 0);
  for (int i = 0; i < 3; ++i)
    step(false, false, true, 0);
  if (top->rdata_vld)
    fail("rdata_vld remained asserted after complete drain");

  for (int i = 0; i < 6; ++i)
    step(false, true, false, 0x40 + i);
  wait_for_valid(5);
  for (int i = 0; i < 64; ++i)
    step(false, true, true, 0xc0 + i);

  for (int i = 0; i < 5; ++i)
    step(false, true, false, 0xe0 + i);
  step(true, false, false, 0);
  step(false, false, false, 0);
  if (top->rdata_vld)
    fail("rdata_vld did not clear across reset");

  for (int i = 0; i < 5000; ++i) {
    const uint32_t r = next_lfsr();
    const bool do_reset = ((r >> 2) & 0x3ffu) == 0x3ffu;
    const bool do_write = (r & 1u) && !top->full && !do_reset;
    step(do_reset, do_write, ((r >> 1) & 1u) && !do_reset,
         static_cast<uint8_t>(r >> 16));
    if (do_reset)
      step(false, false, false, 0);
  }

  while (!expected.empty())
    step(false, false, true, 0);
  for (int i = 0; i < 3; ++i)
    step(false, false, true, 0);

  if (errors == 0)
    std::puts("PASS: fwft_sc_fifo preserves ordering, FWFT, backpressure, capacity, and reset behavior");
  else
    std::printf("FAIL: fwft_sc_fifo had %d mismatches\n", errors);

  std::fclose(trace_file);
  top->final();
  delete top;
  return errors == 0 ? 0 : 1;
}
