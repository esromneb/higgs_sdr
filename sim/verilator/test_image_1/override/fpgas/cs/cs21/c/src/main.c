// test_image_1 cs21: sink for cs22's output. cs22out's ready comes from
// cs21's input DMA, so keep one scheduled at all times.
#include <stdint.h>
#include "dma.h"
#include "vmem.h"

VMEM_SECTION uint32_t sink_mem[1024];

int main(void) {
    while (1) {
        dma_block_get(VMEM_DMA_ADDRESS(sink_mem), 1024);
    }
}
