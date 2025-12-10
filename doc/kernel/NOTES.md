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
  * `SK15` stores the vector unit's *k15 output*, which is only valid for
    funct `MV_V_K15`. To store a vreg into a row:
    `MVVK15_KNOP(Vsrc); MVXV_KNOP(Va,row); VNOP_SK15(Va)`
    (the pattern in `test_slice_0`). The `MVVK15_SK15` macro in
    `xbaseband.h` is malformed (`| |`), so the library does not use it.
  * **MVVK15 over-pushes when the vector unit goes idle** (found in
    test_image_1, §10). In `vector_slice.v`,
    `i_k15_valid = (funct_reg==MV_V_K15) & ~k15_latched`. `funct_reg` keeps
    the last opcode while no instruction is valid, and `k15_latched` clears
    on every idle cycle (`t_instr_ready` is 1 then). So an `MVVK15` that is
    not immediately followed by another vector instruction pushes the same
    value again and again, until the k15 → inmux elastic buffers are full.
    The next `SK15` then stores a stale copy. The image library therefore
    never uses `MVVK15`; its fence uses `LK13`/`SK13` (§6.3).
  * `LK13 → SK13` is a plain row copy: VMEM → oumux k13 → 4-deep FIFO
    (edge 41) → inmux k13 → store.
  * vreg `ADD` is field-split: the 12-bit baddr and the 4-bit perm are added
    separately, with no carry from baddr into perm (`test_slice_0`,
    "add overflow test").
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
| 17 | CHAN_GAUSS | 3x3 | per-lane demo: R `2·gauss3`, G `gauss3`, B `0` | A | 4 | y | 0 |

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
* The Python model (`img_model.fetch`) implements exactly this: zero, or
  a clamped (edge-replicated) coordinate.

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
The flags (FIRST/LAST/CENTER) are taken from **slice 0's word only**.
Coefficients come from each slice's own word, so per-slice coefficients also
work, although the C library always writes the same word to all 16 slices.

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
  Latency from the LAST beat to the k1 row is 5 clocks. The k14 config is
  sampled with every beat and travels down the pipeline with it.
* Only k8+k9 pairs are consumed. A k9 without a matching k8 (or the other
  way round) waits.

## 6. Instruction schedule and C library (task 6)

`libs/riscv-baseband/c/inc/image_kernel.{h,c}`. Like every file in that
folder it is compiled into every firmware. `--gc-sections` drops it, and its
VMEM buffers, when unused.

### 6.1 VMEM layout (static `VMEM_SECTION` arrays, ~93 KB)
| buffer | rows | use |
|---|---|---|
| `img_ring_mem` | 14 slots × (1024+32)/16 | line rings: stage s has n_s slots |
| `img_zero_mem` | 1 slot | all-zero line for ZERO borders |
| `img_out_mem` | 2 × 64 | final output lines, double-buffered for DMA out |
| `img_cfg_mem` | 2 | k14 config row per stage (words 0, 1) |
| `img_coef_mem` | 2 × 49 | one k9 row per tap per stage (same word in all 16 slices) |
| `img_skew_mem` | 7 | SKEW rows, dx = −3..+3 |
| `img_fence_mem` | 3 | fence row, token rows (all 1s, all 2s) |
| `img_hin_mem`, `img_hout_mem` | 1 each | header in/out |
| `img_trl_mem` | trailer | 14 words + 4096 tile counts |

* A line slot is `W/16 + 2` rows: `[pad][W/16 pixel rows][pad]`. Image row
  y of stage s lives in slot `y mod n_s`. Pixel x is DMA word
  `16·(slot_row + 1) + x`.
* Horizontal halo: after each input DMA (and after each intermediate stage
  row) the CPU writes R words either side of the line (0 or the edge pixel),
  then reads one back so the write has landed before any vector load.
* Vertical border: out-of-image rows map to the clamped row (REPLICATE) or
  to the zero line (ZERO).

### 6.2 Vector registers
V0 row address, V1..V7 SKEW for dx = −3..+3, V8 coefficient pointer,
V9 = 1, V10 output pointer, V11 skewed address, V12/V13 fence and config
addresses.
SKEW rows are loaded once per `img_run_stages` with
`MVXV(V0,row); LK15(V0); MVK15V(Vn,0)`.

