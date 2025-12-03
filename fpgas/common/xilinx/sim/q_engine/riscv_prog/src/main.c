#include "csr_control.h"

#define TRANSFERS 64

int main(void) {
  unsigned int pending;

  CSR_WRITE(DMA_0_START_ADDR, 0);
  CSR_WRITE(DMA_0_LENGTH, TRANSFERS);
  CSR_WRITE(DMA_0_TIMER_VAL, 0xffffffff);
  CSR_WRITE_ZERO(DMA_0_PUSH_SCHEDULE);

  do {
    CSR_READ(mip, pending);
  } while ((pending & DMA_0_ENABLE_BIT) == 0);
  CSR_WRITE_ZERO(DMA_0_INTERRUPT_CLEAR);

  CSR_WRITE(DMA_1_START_ADDR, 0);
  CSR_WRITE(DMA_1_LENGTH, TRANSFERS);
  CSR_WRITE(DMA_1_TIMER_VAL, 0xffffffff);
  CSR_WRITE(DMA_1_LAST_RTL, 1);
  CSR_WRITE_ZERO(SLICER);
  CSR_WRITE_ZERO(DMA_1_PUSH_SCHEDULE);

  while (1) {
    asm volatile("");
  }
}
