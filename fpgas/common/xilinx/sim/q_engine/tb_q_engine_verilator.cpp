#include "Vq_engine_test_top.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>

static constexpr unsigned kTransfers = 64;

static uint32_t next_lfsr(uint32_t &state) {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

static uint32_t payload(unsigned index) {
    return 0x51000000u | index;
}

static void fail(const char *message, unsigned cycle, unsigned sent, unsigned received) {
    std::fprintf(stderr, "FAIL: %s cycle=%u sent=%u received=%u\n",
                 message, cycle, sent, received);
    std::exit(1);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vq_engine_test_top dut;
    std::deque<uint32_t> expected;
    uint32_t lfsr = 0x8c274a19u;
    unsigned sent = 0;
    unsigned received = 0;
    unsigned cycle = 0;
    bool in_valid = false;
    const char *trace_path = argc > 1 ? argv[1] : "trace.csv";
    FILE *trace = std::fopen(trace_path, "w");
    if (!trace) {
        std::perror(trace_path);
        return 1;
    }
    std::fprintf(trace, "cycle,in_valid,in_ready,in_data,in_last,out_ready,out_valid,out_data,out_last\n");

    dut.clk = 0;
    dut.srst = 1;
    dut.in_data = 0;
    dut.in_last = 0;
    dut.in_valid = 0;
    dut.out_ready = 0;

    for (unsigned reset_cycle = 0; reset_cycle < 8; reset_cycle++) {
        dut.clk = 0;
        dut.eval();
        dut.clk = 1;
        dut.eval();
    }
    dut.srst = 0;

    while (received < kTransfers) {
        uint32_t random_bits = next_lfsr(lfsr);
        if (!in_valid && sent < kTransfers && (random_bits & 1u)) {
            dut.in_data = payload(sent);
            dut.in_last = sent == kTransfers - 1;
            in_valid = true;
        }
        dut.in_valid = in_valid;
        dut.out_ready = (random_bits >> 1) & 1u;

        dut.clk = 0;
        dut.eval();

        if (dut.out_valid) {
            if (expected.empty())
                fail("unexpected q_engine output", cycle, sent, received);
            if (dut.out_data != expected.front())
                fail("q_engine data mismatch", cycle, sent, received);
            if (!!dut.out_last != (received == kTransfers - 1))
                fail("q_engine last mismatch", cycle, sent, received);
        }

        const bool input_fire = dut.in_valid && dut.in_ready;
        const bool output_fire = dut.out_valid && dut.out_ready;
        std::fprintf(trace, "%u,%u,%u,%08x,%u,%u,%u,%08x,%u\n",
                     cycle, dut.in_valid, dut.in_ready, dut.in_data,
                     dut.in_last, dut.out_ready, dut.out_valid,
                     dut.out_valid ? dut.out_data : 0,
                     dut.out_valid ? dut.out_last : 0);

        dut.clk = 1;
        dut.eval();

        if (output_fire) {
            expected.pop_front();
            received++;
        }
        if (input_fire) {
            expected.push_back(dut.in_data);
            sent++;
            in_valid = false;
        }
        cycle++;
        if (cycle > 30000)
            fail("q_engine timeout", cycle, sent, received);
    }

    dut.final();
    std::fclose(trace);
    if (sent != kTransfers || !expected.empty())
        fail("q_engine scoreboard did not drain", cycle, sent, received);
    std::printf("PASS: q_engine firmware DMA loopback preserved 64 stalled stream transactions\n");
    return 0;
}
