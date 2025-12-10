# test_image_1 — image kernel datapath platform test

End-to-end test of the image datapath (`doc/kernel/`). It covers the RTL in
piston, the C library (`libs/riscv-baseband/c/inc/image_kernel.c`), the
stream protocol, and the fixed-point Python model
(`libs/datapath/image/img_model.py`).

## What it does
* `HIGGS_DATAPATH=img`: every Q-engine in the build gets `img_datapath`
  instead of the FFT datapath.
* `make stream` runs `img_model.py gen-stream in.hex exp.hex`, which
  produces 24 jobs plus END:
  * every op on gray 64x24 (COPY, GAUSS3/5/7, BOX3/5, SHARPEN, UNSHARP,
    LAPLACE, SOBEL, SOBEL_X, PREWITT, SCHARR, EMBOSS, ERODE3, DILATE3,
    EDGES, PEAKS);
  * GAUSS3, SOBEL, CHAN_GAUSS and EDGES on RGBX 32x16;
  * a tiny 40x2 job;
  * two error jobs (unknown op, width not a multiple of 16).
* Platform:
  * cs32 has no RISC-V (`CS32_NO_RISCV`), so the TB injects `cs22in`;
  * cs22 runs `override/fpgas/cs/cs22` (`img_init(); img_stream_loop();`);
  * cs21 runs a DMA sink (`override/fpgas/cs/cs21`) so that cs22out has a
    ready.
* `tb.cpp` captures `cs22out` until the END echo, writes `got.hex`, and runs
  `img_model.py compare exp.hex got.hex` (a job-by-job diff).

## Running
```
make test            # clean Verilator build + run (~4.5 min total)
./obj_dir/Vtb_higgs_top               # rerun without rebuilding
./obj_dir/Vtb_higgs_top +stalltrace   # on a hang, also dump stall.vcd
make xsim_run        # XSIM (source Vivado settings64.sh first; ~8 min run)
make xsim_compare    # XSIM vs model, and byte-for-byte vs Verilator got.hex
```
The cs22 firmware image is read at simulation start. After editing the C
library, `make -C override/fpgas/cs/cs22/c` and rerun the binary; no
re-verilate is needed.

If the firmware stops producing output for 500k cycles, the TB prints the
cs22 PC and the fence row, and fails. With `+stalltrace` it also writes a
20-cycle `stall.vcd` of the whole design, which is enough to see which
handshake is stuck.

## Results
All 24 jobs are bit-exact against the model on Verilator and XSIM, and the
two outputs are byte-identical. The Verilator run prints one `JOBCYC` line
per job (cycles between job headers, 500-cycle resolution). See `doc/kernel/NOTES.md` §10 for cycle
counts and the issues found on the way.
