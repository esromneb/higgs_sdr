# Image kernel datapath — plan

Goal: a compile-time-selectable image-processing datapath for the Q-engine
(piston/VexRiscv) that slides an up-to-7x7 kernel over streamed 8-bit gray or
RGBX images. It sits alongside the existing 16I/16Q FFT datapath, and only
one is connected per build.

Status legend: `[ ]` todo, `[~]` in progress, `[x]` done.

## Tasks

1. `[x]` **Define kernel tasks** (grill-me): Sobel/Prewitt/Scharr, Gaussian
   3/5/7, box, sharpen/unsharp, Laplacian, emboss, erode/dilate, copy,
   custom. See NOTES §2.
2. `[x]` **Feature detection** (grill-me): threshold edge map, 3x3 NMS
   peaks, global min/max + location, 16x16 tile stats → ROI + bounding box.
   See NOTES §3.
3. `[x]` **Processing level / multipliers**: real u8×s8, dual accumulator
   (128 MACs → ~128 DSP48E2), 24-bit accumulators, per-lane mode, MIN/MAX
   comparators, post stage. See NOTES §4–5.
4. `[x]` **Fixed-point Python model**: `libs/datapath/image/img_model.py`
   (bit-exact to NOTES §5), synthetic image generator, stream
   encoder/decoder, self-tests, and RTL vector generator. See NOTES §8.
   `python3 libs/datapath/image/img_model.py selftest` passes.
5. `[x]` **Datapath RTL + compile**: `libs/datapath/image/rtl/img_datapath.v`
   with a standalone Verilator unit test against the model. Integrate it into
   `piston.v` behind `HIGGS_IMG_DATAPATH`, with the make/tcl selection
   `HIGGS_DATAPATH=img`. Then Verilator lint, and a Vivado synth + route of
   CS12 with the image datapath. Done: the unit test is bit-exact at 0/30/70 %
   stall, and CS12 routes at 125 MHz (WNS +0.647 ns, 134 DSP). See NOTES §9.
6. `[x]` **C library + instruction schedule**:
   `libs/riscv-baseband/c/inc/image_kernel.{h,c}`:
   * config/coefficient rows, line rings with halo, skew vregs;
   * the per-chunk LK8/LK9/SK1 schedule and an LK13/SK13 token fence;
   * multi-stage streaming (for PEAKS) and CPU feature reductions;
   * the cs22 stream protocol (jobs, errors, END). See NOTES §6–7.
7. `[x]` **Platform test** `sim/verilator/test_image_1`: cs22 firmware and a
   TB that injects 24 jobs, captures `cs22out` and compares it with the
   Python model. Verilator and XSIM both pass bit-exact with identical
   outputs. See NOTES §10 for results, cycles per job and issues found.

## Milestones / commits
* M1: docs + tasks 1–3. `[x]`
* M2: Python model + self-tests. `[x]`
* M3: RTL + unit test + piston integration + lint + Vivado results. `[x]`
* M4: C library. `[x]`
* M5: test_image_1 on Verilator and XSIM (plus a regression check of
  test_fft_lib_1 with the default datapath). `[x]`

## Risks / open items
* ~~CPU↔vector ordering~~: there is no hardware fence. An SK15 token fence
  hung (MVVK15 over-pushes when the vector unit idles, NOTES §1). The
  library now uses an LK13/SK13 token fence (NOTES §6.3).
* ~~Vivado may map 8x8 multipliers to LUTs~~: resolved, all 128 are in DSPs.
* Full-platform Verilator builds take ~15 min each; iterate with the unit
  test first.
