// test_image_1 cs22: image kernel stream server (doc/kernel/NOTES.md §6/§7).
// Reads jobs from cs22in, streams results to cs22out until the END job.
#include "image_kernel.h"

int main(void) {
    img_init();
    img_stream_loop();
    while (1) {
    }
}
