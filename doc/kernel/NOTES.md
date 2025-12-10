# Image kernel datapath — design notes

This file is the engineering log and the specification. The Python model
(`libs/datapath/image/img_model.py`), the RTL (`libs/datapath/image/rtl/`)
and the C library (`libs/riscv-baseband/c/inc/image_kernel.{h,c}`) all
implement what is written here. If they disagree, this file wins; then fix
the code or update this file in the same commit.

## 0. Context and base branch

* The target is Xilinx (xczu7ev, Vivado 2025.2). `imgmaster` was rebased onto
  `xilmaster` (from `../xil1_higgs`), so the image work carries the full
  Xilinx port: the `HIGGS_FPGA_XILINX` flow, the XSIM parity harness and the
  CS12 Vivado build. The pre-rebase tip is kept as the branch
  `imgmaster-pre-rebase`.
* Baseline evidence: `sim/verilator/test_fft_lib_1` passed before the work
  started (ring output `0xdeadbeef,0x34,0x6,0x2,0x1,0x0,0x0,0xf`, ~14 min
  build+run).
* Both verification flows are required: Verilator and XSIM.

## 1. How the existing datapath is built (study)

* A Q-engine = VexRiscv + *piston* (vector unit + VMEM + datapath).
  `libs/q-engine/piston/hdl/piston.v` is produced by the reqack/fhyper
  generator (`piston/bin/gen.js`, `piston/lib/piston.js`). The datapath graph
  itself comes from `libs/datapath/lib/datapath.js`
  (`funnel → cmul(muladdsub) → radix4 → bs → round_sat → defunnel`).
* Datapath interface (`dpTargets`/`dpInitiators` in `piston.js`):
  * `k8`, `k9`: 512-bit rows loaded from VMEM by `LK8`/`LK9` instructions.
  * `k14`: 512-bit config row loaded by `LK14` (`FLUSH_CONFIG_WORD`).
  * `k1`: 512-bit result row consumed by `SK1`.
  * All four are valid/ready (req/ack) elastic channels. In `piston.v` they
    are `dat38`/`dat39`/`dat40` in and `dat42_nxt` out. The handshakes are
    `req/ack38_0`, `39_0`, `40_0` and `req/ack42` in `piston_ctrl`.
* The existing datapath funnels each 512-bit row into 4 beats of 128 bits
  (8 complex 16I/16Q samples per beat), so it is 16-bit complex only.
* VMEM: 16 banks (slices) × 32 bit, 4096 rows (`VMEM_DEPTH`) = 256 KiB.
  VMEM row r, bank b is DMA word `16*r+b` and CPU address
  `0x40000 + 4*(16*r+b)`.
* Vector registers: 16 per slice, 16 bits: `{perm[15:12], baddr[11:0]}`.
  * Bank `b` reads/writes address `vreg[b].baddr`.
  * The load permutation gives output slice `s` = bank `(s + perm[s]) mod 16`
    (`perm_full_data_dat_2_1.v`).
  * `LKn`/`SKn` use the *pre-op* value of `s1` (`i0_data` is source 1), so
    `ADD_LK9(V8,V8,V9)` loads row `V8` then increments `V8`.
  * `MVXV_KNOP(v,x)` broadcasts the low 16 bits of `x` to all slices.
  * `VNOP_LK15(v); MVK15V_KNOP(d,0)` loads a VMEM row into a vreg.
  * `ADD_SK15(d,a,b)` stores `vreg b` (zero-extended) into row `vreg a`.
* The generator does **not** reproduce the committed `piston.v` any more
  (reqack drift: regenerating shrinks it by ~4k lines). The Xilinx port
  already hand-edits `piston.v` (the `vmem_dat_6_5_1_1` ifdef), so the image
  integration also uses small, guarded hand edits. It does not regenerate.

## 2. Task 1 — kernel operations (grill Q1–Q3, Q5)

All operations are 8-bit per channel, same-size output, and use the
tap-accumulate engine below. Coefficients are signed 8-bit (`s8`).

