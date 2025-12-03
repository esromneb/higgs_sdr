#define VERILATE_TESTBENCH

#include <stdlib.h>
#include <iostream>
#include <vector>
// Include common routines

#include <assert.h>
#include <verilated.h>

#include <sys/stat.h>  // mkdir

#include <fstream>
#include <stdint.h>

// Include model header, generated from Verilating "top.v"
#include "Vtb_higgs_top.h"
#include "Vtb_higgs_top__Syms.h"

#include "cpp_utils.hpp"

#include <verilated_vcd_c.h>


#define RESET MIB_MASTER_RESET

#define GARBAGE_ADDR       (4094*NSLICES)
#define SCRATCH_ADDR       (4095*NSLICES)

#include "higgs_helper.hpp"



using namespace std;


typedef Vtb_higgs_top top_t;
typedef HiggsHelper<top_t> helper_t;

#include "piston_c_types.h"
#include "vmem_types.h"




VerilatedVcdC* tfp = NULL;
// Construct the Verilated model, from Vtop.h generated from Verilating "top.v"
top_t* top = new top_t; // Or use a const unique_ptr, or the VL_UNIQUE_PTR wrapper
// Current simulation time (64-bit unsigned)
uint64_t main_time = 0;
// Called by $time in Verilog
double sc_time_stamp () {
  return main_time; // Note does conversion to real, to match SystemC
}



int main(int argc, char** argv, char** env) {

  STANDARD_TB_START();
  // This helper is what I built to make this function easy
  // this handles reset.  You can register an arbitrary number of inputs
  // and outputs.
  // calling things like `inStreamAppend()` allows user to easily specify queue
  // input data which will be ticked over when tick is called
  HiggsHelper<top_t>* t = new HiggsHelper<top_t>(top,&main_time,tfp);

  srand(1);

  preReset(top);

  t->reset(40);

  postReset(top);

  // tb inputs starts here
  // user can tick the clock for a period
  // append data to input streams, and look at output streams
  // modify negClock() and posClock() above
  // you can also insert for check streams from those functins()

  // boot the processors

  int us = 400;
  // us = 30;

  t->tick(us*500);

  




  // cs30_node_t* cs30_node = top->tb_higgs_top->cs30_top->vex_machine_top_inst->q_engine_inst->piston_inst->UNODE_NAME;
  // cs20_node_t* cs20_node = top->tb_higgs_top->cs20_top->vex_machine_top_inst->q_engine_inst->piston_inst->UNODE_NAME;
  // cs10_node_t* cs10_node = top->tb_higgs_top->cs10_top->vex_machine_top_inst->q_engine_inst->piston_inst->UNODE_NAME;

  // dumping memory to disk
  // file_dump_T<cs30_node_t>(cs30_node, "cs30.out");
  // file_dump_T<cs20_node_t>(cs20_node, "cs20.out");
  // file_dump_T<cs10_node_t>(cs10_node, "cs10.out");

  // hexdump_T<cs20_node_t>(cs20_node,"CS20",0, 32);
  // hexdump_T<cs10_node_t>(cs10_node,"CS10",0, 1024*4);

  cout << "Ringbus got out" << endl;
  for(auto it = t->outs["ringbusout"]->data.begin(); it != t->outs["ringbusout"]->data.end(); it++) {
    cout << "0x" << HEX_STRING(*it) << endl;
  }

  // cout << "CS10 sent to dac:" << endl;
  // for(auto it = t->outs[1].data.begin(); it != t->outs[1].data.end(); it++) {
  //   cout << "0x" << HEX_STRING(*it) << endl;
  // }

  // dumping dma output
  // file_dump_vec(t->outs[1].data, "cs10_out.hex");
  file_dump_vec(t->outs["cs20out"]->data, "cs20_out.hex");

  const vector<uint32_t>& samples = t->outs["cs20out"]->data;
  const size_t expected_count = 32768;
  const size_t expected_period = 4096;
  const uint64_t expected_fnv = 0x6248f48c3198f9f5ULL;
  uint64_t fnv = 0xcbf29ce484222325ULL;
  bool pass = true;

  for (size_t i = 0; i < samples.size(); i++) {
    uint32_t word = samples[i];
    for (unsigned shift = 0; shift < 32; shift += 8) {
      fnv ^= (word >> shift) & 0xff;
      fnv *= 0x100000001b3ULL;
    }
    if (i >= expected_period && word != samples[i % expected_period]) {
      cerr << "FAIL: NCO period mismatch at sample " << i << endl;
      pass = false;
      break;
    }
  }

  if (samples.size() != expected_count) {
    cerr << "FAIL: NCO sample count " << samples.size()
         << " != " << expected_count << endl;
    pass = false;
  }
  if (fnv != expected_fnv) {
    cerr << "FAIL: NCO FNV-1a 0x" << hex << fnv
         << " != 0x" << expected_fnv << dec << endl;
    pass = false;
  }
  if (samples.size() == expected_count &&
      (samples[0] != 0x80000041 ||
       samples[1024] != 0xffe67fff ||
       samples[2048] != 0x7ffffffc ||
       samples[3072] != 0x00768000 ||
       samples[4095] != 0x8000fff3)) {
    cerr << "FAIL: NCO phase-quadrant anchor mismatch" << endl;
    pass = false;
  }

  if (pass) {
    cout << "All Tests Passed" << endl;
  }


  // Final model cleanup
  top->final();

  // Close trace if opened

  if (tfp) { tfp->close(); }

  // Destroy model
  delete top; top = NULL;
  //print_vector(output_vector);
  // Fin
  exit(pass ? 0 : 1);
}
