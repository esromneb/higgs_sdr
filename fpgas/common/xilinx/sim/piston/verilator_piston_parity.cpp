#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <string>

#include <verilated.h>
#include "Vpiston_test_top.h"

static constexpr int kWritesPerDma = 32;
static constexpr int kReadsPerDma = 128;
static constexpr int kResetReadsPerDma = 8;

static Vpiston_test_top *top;
static FILE *trace_file;
static std::array<int, 4> write_index{};
static std::array<int, 4> reset_read_index{};
static std::array<int, 4> read_index{};
static std::array<std::deque<uint32_t>, 4> expected_q;
static uint32_t lfsr = 0x36a97c51u;
static int completed;
static int cycle_count;

static uint32_t next_lfsr() {
  uint32_t x = lfsr;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  lfsr = x;
  return x;
}

static uint16_t write_addr(int owner, int index) {
  const uint16_t row = owner * kWritesPerDma + index;
  const uint16_t bank = (index * 5 + owner * 3) & 15;
  return (row << 4) | bank;
}

static uint32_t write_data(int owner, int index) {
  return 0xe0000000u | (owner << 16) | index;
}

static uint16_t read_addr(int dma, int index) {
  const int owner = (index * 3 + dma) & 3;
  const int write_slot = (index * 7 + dma * 11) % kWritesPerDma;
  return write_addr(owner, write_slot);
}

static uint32_t read_data(int dma, int index) {
  const int owner = (index * 3 + dma) & 3;
  const int write_slot = (index * 7 + dma * 11) % kWritesPerDma;
  return write_data(owner, write_slot);
}

static uint64_t pack_request(bool write, uint16_t addr, uint32_t data) {
  return (static_cast<uint64_t>(write) << 48)
       | (static_cast<uint64_t>(addr) << 32) | data;
}

static void set_input(int dma, uint64_t value) {
  switch (dma) {
    case 0: top->in0 = value; break;
    case 1: top->in1 = value; break;
    case 2: top->in2 = value; break;
    default: top->in3 = value; break;
  }
}

static uint64_t get_input(int dma) {
  switch (dma) {
    case 0: return top->in0;
    case 1: return top->in1;
    case 2: return top->in2;
    default: return top->in3;
  }
}

static uint32_t get_output(int dma) {
  switch (dma) {
    case 0: return top->out0;
    case 1: return top->out1;
    case 2: return top->out2;
    default: return top->out3;
  }
}

static void eval_cycle() {
  top->clk = 0;
  top->eval();
  top->clk = 1;
  top->eval();
}

static void check_outputs() {
  for (int dma = 0; dma < 4; ++dma) {
    if ((top->out_valid >> dma) & 1) {
      if (expected_q[dma].empty()) {
        std::fprintf(stderr, "FAIL: dma%d unexpected response cycle=%d\n",
                     dma, cycle_count);
        std::exit(1);
      }
      if (get_output(dma) != expected_q[dma].front()) {
        std::fprintf(stderr,
                     "FAIL: dma%d expected=%08x got=%08x cycle=%d\n",
                     dma, expected_q[dma].front(), get_output(dma),
                     cycle_count);
        std::exit(1);
      }
    }
  }
}

