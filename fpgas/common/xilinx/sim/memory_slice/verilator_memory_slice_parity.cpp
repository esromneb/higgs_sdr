#include "Vmemory_slice_dual_top.h"
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

std::string trace_path(int argc, char** argv) {
    constexpr char prefix[] = "+TRACE=";
    for (int index = 1; index < argc; ++index) {
        const std::string argument(argv[index]);
        if (argument.compare(0, sizeof(prefix) - 1, prefix) == 0)
            return argument.substr(sizeof(prefix) - 1);
    }
    return "memory_slice_parity.csv";
}

class Testbench {
  public:
    explicit Testbench(const std::string& path) : trace_(path) {
        top_.clk = 0;
        top_.reset_n = 0;
        top_.t0_valid = 0;
        top_.t0_we = 0;
        top_.t0_addr = 0;
        top_.t0_data = 0;
        top_.i0_ready = 1;
        top_.t1_valid = 0;
        top_.t1_we = 0;
        top_.t1_addr = 0;
        top_.t1_data = 0;
        top_.i1_ready = 1;
        top_.eval();
        trace_ << "cycle,t0_valid,t0_we,t0_addr,i0_ready,xil_t0_ready,xil_i0_addr,"
                  "xil_i0_data,xil_i0_valid,t1_valid,t1_we,t1_addr,i1_ready,"
                  "xil_t1_ready,xil_i1_addr,xil_i1_data,xil_i1_valid\n";
    }

