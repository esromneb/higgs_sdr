#include "Valu54b_dual_top.h"
#include "verilated.h"

#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <string>

namespace {

uint32_t next_random(uint32_t value) {
    const uint32_t feedback =
        ((value >> 31) ^ (value >> 21) ^ (value >> 1) ^ value) & 1U;
    return (value << 1) | feedback;
}

// Mirrors the SV testbench's `{random_state[3:0], random_state}` widening of
// a 32-bit LFSR word into a 36-bit operand.
uint64_t widen36(uint32_t random_state) {
    const uint64_t top_nibble = random_state & 0xFU;
    return (top_nibble << 32) | static_cast<uint64_t>(random_state);
}

constexpr uint64_t kMask36 = (1ULL << 36) - 1;
constexpr uint64_t kMask55 = (1ULL << 55) - 1;

std::string trace_path(int argc, char** argv) {
    constexpr char prefix[] = "+TRACE=";
    for (int index = 1; index < argc; ++index) {
        const std::string argument(argv[index]);
        if (argument.compare(0, sizeof(prefix) - 1, prefix) == 0)
            return argument.substr(sizeof(prefix) - 1);
    }
    return "alu54b_parity.csv";
}

class Testbench {
  public:
    explicit Testbench(const std::string& path) : trace_(path) {
        top_.clk = 0;
        top_.rst = 0;
        top_.a = 0;
        top_.b = 0;
        top_.subadd = 0;
        top_.ce = 0;
        top_.eval();
        trace_ << "cycle,rst,ce,a,b,subadd,xil_c\n";
    }

    int run() {
        // Reset assertion/deassertion.
        drive(1, 1, 0, 0, 0);
        drive(1, 1, 0, 0, 0);
        drive(0, 1, 0, 0, 0);

        // Basic add/sub with small positive values.
        drive(0, 1, 10, 3, 0);
        drive(0, 1, 10, 3, 1);
        drive(0, 1, 0, 0, 0);
        drive(0, 1, 0, 0, 0);

        // Signed extremes: max positive / max negative 36-bit operands.
        drive(0, 1, 0x07FFFFFFFFULL, 0x07FFFFFFFFULL, 0);
        drive(0, 1, 0x800000000ULL, 0x800000000ULL, 1);
        drive(0, 1, 0x07FFFFFFFFULL, 0x800000000ULL, 0);
        drive(0, 1, 0x800000000ULL, 0x07FFFFFFFFULL, 1);
        drive(0, 1, 0, 0, 0);
        drive(0, 1, 0, 0, 0);

        // ce toggling: proves no accidental divergence if either
        // implementation later gates on it.
        drive(0, 0, 42, 7, 0);
        drive(0, 0, 99, 1, 1);
        drive(0, 1, 5, 5, 0);
        drive(0, 0, 5, 5, 0);
        drive(0, 1, 0, 0, 0);

        // Idle cycle.
        drive(0, 1, 0, 0, 0);

        // Deterministic fuzz: random 36-bit signed operands, subadd, ce.
        uint32_t random_state = 1;
        for (unsigned index = 0; index < 1000; ++index) {
            random_state = next_random(random_state);
            const uint64_t fa = widen36(random_state);
            const bool subadd = (random_state >> 4) & 1U;
            const bool ce = (random_state >> 5) & 1U;
            random_state = next_random(random_state);
            const uint64_t fb = widen36(random_state);
            drive(0, ce, fa, fb, subadd);
        }

        return errors_ == 0 ? 0 : 1;
    }

  private:
    void drive(int r, int c, uint64_t ta, uint64_t tb, int sa) {
        top_.rst = r != 0;
        top_.ce = c != 0;
        top_.a = ta & kMask36;
        top_.b = tb & kMask36;
        top_.subadd = sa != 0;

        top_.clk = 0;
        top_.eval();
        top_.clk = 1;
        top_.eval();
        ++cycle_;

        const uint64_t ref_c = top_.ref_c;
        const uint64_t xil_c = top_.xil_c;
        if (ref_c != xil_c) {
            std::cerr << "mismatch at cycle " << cycle_ << ": ref=" << std::hex
                       << ref_c << " xil=" << xil_c << std::dec << '\n';
            ++errors_;
        }

        trace_ << cycle_ << ',' << static_cast<unsigned>(top_.rst) << ','
               << static_cast<unsigned>(top_.ce) << ',' << std::hex
               << std::setw(9) << std::setfill('0') << (top_.a & kMask36)
               << ',' << std::setw(9) << (top_.b & kMask36) << ','
               << std::dec << static_cast<unsigned>(top_.subadd) << ','
               << std::hex << std::setw(14) << (xil_c & kMask55)
               << std::dec << '\n';
    }

    Valu54b_dual_top top_;
    std::ofstream trace_;
    unsigned cycle_ = 0;
    unsigned errors_ = 0;
};

}  // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Testbench testbench(trace_path(argc, argv));
    return testbench.run();
}
