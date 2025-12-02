#include "Vscalar_memory_xilinx.h"
#include "verilated.h"

#include <array>
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

uint32_t masked_write(uint32_t old_value, uint32_t new_value, uint8_t mask) {
    for (unsigned byte = 0; byte < 4; ++byte) {
        if ((mask >> byte) & 1U) {
            const uint32_t lane_mask = 0xffU << (byte * 8);
            old_value = (old_value & ~lane_mask) | (new_value & lane_mask);
        }
    }
    return old_value;
}

std::string trace_path(int argc, char** argv) {
    constexpr char prefix[] = "+TRACE=";
    for (int index = 1; index < argc; ++index) {
        const std::string argument(argv[index]);
        if (argument.compare(0, sizeof(prefix) - 1, prefix) == 0)
            return argument.substr(sizeof(prefix) - 1);
    }
    return "scalar_memory_xilinx.csv";
}

class Testbench {
  public:
    Testbench(const std::string& path, int argc, char** argv) : trace_(path) {
        Verilated::commandArgs(argc, argv);
        top_.clk = 0;
        top_.srst = 0;
        top_.t0_valid = 0;
        top_.t0_we = 0;
        top_.t0_mask = 0;
        top_.t0_addr = 0;
        top_.t0_data = 0;
        top_.i0_ready = 1;
        top_.t1_valid = 0;
        top_.t1_we = 0;
        top_.t1_mask = 0;
        top_.t1_addr = 0;
        top_.t1_data = 0;
        top_.i1_ready = 1;
        top_.eval();
        trace_ << "cycle,t0_valid,t0_we,t0_addr,i0_valid,i0_data,"
                  "t1_valid,t1_we,t1_addr,i1_valid,i1_data\n";
    }

    int run() {
        for (uint8_t index = 0; index < 4; ++index) {
            transact(index, true, true, 0xf, 0x10203040U + index,
                     static_cast<uint8_t>(index + 4), true, true, 0xf,
                     0x50607080U + index);
        }

        transact(2, true, true, 0x5, 0xaabbccddU, 5, true, true, 0xa,
                 0x11223344U);
        transact(2, true, false, 0, 0, 5, true, false, 0, 0);
        transact(0, false, false, 0, 0, 0, false, false, 0, 0);

        uint32_t random_state = 1;
        for (unsigned index = 0; index < 400; ++index) {
            random_state = next_random(random_state);
            uint8_t addr0 = random_state & 0x7;
            bool we0 = (random_state >> 3) & 1U;
            uint8_t mask0 = (random_state >> 4) & 0xf;
            uint32_t data0 = random_state;
            random_state = next_random(random_state);
            uint8_t addr1 = random_state & 0x7;
            bool we1 = (random_state >> 3) & 1U;
            uint8_t mask1 = (random_state >> 4) & 0xf;
            uint32_t data1 = random_state;
            if (addr0 == addr1 && (we0 || we1))
                addr1 ^= 1;
            transact(addr0, true, we0, mask0, data0, addr1, true, we1, mask1,
                     data1);
        }

        return errors_ == 0 ? 0 : 1;
    }

  private:
    void transact(uint8_t addr0, bool valid0, bool write0, uint8_t mask0,
                  uint32_t data0, uint8_t addr1, bool valid1, bool write1,
                  uint8_t mask1, uint32_t data1) {
        top_.clk = 0;
        top_.eval();
        top_.t0_addr = static_cast<uint32_t>(addr0) << 2;
        top_.t0_valid = valid0;
        top_.t0_we = write0;
        top_.t0_mask = mask0;
        top_.t0_data = data0;
        top_.t1_addr = static_cast<uint32_t>(addr1) << 2;
        top_.t1_valid = valid1;
        top_.t1_we = write1;
        top_.t1_mask = mask1;
        top_.t1_data = data1;
        top_.clk = 1;
        top_.eval();
        ++cycle_;

        if (valid0 && !write0 && (!top_.i0_valid || top_.i0_data != expected_[addr0]))
            report_error(0, top_.i0_data, expected_[addr0]);
        if (valid1 && !write1 && (!top_.i1_valid || top_.i1_data != expected_[addr1]))
            report_error(1, top_.i1_data, expected_[addr1]);

        trace_ << cycle_ << ',' << valid0 << ',' << write0 << ',' << std::hex
               << std::setw(8) << std::setfill('0') << top_.t0_addr << ','
               << std::dec << static_cast<unsigned>(top_.i0_valid) << ','
               << std::hex << std::setw(8) << top_.i0_data << ',' << std::dec
               << valid1 << ',' << write1 << ',' << std::hex << std::setw(8)
               << top_.t1_addr << ',' << std::dec
               << static_cast<unsigned>(top_.i1_valid) << ',' << std::hex
               << std::setw(8) << top_.i1_data << std::dec << '\n';

        if (valid0 && write0)
            expected_[addr0] = masked_write(expected_[addr0], data0, mask0);
        if (valid1 && write1)
            expected_[addr1] = masked_write(expected_[addr1], data1, mask1);
    }

    void report_error(unsigned port, uint32_t actual, uint32_t expected) {
        std::cerr << "port " << port << " mismatch at cycle " << cycle_
                  << ": got " << std::hex << actual << " expected " << expected
                  << std::dec << '\n';
        ++errors_;
    }

    Vscalar_memory_xilinx top_;
    std::array<uint32_t, 8> expected_{};
    std::ofstream trace_;
    unsigned cycle_ = 0;
    unsigned errors_ = 0;
};

}  // namespace

int main(int argc, char** argv) {
    Testbench testbench(trace_path(argc, argv), argc, argv);
    return testbench.run();
}