### 6.3 Per output row (stage s, row y)
```
if stage changed:  MVXV(V13,cfg_row); LK14(V13)       // after a fence: nothing in flight
MVXV(V10, dst_row)
for chunk j in 0..W/16-1:
    MVXV(V8, coef_row)
    for dx in -R..R:                 // column-major = coefficient order
        for dy in -R..R:
            MVXV(V0, pix_row(y+dy) + j)
            ADD(V11, V0, SKEW[dx])   // dx == 0: LK8(V0) directly
            LK8(V11)
            ADD_LK9(V8, V8, V9)      // load coef row, then V8++
    ADD_SK1(V10, V10, V9)            // store k1 row, then V10++
fence()
```
* `SKEW[dx][b] = ((dx & 15) << 12) | (off & 0xFFF)`, where
  `off = dx ≥ 0 ? (b < dx) : −(b ≥ 16+dx)`. The vreg ADD is field-split
  (§1), so the permutation and the row offset are encoded separately. Bank b
  reads row `base + off_b`, and the permutation rotates the banks back into
  pixel order, so slice s sees pixel `16j + s + dx`.
* Coefficient rows follow the same column-major tap order (t → `jx = t/n`,
  `iy = t%n`). FIRST is on t = 0, LAST on t = n²−1, CENTER on (r, r). The
  accumulation is order-independent, so the result equals the model's
  row-major reference.
* 3x3 cost: ~5 RISC-V instructions per tap, so ~50 per 16 pixels. 7x7 is
  ~250.
* **Fence:** there is no hardware CPU↔vector fence. `img_fence()`
  alternates the token between 1 and 2 and copies the matching token row
  onto the fence row with `MVXV(V12,fence_row+tok); LK13(V12);
  MVXV(V13,fence_row); SK13(V13)`. It then polls `fence_mem[0]` until it
  equals the token. Vector stores leave through one in-order store mux, so
  once the token is visible every earlier SK1 row is in VMEM, and the
  datapath is empty. The first version used `MVVK15`/`SK15` and hung on the
  second row (§1, §10).

### 6.4 Multi-stage (PEAKS) and pull scheduling
`img_produce(s, y)` first makes sure stage s has the input rows up to
`min(y+R, H−1)`. For stage 0 it DMAs input lines. For stage s > 0 it
recursively produces rows of stage s−1 into stage s's ring. Then it runs
the row. This keeps only n_s lines per stage and runs PEAKS (Sobel → 3x3
NMS) in a single pass.

### 6.5 API
* `img_op_stages(op, fmt, thr, stages)`: the op table, mirroring
  `img_model.op_stages`.
* `img_run_stages(stages, n, W, H, border, line_in, line_out, ctx)`: the
  generic engine. `line_in(y, dma_addr, W)` fills an input line (the stream
  layer DMAs it; other users can copy from memory). `line_out(y, cpu_ptr,
  dma_addr, W)` receives each final line.
* `img_stream_job` / `img_stream_loop`: the cs22 stream protocol (§7).
  Stats are computed per output line in the out callback, which also DMAs
  the line out. Before a new output line buffer is written, the code waits
  until DMA_1 has ≤ 1 transfer queued (`dma_out` pops a schedule entry only
  after its last word has been read).
* `img_last_stats()`, `img_last_cycles()`: the last job's features and
  timer cycles.

## 7. Test I/O (grill Q7, Q8)

* cs22 is the image FPGA. The testbench injects on `cs22in`, which requires
  `CS32_NO_RISCV`, as in `test_inject_cs22`, and captures `cs22out`.
* cs21 must run firmware. cs22out's ready is cs21's `HS_EAST_OUT`, which only
  goes high while cs21 has an input DMA scheduled, so cs21 runs a DMA sink
  loop (`test_image_1/override/fpgas/cs/cs21`). The platform is cs32
  (no RISC-V) → cs22 (image firmware) → cs21 (sink).
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
* Errors: a job with an unknown op (1), a bad W (2: 0, not a multiple of 16,
  or > 1024), a zero H (2) or more than 4096 16x16 tiles (3) is echoed as
  its 3 header words plus `0xEE770000|code`. Its W·H pixels are consumed and
  dropped. A bad header magic gives code 4 and nothing is drained.
  `IMG_OP_CUSTOM` is API-only (`img_run_stages`), so it is an error in a
  stream.
