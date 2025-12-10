// Standalone Verilator test for img_datapath against img_model.py vectors.
// usage: Vimg_datapath VECTORS [seed] [stall_pct]
#include "Vimg_datapath.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <deque>

struct Item {
    char kind;                 // 'C' config, 'B' beat
    uint32_t w[32];            // C: w0,w1 ; B: k8[16], k9[16]
};

static uint32_t rng_state = 1;
static uint32_t rnd() {
    rng_state = rng_state * 1664525u + 1013904223u;
    return rng_state >> 8;
}

static void set_row(WData *dst, const uint32_t *src) {
    for (int i = 0; i < 16; i++) dst[i] = src[i];
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s VECTORS [seed] [stall_pct]\n", argv[0]); return 2; }
    rng_state = argc > 2 ? strtoul(argv[2], 0, 0) : 1;
    int stall = argc > 3 ? atoi(argv[3]) : 30;
    Verilated::commandArgs(argc, argv);

    std::vector<Item> items;
    std::deque<std::vector<uint32_t>> expect;
    std::ifstream f(argv[1]);
    std::string line;
    while (std::getline(f, line)) {
        std::istringstream ss(line);
        std::string k;
        ss >> k;
        if (k.empty()) continue;
        std::vector<uint32_t> v;
        std::string h;
        while (ss >> h) v.push_back((uint32_t)strtoul(h.c_str(), 0, 16));
        if (k == "E") { expect.push_back(v); continue; }
        Item it;
        memset(&it, 0, sizeof(it));
        it.kind = k[0];
        for (size_t i = 0; i < v.size() && i < 32; i++) it.w[i] = v[i];
        items.push_back(it);
    }
    const size_t n_expect = expect.size();

    Vimg_datapath *top = new Vimg_datapath;
    top->clk = 0;
    top->reset_n = 0;
    top->t_k8_req = top->t_k9_req = top->t_k14_req = 0;
    top->i_k1_ack = 0;
    for (int i = 0; i < 4; i++) { top->clk = !top->clk; top->eval(); }
    top->reset_n = 1;

    size_t i8 = 0, i9 = 0;     // next item index for each port
    bool r8 = false, r9 = false, r14 = false;
    size_t got = 0;
    int errors = 0;
    uint64_t cyc = 0, beats = 0;
    const uint64_t max_cyc = 50ull * items.size() + 10000;

    auto skip_to_beat = [&](size_t idx) { return idx; };
    (void)skip_to_beat;

    while ((got < n_expect) && cyc < max_cyc && errors < 10) {
        // config barrier: a C item is applied once both ports reached it
        r14 = false;
        if (i8 == i9 && i8 < items.size() && items[i8].kind == 'C') {
            uint32_t row[16] = {0};
            row[0] = items[i8].w[0];
            row[1] = items[i8].w[1];
            set_row(top->t_k14_dat, row);
            r14 = true;
        }
        // drive k8 / k9 (hold req once raised)
        if (!r8 && i8 < items.size() && items[i8].kind == 'B' && (int)(rnd() % 100) >= stall) r8 = true;
        if (!r9 && i9 < items.size() && items[i9].kind == 'B' && (int)(rnd() % 100) >= stall) r9 = true;
        if (r8) set_row(top->t_k8_dat, items[i8].w);
        else for (int i = 0; i < 16; i++) top->t_k8_dat[i] = rnd();
        if (r9) set_row(top->t_k9_dat, items[i9].w + 16);
        else for (int i = 0; i < 16; i++) top->t_k9_dat[i] = rnd();
        top->t_k8_req = r8;
        top->t_k9_req = r9;
        top->t_k14_req = r14;
        top->i_k1_ack = (int)(rnd() % 100) >= stall;

        top->clk = 0;
        top->eval();
        bool f8 = top->t_k8_req && top->t_k8_ack;
        bool f9 = top->t_k9_req && top->t_k9_ack;
        bool f14 = top->t_k14_req && top->t_k14_ack;
        bool fo = top->i_k1_req && top->i_k1_ack;
        if (f8 != f9) { printf("ERROR: k8/k9 join violated at cycle %lu\n", (unsigned long)cyc); errors++; }
        if (fo) {
            const std::vector<uint32_t> &e = expect.front();
            bool ok = true;
            for (int i = 0; i < 16; i++) if (top->i_k1_dat[i] != e[i]) ok = false;
            if (!ok) {
                errors++;
                printf("ERROR: row %zu mismatch at cycle %lu\n  exp:", got, (unsigned long)cyc);
                for (int i = 0; i < 16; i++) printf(" %08x", e[i]);
                printf("\n  got:");
                for (int i = 0; i < 16; i++) printf(" %08x", top->i_k1_dat[i]);
                printf("\n");
            }
            expect.pop_front();
            got++;
        }
        top->clk = 1;
        top->eval();
        cyc++;
        if (f14) { i8++; i9++; }
        if (f8) { i8++; r8 = false; beats++; }
        if (f9) { i9++; r9 = false; }
    }
    // no extra output may appear
    for (int k = 0; k < 20 && !errors; k++) {
        top->i_k1_ack = 1; top->t_k8_req = top->t_k9_req = top->t_k14_req = 0;
        top->clk = 0; top->eval();
        if (top->i_k1_req) { printf("ERROR: unexpected extra output row\n"); errors++; }
        top->clk = 1; top->eval();
    }
    if (got < n_expect && !errors) { printf("ERROR: timeout, got %zu of %zu rows\n", got, n_expect); errors++; }
    printf("img_datapath unit test: %lu beats, %zu rows, %lu cycles, stall %d%%: %s\n",
           (unsigned long)beats, got, (unsigned long)cyc, stall, errors ? "FAIL" : "PASS");
    top->final();
    delete top;
    return errors ? 1 : 0;
}