| id | name | taps | kernel (cA; cB) | comb | shift | round | offset |
|----|------|------|-----------------|------|-------|-------|--------|
| 0 | COPY | 1x1 | `1` | A | 0 | – | 0 |
| 1 | GAUSS3 | 3x3 | `[1 2 1]ᵀ[1 2 1]` (sum 16) | A | 4 | y | 0 |
| 2 | GAUSS5 | 5x5 | `[1 4 6 4 1]ᵀ[1 4 6 4 1]` (sum 256) | A | 8 | y | 0 |
| 3 | GAUSS7 | 7x7 | `[1 3 7 10 7 3 1]ᵀ[…]` (sum 1024) | A | 10 | y | 0 |
| 4 | BOX3 | 3x3 | all `114` (≈1024/9) | A | 10 | y | 0 |
| 5 | BOX5 | 5x5 | all `82` (≈2048/25) | A | 11 | y | 0 |
| 6 | SHARPEN | 3x3 | `[0 -1 0; -1 5 -1; 0 -1 0]` | A | 0 | – | 0 |
| 7 | UNSHARP | 3x3 | `32δ − gauss3` = `[-1 -2 -1; -2 28 -2; -1 -2 -1]` | A | 4 | y | 0 |
| 8 | LAPLACE | 3x3 | `[0 1 0; 1 -4 1; 0 1 0]` | \|A\| | 0 | – | 0 |
| 9 | SOBEL | 3x3 | Gx `[-1 0 1; -2 0 2; -1 0 1]`; Gy = Gxᵀ | \|A\|+\|B\| | 2 | y | 0 |
| 10 | SOBEL_X | 3x3 | Gx | \|A\| | 2 | y | 0 |
| 11 | PREWITT | 3x3 | `[-1 0 1]×3`; transpose | \|A\|+\|B\| | 2 | y | 0 |
| 12 | SCHARR | 3x3 | `[-3 0 3; -10 0 10; -3 0 3]`; transpose | \|A\|+\|B\| | 4 | y | 0 |
| 13 | EMBOSS | 3x3 | `[-2 -1 0; -1 1 1; 0 1 2]` | A | 0 | – | +128 |
| 14 | ERODE3 | 3x3 | MIN over mask (all 1) | – | – | – | – |
| 15 | DILATE3 | 3x3 | MAX over mask (all 1) | – | – | – | – |
| 16 | CUSTOM | ≤7x7 | user s8 kernel(s), user post settings | any | any | any | any |

The feature operations (ids 32+) are in §3.

Notes:
* Kernel sizes 1, 3, 5 and 7 are supported (max 7x7 = 49 taps). The
  accumulator has headroom for 9x9 (see §4).
* A 7x7 binomial (`[1 6 15 20 15 6 1]`) overflows s8 (20·20=400), so GAUSS7
  uses `[1 3 7 10 7 3 1]` (sum 32, 2-D sum 1024, max coefficient 100).
* Box filters cannot divide by N², so they use `c = round(2^s/N²)` with a
  small gain error (+0.2 % for BOX3, +0.1 % for BOX5), saturated.
* Median was explicitly rejected (Q1); it needs sorting, not MACs.
* Other operations this engine also covers (suggestions): motion blur
  (1xN/Nx1 box), directional/compass edges (Kirsch/Robinson as CUSTOM),
  high-pass/high-boost, morphological gradient (DILATE − ERODE, two passes
  plus a CPU subtract), opening/closing (ERODE→DILATE chains), thresholding
  and binary masks, and the local-peak detector.

### Borders (Q5)
* Same-size output. There are two modes, ZERO and REPLICATE.
* Horizontal: each line in VMEM has a pad row (16 words) on the left and the
  right. After the line lands, the C library fills the `R = (N-1)/2` halo
  words next to the line with 0 (ZERO) or the edge pixel (REPLICATE).
* Vertical: the row index `y+dy` is clamped to `[0,H-1]` (REPLICATE) or
  redirected to an all-zero line (ZERO).
* The Python model implements exactly this (`np.pad` with `constant` or
  `edge`).

### Pixel formats (Q2)
* GRAY: one pixel per 32-bit word, value in byte 0 (lane 0). Lanes 1–3 are
  zero on input and forced to zero on output. A 512-bit row = 16 pixels.
  (Future: pack 4 vertical strips per word for 4× gray throughput.)
* RGBX: one pixel per word, R=byte0, G=byte1, B=byte2, X=byte3. X is forced
  to 0 on output. Every channel is filtered independently with the same
  kernel.

## 3. Task 2 — feature detection (grill Q6)

Built on top of the kernel ops, so there is no extra datapath hardware:

| id | name | pipeline | output image |
|----|------|----------|--------------|
| 32 | EDGES | SOBEL + threshold (`thr_en`) | 255 where mag ≥ T else 0 |
| 33 | PEAKS | SOBEL → 3x3 NMS/peak stage | mag where mag is the 3x3 max and ≥ T, else 0 |

