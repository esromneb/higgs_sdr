// test_image_1: image kernel datapath platform test (see README.md).
//
// Injects in.hex (img_model.py gen-stream) on cs22in. cs22 runs
// image_kernel.c's img_stream_loop() on the image datapath. The TB captures
// cs22out until the END header has been echoed (or it times out), writes
// got.hex and runs `img_model.py compare exp.hex got.hex`.
#define VERILATE_TESTBENCH

#include <stdlib.h>
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <assert.h>
#include <verilated.h>
#include <sys/stat.h>
#include "Vtb_higgs_top.h"
#include "Vtb_higgs_top__Syms.h"
#include "cpp_utils.hpp"
#include "feedback_bus_tb.hpp"
#include <verilated_vcd_c.h>
#include "higgs_helper.hpp"

typedef Vtb_higgs_top top_t;

VerilatedVcdC* tfp = NULL;
top_t* top = new top_t;
uint64_t main_time = 0;
double sc_time_stamp () {
    return main_time;
}

#define IMG_MODEL "../../../libs/datapath/image/img_model.py"
#define END_HEADER (0x1A6E00FFu)

static std::vector<uint32_t> read_hex(const char *path) {
    std::vector<uint32_t> v;
    std::ifstream f(path);
    std::string line;
    while (std::getline(f, line)) {
        if (line.size()) {
            v.push_back((uint32_t)std::stoul(line, nullptr, 16));
        }
    }
    return v;
}

static void write_hex(const char *path, const std::vector<uint32_t> &v) {
    std::ofstream f(path);
    char buf[16];
    for (auto w : v) {
        snprintf(buf, sizeof(buf), "%08x\n", w);
        f << buf;
    }
}

int main(int argc, char** argv, char** env) {

    STANDARD_TB_START();

    HiggsHelper<top_t>* t = new HiggsHelper<top_t>(top,&main_time,tfp);

    // +stalltrace: register the trace now, open it only if the run stalls
    VerilatedVcdC* stall_tfp = NULL;
    if (Verilated::commandArgsPlusMatch("stalltrace")[0]) {
        Verilated::traceEverOn(true);
        stall_tfp = new VerilatedVcdC;
        top->trace(stall_tfp, 99);
    }

    preReset(top);
    t->reset(40);
    postReset(top);

    const std::vector<uint32_t> in = read_hex("in.hex");
    const std::vector<uint32_t> exp = read_hex("exp.hex");
    assert(in.size() && exp.size() && "run `make stream` first");
    std::cout << "injecting " << in.size() << " words, expecting "
              << exp.size() << " words\n";

    t->inStreamAppend("cs22in", in);

    auto &got = t->outs["cs22out"]->data;
    const unsigned max_iters = 40000;   // x 500 cycles
    unsigned i;
    size_t last_size = 0;
    uint64_t done_cycle = 0;
    unsigned idle_iters = 0;
    // (output word index, cycle) of each job header, 500-cycle resolution
    std::vector<std::pair<size_t, uint64_t>> hdr_seen;
    for (i = 0; i < max_iters; i++) {
        t->tick(500);
        for (size_t k = last_size; k < got.size(); k++) {
            if ((got[k] >> 16) == (END_HEADER >> 16)) {
                hdr_seen.push_back({k, (uint64_t)(i + 1) * 500});
            }
        }
        // done once the END echo (3 words starting with END_HEADER) is in
        if (got.size() >= 3 && got.size() != last_size) {
            for (size_t k = last_size >= 3 ? last_size - 3 : 0; k + 3 <= got.size(); k++) {
                if (got[k] == END_HEADER) {
                    done_cycle = (uint64_t)(i + 1) * 500;
                }
            }
        }
        idle_iters = (got.size() == last_size) ? idle_iters + 1 : 0;
        last_size = got.size();
        if (done_cycle) {
            break;
        }
        const uint32_t pc = top->tb_higgs_top->cs22_top->vex_machine_top_inst->q_engine_inst->get_iBus_cmd_payload_pc();
        if (i % 1000 == 999) {
            std::cout << "PROGRESS: " << (i + 1) * 500 << " cycles, "
                      << got.size() << " words out, cs22 pc 0x" << HEX_STRING(pc) << "\n";
        }
        // no output for 500k cycles: the firmware is stuck, dump and give up
        if (idle_iters == 1000) {
            std::cout << "STALLED: cs22 pc 0x" << HEX_STRING(pc) << "\n";
            for (int k = 0; k < 8; k++) {
                t->tick(1);
                std::cout << "  pc 0x" << HEX_STRING(top->tb_higgs_top->cs22_top->vex_machine_top_inst->q_engine_inst->get_iBus_cmd_payload_pc()) << "\n";
            }
            const std::vector<uint32_t> fence = t->readVmem("cs22", 0, 16);
            std::cout << "  fence row:";
            for (auto w : fence) std::cout << " " << HEX_STRING(w);
            std::cout << "\n";
            if (stall_tfp) {
                stall_tfp->open("stall.vcd");
                t->tfp = stall_tfp;
                t->tick(20);
                t->tfp = NULL;
                stall_tfp->close();
                std::cout << "  wrote stall.vcd\n";
            }
            break;
        }
    }
    t->tick(2000);   // anything extra after END would be an error

    std::cout << "cs22out: " << got.size() << " words, END after ~"
              << done_cycle << " cycles\n";
    write_hex("got.hex", got);
    // cycles between consecutive job headers ~ cost of the earlier job
    for (size_t j = 0; j + 1 < hdr_seen.size(); j++) {
        std::cout << "JOBCYC: job " << j << " hdr 0x" << HEX_STRING(got[hdr_seen[j].first])
                  << " WxH 0x" << HEX_STRING(got[hdr_seen[j].first + 1])
                  << " out@" << hdr_seen[j].second << " cycles "
                  << (hdr_seen[j + 1].second - hdr_seen[j].second) << "\n";
    }

    const int rc = system("python3 " IMG_MODEL " compare exp.hex got.hex");

    top->final();
    if (tfp) { tfp->close(); }
    delete top; top = NULL;

    if (rc != 0 || !done_cycle) {
        std::cout << "FAILED\n";
        exit(1);
    }
    std::cout << "All Tests Passed\n";
    exit(0);
}