* The END job (`op = 0xFF`) is echoed as 3 words, and `img_stream_loop`
  returns.
* Test images: gray 64x24 and RGBX 32x16. The synthetic
  scene is deterministic and generated by Python: a rectangle, a disc, a
  diagonal line, a gradient and LCG noise.

## 8. Python model (task 4)

`libs/datapath/image/img_model.py` is pure Python 3 with no numpy, so the
test Makefiles have no dependencies.

* `Datapath`: a beat-level model of §5 (64 lanes, 24-bit wrapping
  accumulators, flags from slice 0). It is the reference for the RTL unit
  test.
* `run_stage`: the pixel-level reference, with the borders from §2.
  `run_stage_beats` evaluates the same stage in the hardware order (16-pixel
  chunks, one beat per tap). The self-test checks that the two are identical
  for every op, both formats and both borders.
* `op_stages(op, fmt, thr)`: the op table (§2/§3) as a list of `Stage`s,
  each holding its kernels, config and tap list (row-major, with
  FIRST/LAST/CENTER flags). The C library mirrors this table.
* `stats_trailer` / `run_job` / `build_streams`: the feature trailer and the
  full input/expected cs22 stream for `default_jobs()`. There are 24 jobs:
  every op on gray 64x24, 4 on RGBX 32x16 and 2 error jobs (an unknown op
  and a width that is not a multiple of 16), giving 29,947 input words and
  30,233 expected words.
* `job_error(op, w, h)`: the stream-level validation the C library also
  does. An error job echoes the header plus `0xEE770000|code` (1 = op,
  2 = size, 3 = tiles > 4096) and its pixels are consumed and dropped.
* Scene generator: a gradient, a rectangle, a disc, the diagonal `x = 2y`
  and ±8 LCG noise. Each channel has different shapes, so the RGBX ops
  exercise every lane.
* CLI:
  * `selftest` (about 2 s): hand-checked Sobel step, flat-field invariants
    for the blurs, derivatives and emboss, erode/dilate/peak plateau, 81-tap
    headroom, ROI clipping, compare round trip, and beat-vs-pixel
    cross-check.
  * `gen-unit OUT`: RTL beat vectors (`C`/`B`/`E` lines). They cover
    random configs of every op/comb, extreme values (255·−128 × 81 taps),
    ±32767 offsets, per-lane mode, thresholds and peaks, and random flags in
    slices 1–15.
  * `gen-stream IN EXP`, `compare EXP GOT`: the stream files for
    test_image_1 and the job-by-job diff report.

## 9. RTL, integration and synthesis (task 5)

* `libs/datapath/image/rtl/img_datapath.v`: a single module with the
  piston-style ports `t_k8/t_k9/t_k14` (req/ack) and `i_k1`. It is a 6-stage
  global-stall pipeline (§5.4). Each lane has two `(* use_dsp = "yes" *)`
  u8×s8 products into 24-bit accumulators A/B, plus a MIN/MAX register and a
  centre-capture register.
* Unit test `libs/datapath/image/sim` (`make`): Verilator `-Wall` lint, then
  a C++ TB that replays `img_model.py gen-unit` vectors (240 random
  sequences plus directed edge cases) with 0 %, 30 % and 70 % random
  backpressure/bubbles. It is bit-exact against the model on every row.
* Piston integration (`libs/q-engine/piston/hdl/piston.v`): under
  `` `ifdef HIGGS_IMG_DATAPATH `` the FFT datapath instance is replaced by
  `img_datapath`, which is wired to the same `dat38/39/40` inputs,
  `dat42_nxt` output and `req/ack` handshakes. `` `else `` keeps the
  original code, byte for byte.
* Selection knob `HIGGS_DATAPATH=img`:
  * `verilog_paths.mk` adds `img_datapath.v` to `Q_ENGINE_ALL_VERILOG`;
  * `tb_common.mk` adds `+define+HIGGS_IMG_DATAPATH=1` (Verilator and XSIM);
  * the CS12 Vivado scripts (`build.tcl`/`implement.tcl`) read the same
    environment variable, add the file and define, and write to `out_img/`.
