#include "Vmuladdsub.h"
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

int32_t sign_extend18(uint32_t value) {
    value &= 0x3FFFFU;
    if (value & 0x20000U)
        return static_cast<int32_t>(value | 0xFFFC0000U);
    return static_cast<int32_t>(value);
}

std::string trace_path(int argc, char** argv) {
    constexpr char prefix[] = "+TRACE=";
    for (int index = 1; index < argc; ++index) {
        const std::string argument(argv[index]);
        if (argument.compare(0, sizeof(prefix) - 1, prefix) == 0)
            return argument.substr(sizeof(prefix) - 1);
    }
    return "muladdsub_parity.csv";
}

class Testbench {
  public:
    explicit Testbench(const std::string& path) : trace_(path) {
        top_.CLK0 = 0;
        top_.RST0 = 0;
        top_.CE0 = 0;
        top_.CE1 = 0;
        top_.CE2 = 0;
        top_.ADDNSUB = 0;
        top_.A0 = 0;
        top_.A1 = 0;
        top_.B0 = 0;
        top_.B1 = 0;
        top_.eval();
        trace_ << "cycle,rst,ce0,ce1,ce2,addnsub,a0,a1,b0,b1,sum\n";
    }

    int run() {
        // Reset assertion/deassertion with CEs already high.
        drive(1, 1, 1, 1, 0, 0, 0, 0, 0);
        drive(1, 1, 1, 1, 0, 0, 0, 0, 0);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);

