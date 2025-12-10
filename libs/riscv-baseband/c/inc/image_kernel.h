#ifndef __IMAGE_KERNEL_H__
#define __IMAGE_KERNEL_H__

///
/// Image-kernel library for the image datapath (HIGGS_DATAPATH=img).
///
/// Spec: doc/kernel/NOTES.md. Section 5 is the datapath contract, section 6
/// the instruction schedule and section 7 the stream format. The op table
/// here mirrors op_stages() in libs/datapath/image/img_model.py.
///
/// Two levels of API:
///  * img_stream_job() / img_stream_loop(): stream jobs. Each job arrives on
///    DMA in as a 3-word header plus W*H pixel words, and the results
///    (header, W*H pixels, stats/ROI trailer) leave on DMA out.
///  * img_op_stages() / img_run_stages(): run the op table, or a custom
///    img_stage_t list, over lines supplied by a caller callback.
///
/// This only works on a Q-engine built with the image datapath. On the FFT
/// datapath the LK8/LK9/SK1 schedule below would hang.
///

#include <stdint.h>

// ---------------------------------------------------------------- stream --
#define IMG_HDR_MAGIC (0x1A6E0000u)
#define IMG_TRL_MAGIC (0x5A7A0000u)
#define IMG_ERR_MAGIC (0xEE770000u)
#define IMG_OP_END    (0xFF)

// error codes returned by img_job_check() and sent as IMG_ERR_MAGIC | code
#define IMG_ERR_OP    (1)
#define IMG_ERR_SIZE  (2)
#define IMG_ERR_TILES (3)
#define IMG_ERR_HDR   (4)

#define IMG_FMT_GRAY (0)
#define IMG_FMT_RGBX (1)
#define IMG_BORDER_ZERO      (0)
#define IMG_BORDER_REPLICATE (1)

// ------------------------------------------------------------------ ops --
#define IMG_OP_COPY       (0)
#define IMG_OP_GAUSS3     (1)
#define IMG_OP_GAUSS5     (2)
#define IMG_OP_GAUSS7     (3)
#define IMG_OP_BOX3       (4)
#define IMG_OP_BOX5       (5)
#define IMG_OP_SHARPEN    (6)
#define IMG_OP_UNSHARP    (7)
#define IMG_OP_LAPLACE    (8)
#define IMG_OP_SOBEL      (9)
#define IMG_OP_SOBEL_X    (10)
#define IMG_OP_PREWITT    (11)
#define IMG_OP_SCHARR     (12)
#define IMG_OP_EMBOSS     (13)
#define IMG_OP_ERODE3     (14)
#define IMG_OP_DILATE3    (15)
#define IMG_OP_CUSTOM     (16)   // C API only (img_run_stages), not in a stream
#define IMG_OP_CHAN_GAUSS (17)
#define IMG_OP_EDGES      (32)
#define IMG_OP_PEAKS      (33)

// --------------------------------------------------- datapath config (k14) --
#define IMG_DP_MAC (0)
#define IMG_DP_MIN (1)
#define IMG_DP_MAX (2)

#define IMG_COMB_A      (0)
#define IMG_COMB_ABS_A  (1)
#define IMG_COMB_L1     (2)   // |A|+|B|
#define IMG_COMB_MAXABS (3)   // max(|A|,|B|)

// coefficient word flags (k9), taken from slice 0
#define IMG_F_FIRST  (1u << 24)
#define IMG_F_LAST   (1u << 25)
#define IMG_F_CENTER (1u << 26)

// ---------------------------------------------------------------- limits --
#define IMG_MAX_W      (1024)
#define IMG_MAX_N      (7)
#define IMG_MAX_TAPS   (IMG_MAX_N * IMG_MAX_N)
#define IMG_MAX_STAGES (2)
#define IMG_MAX_TILES  (4096)
#define IMG_STATS_WORDS (13)

