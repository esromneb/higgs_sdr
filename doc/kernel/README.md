# Image kernel datapath

A real-valued (u8 pixel × s8 coefficient) sliding-window datapath for the
Higgs Q-engine. It replaces the 16I/16Q complex FFT datapath at compile time.
Images stream into a Q-engine. The VexRiscv keeps N lines in VMEM, the
vector unit feeds taps into the datapath (LK8 pixels, LK9 coefficients), and
the results are stored back (SK1) and streamed out.

* Design/spec: [NOTES.md](NOTES.md) (the bit-exact contract is §5)
* Plan/status: [PLAN.md](PLAN.md)

## Capabilities
* 3x3, 5x5 and 7x7 kernels on gray (1 px/word) or RGBX (1 px/word, 3
  channels) at 16 pixels per LK8/LK9 beat.
* Ops: copy, Gaussian 3/5/7, box 3/5, sharpen, unsharp, Laplacian,
  Sobel (|Gx|+|Gy| in one pass), Sobel-X, Prewitt, Scharr, emboss,
  erode/dilate, custom s8 kernels, and a per-channel-coefficient demo
  (CHAN_GAUSS).
* Feature detection: thresholded edges, 3x3 non-maximum suppression (peaks),
  global min/max with location, 16x16 tile edge counts → ROI bounding box.
* Borders: ZERO or REPLICATE, with same-size output.

## Layout (planned; updated as milestones land)
| path | what |
|------|------|
| `libs/datapath/image/img_model.py` | fixed-point Python model (done: `selftest`, `gen-unit`, `gen-stream`, `compare`) |
| `libs/datapath/image/rtl/img_datapath.v` | datapath RTL (done; unit test in `libs/datapath/image/sim`, `make`) |
| `libs/riscv-baseband/c/inc/image_kernel.{h,c}` | C library (done: `img_run_stages`, `img_stream_loop`) |
| `sim/verilator/test_image_1/` | platform test (Verilator + XSIM) |

## Selecting the datapath (compile time)
Set `HIGGS_DATAPATH=img` in a test Makefile (Verilator/XSIM) or in the
environment for Vivado (`fpgas/cs/cs12/build/vivado/README.md`). This defines `HIGGS_IMG_DATAPATH`, which
reconnects piston's k8/k9/k14/k1 ports to `img_datapath`. The default
(unset) is the original FFT datapath, unchanged.