        // Flow-through: distinct small positive values, all CEs held high.
        drive(0, 1, 1, 1, 0, 3, 5, 7, 11);
        drive(0, 1, 1, 1, 1, 3, 5, 7, 11);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);

        // Signed extremes: max positive and max negative 18-bit operands.
        drive(0, 1, 1, 1, 0, 0x1FFFF, 0x1FFFF, 0x1FFFF, 0x1FFFF);
        drive(0, 1, 1, 1, 1, 0x20000, 0x20000, 0x20000, 0x20000);
        drive(0, 1, 1, 1, 0, 0x20000, 0x1FFFF, 0x1FFFF, 0x20000);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);

        // CE0 gating: freeze stage 1 while inputs keep changing.
        drive(0, 1, 1, 1, 0, 9, 2, 4, 1);
        drive(0, 0, 1, 1, 0, 99, 88, 77, 66);
        drive(0, 0, 1, 1, 0, 55, 44, 33, 22);
        drive(0, 1, 1, 1, 0, 1, 1, 1, 1);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);

        // CE1 gating: freeze stage 2 (the multiply result) mid-flow.
        drive(0, 1, 1, 1, 0, 6, 3, 2, 9);
        drive(0, 1, 0, 1, 0, 1, 1, 1, 1);
        drive(0, 1, 0, 1, 0, 2, 2, 2, 2);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);

        // CE2 gating: freeze the final add/sub output mid-flow.
        drive(0, 1, 1, 1, 0, 10, 4, 3, 2);
        drive(0, 1, 1, 0, 1, 1, 1, 1, 1);
        drive(0, 1, 1, 0, 1, 2, 2, 2, 2);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);

        // Idle cycle with all CEs low.
        drive(0, 0, 0, 0, 0, 0, 0, 0, 0);

        // Deterministic fuzz: random operands, CE gating, and ADDNSUB.
        uint32_t random_state = 1;
        for (unsigned index = 0; index < 1000; ++index) {
            random_state = next_random(random_state);
            uint32_t a0 = random_state & 0x3FFFFU;
            bool addnsub = (random_state >> 18) & 1U;
            bool ce0 = (random_state >> 19) & 1U;
            random_state = next_random(random_state);
            uint32_t a1 = random_state & 0x3FFFFU;
            bool ce1 = (random_state >> 18) & 1U;
            random_state = next_random(random_state);
            uint32_t b0 = random_state & 0x3FFFFU;
            bool ce2 = (random_state >> 18) & 1U;
            random_state = next_random(random_state);
            uint32_t b1 = random_state & 0x3FFFFU;
            drive_bool(0, ce0, ce1, ce2, addnsub, a0, a1, b0, b1);
        }

        return errors_ == 0 ? 0 : 1;
    }

  private:
    void drive(int r, int c0, int c1, int c2, int asub, uint32_t ta0,
               uint32_t ta1, uint32_t tb0, uint32_t tb1) {
        drive_bool(r != 0, c0 != 0, c1 != 0, c2 != 0, asub != 0, ta0, ta1, tb0,
                   tb1);
    }

    void drive_bool(bool r, bool c0, bool c1, bool c2, bool asub,
                     uint32_t ta0, uint32_t ta1, uint32_t tb0, uint32_t tb1) {
        top_.RST0 = r;
        top_.CE0 = c0;
        top_.CE1 = c1;
        top_.CE2 = c2;
        top_.ADDNSUB = asub;
        top_.A0 = ta0 & 0x3FFFFU;
        top_.A1 = ta1 & 0x3FFFFU;
        top_.B0 = tb0 & 0x3FFFFU;
        top_.B1 = tb1 & 0x3FFFFU;

        // Model update: all three stages read pre-edge state, mirroring the
        // RTL's independent always blocks sampling the same pre-edge
        // registers before any of them commit.
        const uint32_t old_a0_r = m_a0_r_;
        const uint32_t old_a1_r = m_a1_r_;
        const uint32_t old_b0_r = m_b0_r_;
        const uint32_t old_b1_r = m_b1_r_;
        const int64_t old_ab0_r = m_ab0_r_;
        const int64_t old_ab1_r = m_ab1_r_;

        if (r) {
            m_a0_r_ = 0;
            m_a1_r_ = 0;
            m_b0_r_ = 0;
            m_b1_r_ = 0;
        } else if (c0) {
            m_a0_r_ = top_.A0;
            m_a1_r_ = top_.A1;
            m_b0_r_ = top_.B0;
            m_b1_r_ = top_.B1;
        }

        if (r) {
            m_ab0_r_ = 0;
            m_ab1_r_ = 0;
        } else if (c1) {
            m_ab0_r_ = static_cast<int64_t>(sign_extend18(old_a0_r)) *
                       static_cast<int64_t>(sign_extend18(old_b0_r));
            m_ab1_r_ = static_cast<int64_t>(sign_extend18(old_a1_r)) *
                       static_cast<int64_t>(sign_extend18(old_b1_r));
        }

        if (r) {
            m_ab_r_ = 0;
        } else if (c2) {
            m_ab_r_ = asub ? (old_ab0_r + old_ab1_r) : (old_ab0_r - old_ab1_r);
        }

        top_.CLK0 = 0;
        top_.eval();
        top_.CLK0 = 1;
        top_.eval();
        ++cycle_;

        const uint64_t expected = static_cast<uint64_t>(m_ab_r_) & 0xFFFFFFFFFULL;
        const uint64_t actual = static_cast<uint64_t>(top_.SUM) & 0xFFFFFFFFFULL;
        if (expected != actual) {
            std::cerr << "mismatch at cycle " << cycle_ << ": dut=" << std::hex
                       << actual << " model=" << expected << std::dec << '\n';
            ++errors_;
        }

        trace_ << cycle_ << ',' << r << ',' << c0 << ',' << c1 << ',' << c2
               << ',' << asub << ',' << std::hex << std::setw(5)
               << std::setfill('0') << (top_.A0 & 0x3FFFFU) << ',' << std::setw(5)
               << (top_.A1 & 0x3FFFFU) << ',' << std::setw(5)
               << (top_.B0 & 0x3FFFFU) << ',' << std::setw(5)
               << (top_.B1 & 0x3FFFFU) << ',' << std::setw(9) << actual
               << std::dec << '\n';
    }

    Vmuladdsub top_;
    std::ofstream trace_;
    unsigned cycle_ = 0;
    unsigned errors_ = 0;

    uint32_t m_a0_r_ = 0, m_a1_r_ = 0, m_b0_r_ = 0, m_b1_r_ = 0;
    int64_t m_ab0_r_ = 0, m_ab1_r_ = 0;
    int64_t m_ab_r_ = 0;
};

}  // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Testbench testbench(trace_path(argc, argv));
    return testbench.run();
}