Where:
* **Threshold** is a datapath post-op: `out = (v >= T) ? 255 : 0`.
* **NMS / local peaks** is a second streaming stage. It runs MAX over a 3x3
  window with the `CENTER` tap flag capturing the centre pixel, then
  `out = (ctr == max && ctr >= T) ? ctr : 0`. Plateaus keep all equal
  maxima. This is isotropic 3x3 peak suppression, not Canny's directional
  NMS.
* **Global statistics** are computed by the CPU from each finished output
  line while it is still in VMEM, for every op. The value used is
  `v = max(R,G,B)` (lane 0 for gray):
  * max value and the (x,y) of its first occurrence in raster order;
  * min value and the (x,y) of its first occurrence;
  * the count of non-zero pixels and the sum of `v`.
* **Interesting regions (ROI)**: the image is split into 16x16 tiles
  (ceil at the edges). A tile's score is its count of non-zero output pixels
  (edge pixels for EDGES/PEAKS). A tile is a ROI when `score >= roi_thr`.
  The CPU reports the ROI tile count and the pixel bounding box of all ROI
  tiles.
* Deferred to future work: Harris corners (needs products of gradients, 3
  passes), connected components, per-ROI centroid.
* Refinement vs the grill answer: the "datapath per-column running max"
  idea (a MAX op over {line, running-max row}) works with the existing ops,
  but it cannot give the (x,y) location cheaply. v1 therefore does the
  min/max reduction on the CPU, which already has each line in VMEM. The
  running-max trick is noted as an optimisation.

## 4. Task 3 — processing level and multipliers (grill Q3, Q4)

* **Real, not complex:** image data is u8 and coefficients are s8. The
  existing 16I/16Q complex `muladdsub` datapath is replaced (at compile time)
  by a real u8×s8 engine.
* **Width:** a whole 512-bit row per beat is 64 byte-lanes (16 words × 4
  lanes). There is no funnel: one LK8/LK9 pair per clock.