    int run() {
        // Reset assertion/deassertion; `reset_n` is not consumed by either
        // implementation.
        top_.reset_n = 0;
        drive(0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
        drive(0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
        top_.reset_n = 1;

        // Initialize every location with disjoint, non-colliding writes.
        for (uint8_t index = 0; index < 8; ++index) {
            drive(index, 1, 1, 0x10000000U + index, 1,
                  static_cast<uint8_t>(index + 8), 1, 1, 0x20000000U + index, 1);
        }

        // Directed port-0 backpressure.
        drive(3, 1, 0, 0, 0, 0, 0, 0, 0, 1);
        drive(3, 0, 0, 0, 0, 0, 0, 0, 0, 1);
        drive(3, 0, 0, 0, 0, 0, 0, 0, 0, 1);
        drive(3, 0, 0, 0, 1, 0, 0, 0, 0, 1);
        drive(0, 0, 0, 0, 1, 0, 0, 0, 0, 1);

        // Directed port-1 backpressure and its extra pipeline stage.
        drive(0, 0, 0, 0, 1, 9, 1, 0, 0, 0);
        drive(0, 0, 0, 0, 1, 9, 0, 0, 0, 0);
        drive(0, 0, 0, 0, 1, 9, 0, 0, 0, 1);
        drive(0, 0, 0, 0, 1, 0, 0, 0, 0, 1);

        // Same-address concurrent reads on both ports: defined and safe.
        drive(5, 1, 0, 0, 1, 5, 1, 0, 0, 1);
        drive(0, 0, 0, 0, 1, 0, 0, 0, 0, 1);

        // Idle cycle.
        drive(0, 0, 0, 0, 1, 0, 0, 0, 0, 1);

        // Deterministic fuzzing; exclude same-address cross-port writes.
        uint32_t random_state = 1;
        for (unsigned index = 0; index < 500; ++index) {
            random_state = next_random(random_state);
            uint8_t addr0 = random_state & 0xf;
            bool valid0 = (random_state >> 4) & 1U;
            bool we0 = (random_state >> 5) & 1U;
            bool ready0 = (random_state >> 6) & 1U;
            uint32_t data0 = random_state;
            random_state = next_random(random_state);
            uint8_t addr1 = random_state & 0xf;
            bool valid1 = (random_state >> 4) & 1U;
            bool we1 = (random_state >> 5) & 1U;
            bool ready1 = (random_state >> 6) & 1U;
            uint32_t data1 = random_state;
            if (addr0 == addr1 && (we0 || we1))
                addr1 ^= 1;
            drive(addr0, valid0, we0, data0, ready0, addr1, valid1, we1, data1,
                  ready1);
        }

        return errors_ == 0 ? 0 : 1;
    }

  private:
    void drive(uint8_t addr0, bool valid0, bool we0, uint32_t data0,
               bool ready0, uint8_t addr1, bool valid1, bool we1,
               uint32_t data1, bool ready1) {
        top_.t0_addr = addr0;
        top_.t0_valid = valid0;
        top_.t0_we = we0;
        top_.t0_data = data0;
        top_.i0_ready = ready0;
        top_.t1_addr = addr1;
        top_.t1_valid = valid1;
        top_.t1_we = we1;
        top_.t1_data = data1;
        top_.i1_ready = ready1;

        top_.clk = 0;
        top_.eval();
        top_.clk = 1;
        top_.eval();
        ++cycle_;

        check_port("port0", top_.ref_t0_ready, top_.xil_t0_ready,
                   top_.ref_i0_addr, top_.xil_i0_addr, top_.ref_i0_data,
                   top_.xil_i0_data, top_.ref_i0_valid, top_.xil_i0_valid);
        check_port("port1", top_.ref_t1_ready, top_.xil_t1_ready,
                   top_.ref_i1_addr, top_.xil_i1_addr, top_.ref_i1_data,
                   top_.xil_i1_data, top_.ref_i1_valid, top_.xil_i1_valid);

        trace_ << cycle_ << ',' << valid0 << ',' << we0 << ',' << std::hex
               << std::setw(3) << std::setfill('0')
               << static_cast<unsigned>(addr0) << ',' << std::dec << ready0
               << ',' << static_cast<unsigned>(top_.xil_t0_ready) << ','
               << std::hex << std::setw(3) << std::setfill('0')
               << top_.xil_i0_addr << ',' << std::setw(8) << std::setfill('0')
               << top_.xil_i0_data
               << ',' << std::dec << static_cast<unsigned>(top_.xil_i0_valid)
               << ',' << valid1 << ',' << we1 << ',' << std::hex
               << std::setw(3) << std::setfill('0')
               << static_cast<unsigned>(addr1) << ',' << std::dec << ready1
               << ',' << static_cast<unsigned>(top_.xil_t1_ready) << ','
               << std::hex << std::setw(3) << std::setfill('0')
               << top_.xil_i1_addr << ',' << std::setw(8) << std::setfill('0')
               << top_.xil_i1_data
               << ',' << std::dec << static_cast<unsigned>(top_.xil_i1_valid)
               << '\n';
    }

    void check_port(const char* name, uint8_t ref_ready, uint8_t xil_ready,
                     uint16_t ref_addr, uint16_t xil_addr, uint32_t ref_data,
                     uint32_t xil_data, uint8_t ref_valid, uint8_t xil_valid) {
        // Data is a don't-care unless the port is actually valid; see
        // tb_memory_slice_parity.sv for why uninitialized data may still
        // differ (X vs. 0) while invalid.
        const bool data_mismatch = xil_valid && (ref_data != xil_data);
        if (ref_ready != xil_ready || ref_addr != xil_addr ||
            ref_valid != xil_valid || data_mismatch) {
            std::cerr << name << " mismatch at cycle " << cycle_ << ": ref="
                      << static_cast<unsigned>(ref_ready) << '/' << std::hex
                      << ref_addr << '/' << ref_data << std::dec << '/'
                      << static_cast<unsigned>(ref_valid) << " xil="
                      << static_cast<unsigned>(xil_ready) << '/' << std::hex
                      << xil_addr << '/' << xil_data << std::dec << '/'
                      << static_cast<unsigned>(xil_valid) << '\n';
            ++errors_;
        }
    }

    Vmemory_slice_dual_top top_;
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