static void log_cycle() {
  std::fprintf(trace_file,
               "%d,%u,%x,%x,%llx,%llx,%llx,%llx,%x,%x,%x,%x,%x,%x\n",
               cycle_count, top->reset_n, top->in_valid, top->in_ready,
               static_cast<unsigned long long>(get_input(0)),
               static_cast<unsigned long long>(get_input(1)),
               static_cast<unsigned long long>(get_input(2)),
               static_cast<unsigned long long>(get_input(3)),
               top->out_ready, top->out_valid, get_output(0), get_output(1),
               get_output(2), get_output(3));
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top = new Vpiston_test_top;

  std::string trace_path = "trace.csv";
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg.rfind("+TRACE=", 0) == 0)
      trace_path = arg.substr(7);
  }
  trace_file = std::fopen(trace_path.c_str(), "w");
  if (!trace_file)
    return 2;
  std::fprintf(trace_file,
               "cycle,resetn,in_valid,in_ready,in0,in1,in2,in3,out_ready,out_valid,out0,out1,out2,out3\n");

  top->reset_n = 0;
  top->in_valid = 0;
  top->out_ready = 0;
  for (int dma = 0; dma < 4; ++dma)
    set_input(dma, 0);
  for (int i = 0; i < 5; ++i)
    eval_cycle();
  top->reset_n = 1;

  bool all_done = false;
  while (!all_done) {
    const uint32_t random_bits = next_lfsr();
    for (int dma = 0; dma < 4; ++dma) {
      if (!((top->in_valid >> dma) & 1)
          && write_index[dma] < kWritesPerDma
          && ((random_bits >> dma) & 1)) {
        set_input(dma, pack_request(true, write_addr(dma, write_index[dma]),
                                    write_data(dma, write_index[dma])));
        top->in_valid |= 1u << dma;
      }
    }
    top->clk = 0;
    top->eval();
    const uint8_t input_fire = top->in_valid & top->in_ready;
    top->clk = 1;
    top->eval();
    for (int dma = 0; dma < 4; ++dma) {
      if ((input_fire >> dma) & 1) {
        ++write_index[dma];
        top->in_valid &= ~(1u << dma);
      }
    }
    all_done = true;
    for (int dma = 0; dma < 4; ++dma)
      if (write_index[dma] != kWritesPerDma)
        all_done = false;
  }

  top->in_valid = 0;
  for (int i = 0; i < 100; ++i)
    eval_cycle();

  all_done = false;
  while (!all_done) {
    for (int dma = 0; dma < 4; ++dma) {
      if (!((top->in_valid >> dma) & 1)
          && reset_read_index[dma] < kResetReadsPerDma) {
        set_input(dma, pack_request(false,
                                    read_addr(dma, reset_read_index[dma]), 0));
        top->in_valid |= 1u << dma;
      }
    }
    top->out_ready = 0;
    top->clk = 0;
    top->eval();
    const uint8_t input_fire = top->in_valid & top->in_ready;
    top->clk = 1;
    top->eval();
    for (int dma = 0; dma < 4; ++dma) {
      if ((input_fire >> dma) & 1) {
        ++reset_read_index[dma];
        top->in_valid &= ~(1u << dma);
      }
    }
    all_done = true;
    for (int dma = 0; dma < 4; ++dma)
      if (reset_read_index[dma] != kResetReadsPerDma)
        all_done = false;
  }

  for (int i = 0; i < 30; ++i)
    eval_cycle();
  if (top->out_valid == 0) {
    std::fprintf(stderr, "FAIL: reset test failed to queue responses\n");
    return 1;
  }
  top->reset_n = 0;
  top->in_valid = 0;
  for (int i = 0; i < 5; ++i)
    eval_cycle();
  top->reset_n = 1;
  for (int i = 0; i < 5; ++i)
    eval_cycle();
  if (top->out_valid != 0) {
    std::fprintf(stderr, "FAIL: reset did not discard piston responses\n");
    return 1;
  }

  cycle_count = 0;
  while (completed < 4 * kReadsPerDma) {
    const uint32_t random_bits = next_lfsr();
    for (int dma = 0; dma < 4; ++dma) {
      if (!((top->in_valid >> dma) & 1)
          && read_index[dma] < kReadsPerDma
          && ((random_bits >> dma) & 1)) {
        set_input(dma,
                  pack_request(false, read_addr(dma, read_index[dma]), 0));
        top->in_valid |= 1u << dma;
      }
    }
    top->out_ready = (random_bits >> 4) & 0xf;
    top->clk = 0;
    top->eval();
    check_outputs();
    const uint8_t input_fire = top->in_valid & top->in_ready;
    const uint8_t output_fire = top->out_valid & top->out_ready;
    top->clk = 1;
    top->eval();
    ++cycle_count;

    for (int dma = 0; dma < 4; ++dma) {
      if ((output_fire >> dma) & 1) {
        expected_q[dma].pop_front();
        ++completed;
      }
      if ((input_fire >> dma) & 1) {
        expected_q[dma].push_back(read_data(dma, read_index[dma]));
        ++read_index[dma];
        top->in_valid &= ~(1u << dma);
      }
    }
    check_outputs();
    log_cycle();
    if (cycle_count > 30000) {
      std::fprintf(stderr, "FAIL: timeout completed=%d\n", completed);
      return 1;
    }
  }

  std::puts("PASS: piston preserved 512 ordered VMEM reads through its stalled external DMA interfaces");
  std::fclose(trace_file);
  top->final();
  delete top;
  return 0;
}
