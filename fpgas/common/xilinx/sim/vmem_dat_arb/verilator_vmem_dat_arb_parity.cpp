#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <string>

#include <verilated.h>
#include "Vvmem_dat_arb_test_top.h"

static constexpr int kTransactions = 512;
static Vvmem_dat_arb_test_top *top;
static FILE *trace_file;
static std::array<std::deque<int>, 4> order_q;
static std::array<std::array<std::deque<uint32_t>, 16>, 4> data_q;
static int order_index;
static int return_index;
static int completed;
static int cycle_count;
static int errors;
static uint32_t lfsr = 0x91e10da5u;

static uint32_t tx_data(int index) { return 0xa5000000u | index; }
static int tx_dma(int index) { return (index * 3 + 1) & 3; }
static int tx_slice(int index) { return (index * 5 + 7) & 15; }

static uint32_t next_lfsr() {
  uint32_t x = lfsr;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  lfsr = x;
  return x;
}

static uint32_t output_data(int dma) {
  return top->out_data[dma];
}

static void fail(const std::string &message) {
  ++errors;
  std::fprintf(stderr, "MISMATCH cycle=%d: %s\n", cycle_count, message.c_str());
}

static void check_outputs() {
  for (int dma = 0; dma < 4; ++dma) {
    const bool expected_valid =
        !order_q[dma].empty() && !data_q[dma][order_q[dma].front()].empty();
    const bool got_valid = (top->out_valid >> dma) & 1;
    if (got_valid != expected_valid)
      fail("output valid mismatch");
    if (expected_valid
        && output_data(dma) != data_q[dma][order_q[dma].front()].front())
      fail("output payload mismatch");
  }
}

static void eval_cycle() {
  top->clk = 0;
  top->eval();
  top->clk = 1;
  top->eval();
  ++cycle_count;
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top = new Vvmem_dat_arb_test_top;

  std::string trace_path = "trace.csv";
  for (int i = 1; i < argc; ++i) {
    std::string arg = argv[i];
    if (arg.rfind("+TRACE=", 0) == 0)
      trace_path = arg.substr(7);
  }
  trace_file = std::fopen(trace_path.c_str(), "w");
  if (!trace_file)
    return 2;
  std::fprintf(trace_file, "cycle,resetn,order_valid,order_ready,order_dma,order_slice,return_valid,return_ready,return_dma,return_slice,return_data,out_ready,out_valid,out0,out1,out2,out3\n");

  top->resetn = 0;
  top->return_valid = 0;
  top->order_valid = 0;
  top->out_ready = 0;
  for (int i = 0; i < 4; ++i)
    eval_cycle();
  top->resetn = 1;
  cycle_count = 0;

  while (completed < kTransactions) {
    const uint32_t random_bits = next_lfsr();
    if (!top->order_valid && order_index < kTransactions && (random_bits & 1)) {
      top->order_valid = 1;
      top->order_dma = tx_dma(order_index);
      top->order_slice = tx_slice(order_index);
    }
    if (!top->return_valid && return_index < kTransactions && (random_bits & 2)) {
      top->return_valid = 1;
      top->return_dma = tx_dma(return_index);
      top->return_slice = tx_slice(return_index);
      top->return_data = tx_data(return_index);
    }
    top->out_ready = (random_bits >> 2) & 0xf;

    top->clk = 0;
    top->eval();
    check_outputs();
    const bool order_fire = top->order_valid && top->order_ready;
    const bool return_fire = top->return_valid && top->return_ready;
    const uint8_t output_fire = top->out_valid & top->out_ready;
    top->clk = 1;
    top->eval();
    ++cycle_count;

    if (order_fire) {
      order_q[top->order_dma].push_back(top->order_slice);
      ++order_index;
      top->order_valid = 0;
    }
    if (return_fire) {
      data_q[top->return_dma][top->return_slice].push_back(top->return_data);
      ++return_index;
      top->return_valid = 0;
    }

    for (int dma = 0; dma < 4; ++dma) {
      if ((output_fire >> dma) & 1) {
        data_q[dma][order_q[dma].front()].pop_front();
        order_q[dma].pop_front();
        ++completed;
      }
    }
    check_outputs();

    std::fprintf(trace_file, "%d,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%x,%x,%x,%x,%x,%x\n",
                 cycle_count, top->resetn, top->order_valid, top->order_ready,
                 top->order_dma, top->order_slice, top->return_valid,
                 top->return_ready, top->return_dma, top->return_slice,
                 top->return_data, top->out_ready, top->out_valid,
                 output_data(0), output_data(1), output_data(2), output_data(3));

    if (cycle_count > 20000) {
      fail("timeout");
      break;
    }
  }

  if (errors == 0)
    std::puts("PASS: VMEM arbiter preserved 512 ordered transactions under independent input and output stalls");
  else
    std::printf("FAIL: %d VMEM arbiter mismatches\n", errors);

  std::fclose(trace_file);
  top->final();
  delete top;
  return errors == 0 ? 0 : 1;
}