* **Dual accumulator:** each lane has accumulator A (`p·cA`) and B
  (`p·cB`), so Sobel/Prewitt/Scharr get Gx and Gy in one pass. That is
  2 × 64 = **128 u8×s8 multipliers**, about 128 DSP48E2 (≈7.4 % of the
  xczu7ev's 1,728 DSPs). Future work: pack two u8×s8 products per DSP48E2
  (INT8 packing) to halve this.
* **Accumulator width:** |p·c| ≤ 255·128 = 32,640. 49 taps ≤ 1.6 M < 2²³,
  and 81 taps (9x9) ≤ 2.65 M, so the accumulators are **24-bit signed**.
* **Per-lane mode:** coefficients differ per channel (`cA` from bytes 0..2
  of the coefficient word, lane 3 = 0, B unused). Useful for per-channel
  weighting and colour-specific kernels.
* **MIN/MAX mode** (erode/dilate/NMS) uses 64 8-bit comparators per op; no
  multipliers.
* **Post stage** per lane:
  combine → round/shift → offset → saturate u8 → threshold/peak → lane mask.

## 5. Datapath specification (bit-exact contract)

### 5.1 Coefficient row (k9, LK9)
The coefficient row has 16 words, one per slice. v1 always uses the same
word in all 16 slices.
```
word[7:0]   cA  (s8)       per-lane mode: cA for lane 0 (R/gray)
word[15:8]  cB  (s8)       per-lane mode: cA for lane 1 (G)
word[23:16] reserved (0)   per-lane mode: cA for lane 2 (B)
word[24]    FIRST   clear accumulators (load instead of add)
word[25]    LAST    emit the post-processed row on k1 after this tap
word[26]    CENTER  capture this tap's pixel as the centre value
word[31:27] reserved (0)
```
In normal mode `cA` and `cB` are broadcast to the 4 lanes of the word.
Per-lane mode: lane 3 has cA=0, and cB=0 for all lanes.

### 5.2 Config row (k14, LK14) — only word 0 and word 1 (slice 0, 1) are used
```
w0[1:0]   op       0=MAC 1=MIN 2=MAX
w0[3:2]   comb     0=A 1=|A| 2=|A|+|B| 3=max(|A|,|B|)      (MAC only)
w0[7:4]   shift    0..15 arithmetic right shift            (MAC only)
w0[8]     round    add 1<<(shift-1) before the shift (if shift>0)
w0[9]     thr_en   out = (v >= thr) ? 255 : 0
w0[10]    peak_en  out = (ctr == v && ctr >= thr) ? ctr : 0 (MIN/MAX)
w0[11]    perlane  per-lane coefficient mode
w0[15:12] lane_mask  output lane enable (gray 0x1, RGBX 0x7)
w0[23:16] thr      u8 threshold
w1[15:0]  offset   s16 added after the shift              (MAC only)
```
`peak_en` takes precedence over `thr_en`.

### 5.3 Per-lane arithmetic (lane l = 4·slice + byte)
```
p   = k8 byte l (u8)
cA  = perlane ? (byte<3 ? word.byte[byte] : 0) : s8(word[7:0])
cB  = perlane ? 0 : s8(word[15:8])
MAC: A = FIRST ? p*cA : A + p*cA ; B = FIRST ? p*cB : B + p*cB  (24-bit)
MIN: M = FIRST ? (cA? p : 255) : (cA? min(M,p) : M)
MAX: M = FIRST ? (cA? p : 0)   : (cA? max(M,p) : M)
CENTER: C = p
LAST → post:
  MAC: v = comb(A,B);  if round && shift: v += 1<<(shift-1)
       v = v >>> shift (arithmetic); v += offset; v = clamp(v,0,255)
  MIN/MAX: v = M
  if peak_en: v = (C == v && C >= thr) ? C : 0
  elif thr_en: v = (v >= thr) ? 255 : 0
  out byte = lane_mask[byte] ? v : 0
```
`|A|` is computed on the 24-bit value (it cannot overflow). Combine results
use 26-bit signed arithmetic.

### 5.4 Handshake / pipeline
* One beat = one k8 row + one k9 row, taken together (join). The k14 config
  is latched whenever a k14 token arrives (the op is always acked).
* A k1 row is produced only on LAST. The module is a global-stall pipeline:
  every stage advances when the output register is empty or being accepted.
  Latency from the LAST beat to the k1 row is 6 clocks.
* Only k8+k9 pairs are consumed. A k9 without a matching k8 (or the other
  way round) waits.

## 6. Instruction schedule (task 6, summary)

Line buffers are VMEM rings. For a kernel of size N (R=(N-1)/2):
* N line slots, each `W/16 + 2` rows: `[pad][W/16 pixel rows][pad]`.
  Pixel x of a line is DMA word `16·(slot_row+1) + x`.
* For output chunk j (pixels 16j..16j+15) of output row y and tap (dy,dx),
  `LK8` uses `vreg = uniform(slot_row(y+dy) + 1 + j) + SKEW[dx]` where
  `SKEW[dx][b] = ((dx mod 16) << 12) + (dx≥0 ? (b<dx) : -(b≥16+dx))`.
  The per-bank row offset handles the wrap into the neighbouring 16-word row;
  the permutation rotates banks back into pixel order.
* The `SKEW` rows (dx = −3..+3) live in a VMEM table. They are loaded into 7
  vregs with `LK15/MVK15V`.
* The coefficient table has one row per tap, walked with
  `ADD_LK9(Vc,Vc,Vone)`.
* Each chunk ends with `SK1` into the output line. Fence: `ADD_SK15` writes a
  token into a fence row, and the CPU polls it before reading the line or
  DMAing it out.
* 3x3 cost: 9 × (MVXV + ADD + LK8 + LK9) + SK1 ≈ 37 vector instructions per
  16 pixels.

## 7. Test I/O (grill Q7, Q8)

* cs22 is the image FPGA. The testbench injects on `cs22in`, which requires
  `CS32_NO_RISCV`, as in `test_inject_cs22`, and captures `cs22out`. Every
  other FPGA is `*_NO_RISCV`.
* The datapath choice is sim-wide: every Q-engine in the build gets the image
  datapath (`HIGGS_DATAPATH=img`).
* Input stream, per job:
  * `w0 = 0x1A6E0000 | border<<9 | fmt<<8 | op`, where fmt 0 = gray and
    1 = RGBX, and border 0 = ZERO and 1 = REPLICATE;
  * `w1 = H<<16 | W`;
  * `w2 = thr | roi_thr<<8`;
  * then `W·H` pixel words.
  * `op = 0xFF` ends the run.
* Output stream, per job:
  * the same 3 header words;
  * `W·H` pixel words;
  * a trailer: `0x5A7A0000 | n` followed by n words: `max_v, max_x, max_y,
    min_v, min_x, min_y, nz_count, sum, roi_count, roi_x0, roi_y0, roi_x1,
    roi_y1`, then one edge count per 16x16 tile in raster order. With no ROI
    tiles the bounding box is `0xFFFF`×4.
* Limits: W is a multiple of 16 and ≤ 1024 (the C library rejects others),
  and H is unbounded. Test images: gray 64x24 and RGBX 32x16. The synthetic
  scene is deterministic and generated by Python: a rectangle, a disc, a
  diagonal line, a gradient and LCG noise.