typedef struct {
    uint8_t op;         // IMG_DP_*
    uint8_t comb;       // IMG_COMB_*
    uint8_t shift;      // 0..15
    uint8_t rnd;        // round before the shift
    uint8_t thr_en;     // out = v >= thr ? 255 : 0
    uint8_t peak_en;    // out = (ctr == v && ctr >= thr) ? ctr : 0
    uint8_t perlane;    // per-lane coefficients (ka=R, kb=G, kc=B)
    uint8_t lane_mask;  // output lanes (gray 0x1, RGBX 0x7)
    uint8_t thr;
    int16_t offset;
} img_cfg_t;

/// One streaming kernel pass. Kernels are n*n s8, row-major, where row i is
/// dy = i - (n-1)/2 and column j is dx = j - (n-1)/2. For MIN/MAX a non-zero
/// ka coefficient includes that tap in the window.
typedef struct {
    uint8_t n;           // 1, 3, 5 or 7
    const int8_t *ka;    // kernel A (per-lane: R)
    const int8_t *kb;    // kernel B or 0 (per-lane: G)
    const int8_t *kc;    // per-lane: B, else unused (0)
    img_cfg_t cfg;
} img_stage_t;

typedef struct {
    uint32_t op, fmt, border, w, h, thr, roi_thr;
} img_job_t;

/// Global features of the final image, the value is max(R,G,B) (gray: lane 0).
typedef struct {
    int32_t  max_v, max_x, max_y;
    int32_t  min_v, min_x, min_y;
    uint32_t nz, sum;
} img_stats_t;

// ------------------------------------------------------------ table/rows --
uint32_t img_cfg_word0(const img_cfg_t *c);
uint32_t img_cfg_word1(const img_cfg_t *c);

/// Fill out[] with the op's stages. Returns the stage count, or 0 for an
/// unknown op (CUSTOM included).
unsigned img_op_stages(unsigned op, unsigned fmt, unsigned thr, img_stage_t *out);

/// Coefficient word (with flags) for issue slot t of a stage. Taps are
/// issued column-major (dx outer, dy inner), see NOTES section 6.
uint32_t img_tap_word(const img_stage_t *st, unsigned t);

/// Parse / validate a stream header. Returns 0 or an IMG_ERR_* code.
unsigned img_job_parse(const uint32_t hdr[3], img_job_t *job);
unsigned img_job_check(const img_job_t *job);

// -------------------------------------------------------------- running --

/// One-time setup: zero line, skew table. Call before anything else.
void img_init(void);

/// Called by img_run_stages() to fill input line y (W pixel words) at DMA
/// word address dma_addr. It must return once the words are in VMEM.
typedef void (*img_line_in_fn)(uint32_t y, uint32_t dma_addr, uint32_t w, void *ctx);
/// Called by img_run_stages() with finished output line y at
/// cpu_ptr/dma_addr. The line buffer is reused two lines later (double
/// buffered); img_run_stages() waits for DMA out to drain before reuse.
typedef void (*img_line_out_fn)(uint32_t y, volatile uint32_t *cpu_ptr, uint32_t dma_addr, uint32_t w, void *ctx);

/// Run nst stages over a W x H image, one output line at a time, keeping
/// only n lines per stage in VMEM rings. Returns 0 or an IMG_ERR_* code.
unsigned img_run_stages(const img_stage_t *st, unsigned nst, uint32_t w, uint32_t h,
                        uint32_t border, img_line_in_fn in, img_line_out_fn out, void *ctx);

/// Process one stream job (header already read). Sends header, pixels and
/// trailer (or header + IMG_ERR_MAGIC|code after draining the input).
void img_stream_job(const img_job_t *job, unsigned err);

/// Read and process jobs from DMA in until an END header (which is echoed).
/// Returns the number of jobs processed (END not counted).
unsigned img_stream_loop(void);

/// Stats of the last img_stream_job().
const img_stats_t *img_last_stats(void);

/// Clock cycles spent in the last img_stream_job().
uint32_t img_last_cycles(void);

#endif
