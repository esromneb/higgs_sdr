// Minimal RISC-V "smoke test" program for the vex_machine_top integration
// harness (fpgas/common/xilinx/sim/vex_machine_top/).
//
// Purpose: exercise the *real* VexRiscv core, real bus/CSR decode logic,
// and the real GPIO peripheral inside q_engine -- as opposed to a
// NO_RISCV=1 idle/reset-only smoke test -- so that the Verilator vs. XSIM
// comparison in this harness is a genuine end-to-end integration check of
// "CPU fetch/execute -> CSR bus -> GPIO output", not just elaboration.
//
// This program deliberately avoids DMA, ring bus, NCO, vector memory
// (piston) and interrupt logic: those are out of scope for this smoke
// test (see README.md). It only:
//   1. Enables all 22 GPIO pins as outputs.
//   2. Repeatedly writes a rotating one-hot bit pattern to GPIO_WRITE,
//      with a short busy-wait delay between writes, forever.
//
// The rotating pattern gives the comparison harness a long, easily
// distinguishable, non-trivial GPIO waveform to diff between simulators.
#include "csr_control.h"

static void delay_loop(volatile unsigned int count) {
  while (count--) {
    asm volatile("");
  }
}

int main(void) {
  CSR_WRITE(GPIO_WRITE_EN, ALL_GPIO_PIN);

  unsigned int pattern = 0x1;
  while (1) {
    CSR_WRITE(GPIO_WRITE, pattern);
    delay_loop(24);

    pattern <<= 1;
    if (pattern & ~ALL_GPIO_PIN) {
      pattern = 0x1;
    }
  }

  return 0;
}