* Vivado 2025.2, CS12 (xczu-class part), `sys_clk` 125 MHz:

  | | FFT datapath (baseline) | image datapath |
  |---|---|---|
  | DSP | 38 | 134 (128 lane MACs + 6 elsewhere) |
  | CLB LUT | ~28k | 39,615 |
  | CLB FF | – | 31,128 |
  | BRAM tiles | 72 | 72 |
  | routed WNS | met | **+0.647 ns**, all constraints met |

  The 128 u8×s8 multipliers all mapped to DSP48E2. The extra LUTs are the
  64-lane MIN/MAX, combine and saturate logic plus the 512-bit pipeline.

## 10. Platform test results (task 7)

`sim/verilator/test_image_1` (see its README) builds cs22 with
`HIGGS_DATAPATH=img`, runs `img_init(); img_stream_loop();`, and injects the
24-job stream from `img_model.py gen-stream` into `cs22in`.

* **Verilator** (`make test`): all 24 jobs are bit-exact against the model.
  That covers 18 gray ops at 64×24, two error jobs (bad op, W=40 not a
  multiple of 16) and 4 RGBX jobs at 32×16. END arrives at about 1.95 M
  cycles. A clean build plus the run takes about 4.5 min wall.
* **XSIM** (`make xsim_run`, Vivado 2025.2): PASS. `xsim_got.hex` is
  byte-identical to Verilator's `got.hex`. The run takes about 8 min wall.
* **Regression:** `test_fft_lib_1` with the default FFT datapath still
  passes ("All Tests Passed").

### 10.1 Cycles per job

`tb.cpp` records the 500-cycle tick at which each job header appears in
`cs22out` and prints `JOBCYC` lines. The header goes out once the job
starts, so each gap below covers one whole job: pixels in, kernel, lines
out, trailer.

| job | size | cycles | per pixel |
|---|---|---|---|
| COPY (1 tap) | 64×24 gray | 77.5 k | 50 |
| GAUSS3, BOX3, SHARPEN, LAPLACE, SOBEL, … (3×3) | 64×24 | 91–93 k | ~60 |
| GAUSS5, BOX5 (5×5) | 64×24 | 113 k | 74 |
| GAUSS7 (7×7) | 64×24 | 142 k | 92 |
| PEAKS (Sobel → NMS, 2 stages) | 64×24 | 120 k | 78 |
| GAUSS3 / SOBEL / CHAN_GAUSS / EDGES | 32×16 RGBX | 46–47.5 k | ~90 |
| error job (drain) | 32×3, 40×2 | < 500 | – |

* **Fixed cost.** COPY sets the floor at about 50 cycles per pixel. Most of
  that is the CPU: it reads each input word from the stream FIFO and packs
  it into VMEM, then does per-line output DMA and stats (min/max/nz/sum/tile
  counts are all computed on the CPU per output pixel).
* **Kernel cost.** Each extra tap costs about 14–16 cycles per 16-pixel
  chunk. Measured against COPY over 96 chunks: 3×3 adds ~150 per chunk,
  5×5 ~370 and 7×7 ~670. The per-tap cost is the MVXV + ADD(skew) + LK8 +
  ADD_LK9 issue sequence. The 64-lane datapath itself is never the
  bottleneck.
* **Speed-up options** (not done): move stats to the datapath (min/max are
  already available as MIN/MAX ops); unroll the input packing loop; issue
  the tap sequence from a precomputed schedule so the per-tap address math
  leaves the inner loop.

### 10.2 Issues found by the platform test

1. **MVVK15 idle over-push** (hardware, `vector_slice.v`, §1). The first
   fence design (MVVK15 + SK15) hung on output row 1 of job 0. Fixed in
   the library with an LK13→SK13 token-copy fence (§6.3). The shared RTL
   is unchanged.
2. **First injected word lost on XSIM** (`vex_machine_top.v` input buffer).
   The buffer writes on `temp_valid && temp_ready_delay`, and the delayed
   ready leaves reset one cycle after `o_afull_n`, so a word offered right
   after reset is acked but dropped. `tb_higgs_top_xsim.sv` waits
   `INJECT_DELAY` = 100 cycles after reset before injecting. Verilator's
   injector starts later and never hit this.
3. **Debug method.** `./obj_dir/Vtb_higgs_top +stalltrace`: if no output
   arrives for 500 k cycles, the TB prints the cs22 PC and the fence row and
   writes a 20-cycle `stall.vcd`. Verilator inlines most piston signals, so
   the VCD is the practical way to inspect the inmux/oumux req/ack state.
