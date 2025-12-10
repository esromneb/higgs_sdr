#include "image_kernel.h"
#include "xbaseband.h"
#include "vmem.h"
#include "csr_control.h"
#include "dma.h"
#include "stall.h"

///
/// Implementation notes (see doc/kernel/NOTES.md section 6):
///
/// VMEM layout (all static, one 16-word row = 16 pixels):
///  * rings: stage s keeps n_s line slots of W/16+2 rows, [pad][pixels][pad].
///    Pixel x of a slot is DMA word 16*(slot_row+1)+x. The pad words next
///    to the line hold the horizontal halo (0 or the edge pixel).
///  * zero line: an all-zero slot that ZERO borders use for rows above/below
///    the image.
///  * two output lines (double buffered for DMA out), config rows,
///    coefficient rows (one per tap, same word in all 16 slices), 7 skew rows,
///    the fence row, header buffers and the trailer (stats + tile counts).
///
/// Vector registers:
///  V0 row address, V1..V7 skew for dx=-3..+3, V8 coefficient pointer,
///  V9 = 1, V10 output row pointer, V11 skewed address, V12/V13 fence/cfg.
///

#define IMG_SLOT_WORDS (IMG_MAX_W + 32)
#define IMG_RING_SLOTS (IMG_MAX_STAGES * IMG_MAX_N)
#define IMG_TRL_TILE0  (1 + IMG_STATS_WORDS)

VMEM_SECTION uint32_t img_ring_mem[IMG_RING_SLOTS * IMG_SLOT_WORDS];
VMEM_SECTION uint32_t img_zero_mem[IMG_SLOT_WORDS];
VMEM_SECTION uint32_t img_out_mem[2 * IMG_MAX_W];
VMEM_SECTION uint32_t img_cfg_mem[IMG_MAX_STAGES * 16];
VMEM_SECTION uint32_t img_coef_mem[IMG_MAX_STAGES * IMG_MAX_TAPS * 16];
VMEM_SECTION uint32_t img_skew_mem[7 * 16];
VMEM_SECTION uint32_t img_fence_mem[3 * 16];   // fence row, token rows 1 and 2
VMEM_SECTION uint32_t img_hin_mem[16];
VMEM_SECTION uint32_t img_hout_mem[16];
VMEM_SECTION uint32_t img_trl_mem[IMG_TRL_TILE0 + IMG_MAX_TILES + 2];

#define IMG_VM(x) ((volatile uint32_t *)(x))
#define IMG_BARRIER() asm volatile("" ::: "memory")
#define IMG_ROWP(row) ((volatile uint32_t *)(vector_memory + 16 * (row)))

// ------------------------------------------------------------- op table --
static const int8_t K_ONE[1] = {1};
static const int8_t K_G3[9] = {1, 2, 1, 2, 4, 2, 1, 2, 1};
static const int8_t K_G3X2[9] = {2, 4, 2, 4, 8, 4, 2, 4, 2};
static const int8_t K_G5[25] = {
    1,  4,  6,  4, 1,
    4, 16, 24, 16, 4,
    6, 24, 36, 24, 6,
    4, 16, 24, 16, 4,
    1,  4,  6,  4, 1};
static const int8_t K_G7[49] = {
     1,  3,  7,  10,  7,  3,  1,
     3,  9, 21,  30, 21,  9,  3,
     7, 21, 49,  70, 49, 21,  7,
    10, 30, 70, 100, 70, 30, 10,
     7, 21, 49,  70, 49, 21,  7,
     3,  9, 21,  30, 21,  9,  3,
     1,  3,  7,  10,  7,  3,  1};
static const int8_t K_BOX3[9] = {114, 114, 114, 114, 114, 114, 114, 114, 114};
static const int8_t K_BOX5[25] = {
    82, 82, 82, 82, 82, 82, 82, 82, 82, 82, 82, 82, 82,
    82, 82, 82, 82, 82, 82, 82, 82, 82, 82, 82, 82};
static const int8_t K_ONES3[9] = {1, 1, 1, 1, 1, 1, 1, 1, 1};
static const int8_t K_ZERO3[9] = {0, 0, 0, 0, 0, 0, 0, 0, 0};
static const int8_t K_SHARPEN[9] = {0, -1, 0, -1, 5, -1, 0, -1, 0};
static const int8_t K_UNSHARP[9] = {-1, -2, -1, -2, 28, -2, -1, -2, -1};
static const int8_t K_LAPLACE[9] = {0, 1, 0, 1, -4, 1, 0, 1, 0};
static const int8_t K_GX[9] = {-1, 0, 1, -2, 0, 2, -1, 0, 1};
static const int8_t K_GY[9] = {-1, -2, -1, 0, 0, 0, 1, 2, 1};
static const int8_t K_PX[9] = {-1, 0, 1, -1, 0, 1, -1, 0, 1};
static const int8_t K_PY[9] = {-1, -1, -1, 0, 0, 0, 1, 1, 1};
static const int8_t K_SX[9] = {-3, 0, 3, -10, 0, 10, -3, 0, 3};
static const int8_t K_SY[9] = {-3, -10, -3, 0, 0, 0, 3, 10, 3};
static const int8_t K_EMBOSS[9] = {-2, -1, 0, -1, 1, 1, 0, 1, 2};

static void img_stage_set(img_stage_t *s, uint8_t n, const int8_t *ka, const int8_t *kb,
                          uint8_t op, uint8_t comb, uint8_t shift, uint8_t lane_mask) {
    s->n = n;
    s->ka = ka;
    s->kb = kb;
    s->kc = 0;
    s->cfg.op = op;
    s->cfg.comb = comb;
    s->cfg.shift = shift;
    s->cfg.rnd = shift ? 1 : 0;
    s->cfg.thr_en = 0;
    s->cfg.peak_en = 0;
    s->cfg.perlane = 0;
    s->cfg.lane_mask = lane_mask;
    s->cfg.thr = 0;
    s->cfg.offset = 0;
}

unsigned img_op_stages(unsigned op, unsigned fmt, unsigned thr, img_stage_t *out) {
    const uint8_t lm = (fmt == IMG_FMT_GRAY) ? 0x1 : 0x7;
    img_stage_t *s = out;
    switch (op) {
    case IMG_OP_COPY:    img_stage_set(s, 1, K_ONE, 0, IMG_DP_MAC, IMG_COMB_A, 0, lm); return 1;
    case IMG_OP_GAUSS3:  img_stage_set(s, 3, K_G3, 0, IMG_DP_MAC, IMG_COMB_A, 4, lm); return 1;
    case IMG_OP_GAUSS5:  img_stage_set(s, 5, K_G5, 0, IMG_DP_MAC, IMG_COMB_A, 8, lm); return 1;
    case IMG_OP_GAUSS7:  img_stage_set(s, 7, K_G7, 0, IMG_DP_MAC, IMG_COMB_A, 10, lm); return 1;
    case IMG_OP_BOX3:    img_stage_set(s, 3, K_BOX3, 0, IMG_DP_MAC, IMG_COMB_A, 10, lm); return 1;
    case IMG_OP_BOX5:    img_stage_set(s, 5, K_BOX5, 0, IMG_DP_MAC, IMG_COMB_A, 11, lm); return 1;
    case IMG_OP_SHARPEN: img_stage_set(s, 3, K_SHARPEN, 0, IMG_DP_MAC, IMG_COMB_A, 0, lm); return 1;
    case IMG_OP_UNSHARP: img_stage_set(s, 3, K_UNSHARP, 0, IMG_DP_MAC, IMG_COMB_A, 4, lm); return 1;
    case IMG_OP_LAPLACE: img_stage_set(s, 3, K_LAPLACE, 0, IMG_DP_MAC, IMG_COMB_ABS_A, 0, lm); return 1;
    case IMG_OP_SOBEL:   img_stage_set(s, 3, K_GX, K_GY, IMG_DP_MAC, IMG_COMB_L1, 2, lm); return 1;
    case IMG_OP_SOBEL_X: img_stage_set(s, 3, K_GX, 0, IMG_DP_MAC, IMG_COMB_ABS_A, 2, lm); return 1;
    case IMG_OP_PREWITT: img_stage_set(s, 3, K_PX, K_PY, IMG_DP_MAC, IMG_COMB_L1, 2, lm); return 1;
    case IMG_OP_SCHARR:  img_stage_set(s, 3, K_SX, K_SY, IMG_DP_MAC, IMG_COMB_L1, 4, lm); return 1;
    case IMG_OP_EMBOSS:
        img_stage_set(s, 3, K_EMBOSS, 0, IMG_DP_MAC, IMG_COMB_A, 0, lm);
        s->cfg.offset = 128;
        return 1;
    case IMG_OP_ERODE3:  img_stage_set(s, 3, K_ONES3, 0, IMG_DP_MIN, IMG_COMB_A, 0, lm); return 1;
    case IMG_OP_DILATE3: img_stage_set(s, 3, K_ONES3, 0, IMG_DP_MAX, IMG_COMB_A, 0, lm); return 1;
    case IMG_OP_CHAN_GAUSS:
        img_stage_set(s, 3, K_G3X2, K_G3, IMG_DP_MAC, IMG_COMB_A, 4, lm);
        s->kc = K_ZERO3;
        s->cfg.perlane = 1;
        return 1;
    case IMG_OP_EDGES:
        img_stage_set(s, 3, K_GX, K_GY, IMG_DP_MAC, IMG_COMB_L1, 2, lm);
        s->cfg.thr_en = 1;
        s->cfg.thr = (uint8_t)thr;
        return 1;
    case IMG_OP_PEAKS:
        img_stage_set(s, 3, K_GX, K_GY, IMG_DP_MAC, IMG_COMB_L1, 2, lm);
        img_stage_set(s + 1, 3, K_ONES3, 0, IMG_DP_MAX, IMG_COMB_A, 0, lm);
        s[1].cfg.peak_en = 1;
        s[1].cfg.thr = (uint8_t)thr;
        return 2;
    default:
        return 0;
    }
}

uint32_t img_cfg_word0(const img_cfg_t *c) {
    return ((uint32_t)c->op & 3u) |
           ((uint32_t)c->comb & 3u) << 2 |
           ((uint32_t)c->shift & 15u) << 4 |
           (uint32_t)(c->rnd ? 1u : 0u) << 8 |
           (uint32_t)(c->thr_en ? 1u : 0u) << 9 |
           (uint32_t)(c->peak_en ? 1u : 0u) << 10 |
           (uint32_t)(c->perlane ? 1u : 0u) << 11 |
           ((uint32_t)c->lane_mask & 15u) << 12 |
           (uint32_t)c->thr << 16;
}

uint32_t img_cfg_word1(const img_cfg_t *c) {
    return (uint32_t)(uint16_t)c->offset;
}

uint32_t img_tap_word(const img_stage_t *st, unsigned t) {
    const unsigned n = st->n;
    const unsigned r = (n - 1) / 2;
    const unsigned jx = t / n;          // dx = jx - r (outer)
    const unsigned iy = t % n;          // dy = iy - r (inner)
    const unsigned k = iy * n + jx;
    uint32_t w = (uint8_t)st->ka[k];
    if (st->kb) {
        w |= (uint32_t)(uint8_t)st->kb[k] << 8;
    }
    if (st->cfg.perlane && st->kc) {
        w |= (uint32_t)(uint8_t)st->kc[k] << 16;
    }
    if (t == 0) {
        w |= IMG_F_FIRST;
    }
    if (t == n * n - 1) {
        w |= IMG_F_LAST;
    }
    if (iy == r && jx == r) {
        w |= IMG_F_CENTER;
    }
    return w;
}

// ----------------------------------------------------------- low level --
static uint32_t img_token;

static void img_skew_build(void) {
    volatile uint32_t *p = IMG_VM(img_skew_mem);
    for (int dx = -3; dx <= 3; dx++) {
        for (int b = 0; b < 16; b++) {
            // the vreg add has no carry from the 12-bit address into the
            // 4-bit permutation, so the fields are encoded separately
            int off = (dx >= 0) ? (b < dx) : -(b >= 16 + dx);
            p[(dx + 3) * 16 + b] = ((uint32_t)(dx & 15) << 12) | ((uint32_t)off & 0xFFFu);
        }
    }
    (void)p[7 * 16 - 1];
}

static void img_skew_load(void) {
    const uint32_t r = VMEM_ROW_ADDRESS(img_skew_mem);
    MVXV_KNOP(V0, r + 0); VNOP_LK15(V0); MVK15V_KNOP(V1, 0);
    MVXV_KNOP(V0, r + 1); VNOP_LK15(V0); MVK15V_KNOP(V2, 0);
    MVXV_KNOP(V0, r + 2); VNOP_LK15(V0); MVK15V_KNOP(V3, 0);
    MVXV_KNOP(V0, r + 3); VNOP_LK15(V0); MVK15V_KNOP(V4, 0);
    MVXV_KNOP(V0, r + 4); VNOP_LK15(V0); MVK15V_KNOP(V5, 0);
    MVXV_KNOP(V0, r + 5); VNOP_LK15(V0); MVK15V_KNOP(V6, 0);
    MVXV_KNOP(V0, r + 6); VNOP_LK15(V0); MVK15V_KNOP(V7, 0);
    MVXV_KNOP(V9, 1);
}

/// Wait until every vector store issued so far has landed in VMEM.
/// LK13 copies token row 1 or 2 through the k13 FIFO and SK13 stores it
/// to the fence row; the store mux is in order, so it lands after every
/// earlier SK1. MVVK15/SK15 cannot be used here: after an MVVK15 the
/// vector slice keeps pushing k15 copies while no new instruction arrives
/// (vector_slice.v: i_k15_valid only looks at funct_reg), which leaves
/// stale tokens queued for the next SK15. See NOTES.md section 7.
static void img_fence(void) {
    const uint32_t tok = (img_token == 1) ? 2 : 1;
    img_token = tok;
    const uint32_t row = VMEM_ROW_ADDRESS(img_fence_mem);
    MVXV_KNOP(V12, row + tok);
    VNOP_LK13(V12);
    MVXV_KNOP(V13, row);
    VNOP_SK13(V13);
    IMG_BARRIER();
    while (IMG_VM(img_fence_mem)[0] != tok) {
    }
    IMG_BARRIER();
}

void img_init(void) {
    volatile uint32_t *z = IMG_VM(img_zero_mem);
    for (unsigned i = 0; i < IMG_SLOT_WORDS; i++) {
        z[i] = 0;
    }
    volatile uint32_t *f = IMG_VM(img_fence_mem);
    for (unsigned i = 0; i < 16; i++) {
        f[i] = 0;
        f[16 + i] = 1;
        f[32 + i] = 2;
    }
    (void)f[47];
    img_token = 0;
    img_skew_build();
}

// --------------------------------------------------------- line engine --
typedef struct {
    uint32_t n, r;
    uint32_t cfg_row, coef_row;
    uint32_t ring_row;
} img_srt_t;

static struct {
    img_srt_t s[IMG_MAX_STAGES];
    uint32_t nst, w, h, border, slot_rows, chunks;
    uint32_t loaded;
    uint32_t produced[IMG_MAX_STAGES];
    uint32_t cur_cfg;
    uint32_t out_idx;
    img_line_in_fn in;
    img_line_out_fn out;
    void *ctx;
} img_rt;

static uint32_t img_pix_row(unsigned s, uint32_t y) {
    return img_rt.s[s].ring_row + (y % img_rt.s[s].n) * img_rt.slot_rows + 1;
}

/// Fill the r halo words either side of the line at pix_row.
static void img_halo(uint32_t pix_row, uint32_t r) {
    if (r == 0) {
        return;
    }
    volatile uint32_t *p = IMG_ROWP(pix_row);
    const uint32_t w = img_rt.w;
    uint32_t lv = 0;
    uint32_t rv = 0;
    if (img_rt.border == IMG_BORDER_REPLICATE) {
        lv = p[0];
        rv = p[w - 1];
    }
    for (uint32_t k = 1; k <= r; k++) {
        *(p - k) = lv;
        p[w - 1 + k] = rv;
    }
    (void)p[w - 1 + r];   // read back: CPU writes land before vector loads
    IMG_BARRIER();
}

#define IMG_COL(VS)                                  \
    for (i = 0; i < n; i++) {                        \
        const uint32_t a_ = rows[i] + j;             \
        MVXV_KNOP(V0, a_);                           \
        ADD_KNOP(V11, V0, VS);                       \
        VNOP_LK8(V11);                               \
        ADD_LK9(V8, V8, V9);                         \
    }

#define IMG_COL0                                     \
    for (i = 0; i < n; i++) {                        \
        const uint32_t a_ = rows[i] + j;             \
        MVXV_KNOP(V0, a_);                           \
        VNOP_LK8(V0);                                \
        ADD_LK9(V8, V8, V9);                         \
    }

/// Run stage s for output row y: every 16-pixel chunk gets n*n
/// LK8(skewed pixel row)+LK9(coefficient row) beats and one SK1.
static void img_row(unsigned s, uint32_t y) {
    const img_srt_t *st = &img_rt.s[s];
    const uint32_t n = st->n;
    const uint32_t coef_row = st->coef_row;
    const int h = (int)img_rt.h;
    uint32_t rows[IMG_MAX_N];
    uint32_t i;
    for (i = 0; i < n; i++) {
        int yy = (int)y + (int)i - (int)st->r;
        if (yy < 0 || yy >= h) {
            if (img_rt.border != IMG_BORDER_REPLICATE) {
                rows[i] = VMEM_ROW_ADDRESS(img_zero_mem) + 1;
                continue;
            }
            yy = (yy < 0) ? 0 : h - 1;
        }
        rows[i] = img_pix_row(s, (uint32_t)yy);
    }

    const int final = (s + 1 == img_rt.nst);
    uint32_t dst;
    if (final) {
        unsigned occ;
        // the other line buffer may still be sending; this one must be done
        do {
            CSR_READ(DMA_1_SCHEDULE_OCCUPANCY, occ);
        } while (occ > 1);
        dst = VMEM_ROW_ADDRESS(img_out_mem) + img_rt.out_idx * (IMG_MAX_W / 16);
    } else {
        dst = img_pix_row(s + 1, y);
    }

    if (img_rt.cur_cfg != s) {
        // safe: the previous row's fence drained the datapath
        MVXV_KNOP(V13, st->cfg_row);
        VNOP_LK14(V13);
        img_rt.cur_cfg = s;
    }

    MVXV_KNOP(V10, dst);
    for (uint32_t j = 0; j < img_rt.chunks; j++) {
        MVXV_KNOP(V8, coef_row);
        if (n >= 7) { IMG_COL(V1) }
        if (n >= 5) { IMG_COL(V2) }
        if (n >= 3) { IMG_COL(V3) }
        IMG_COL0
        if (n >= 3) { IMG_COL(V5) }
        if (n >= 5) { IMG_COL(V6) }
        if (n >= 7) { IMG_COL(V7) }
        ADD_SK1(V10, V10, V9);
    }
    img_fence();

    if (final) {
        img_rt.out(y, IMG_ROWP(dst), 16 * dst, img_rt.w, img_rt.ctx);
        img_rt.out_idx ^= 1;
    } else {
        img_halo(dst, img_rt.s[s + 1].r);
    }
}

/// Produce output row y of stage s, first pulling the input rows it needs.
static void img_produce(unsigned s, uint32_t y) {
    uint32_t need = y + img_rt.s[s].r;
    if (need > img_rt.h - 1) {
        need = img_rt.h - 1;
    }
    if (s == 0) {
        while (img_rt.loaded <= need) {
            const uint32_t pr = img_pix_row(0, img_rt.loaded);
            img_rt.in(img_rt.loaded, 16 * pr, img_rt.w, img_rt.ctx);
            STALL(8);
            img_halo(pr, img_rt.s[0].r);
            img_rt.loaded++;
        }
    } else {
        while (img_rt.produced[s - 1] <= need) {
            img_produce(s - 1, img_rt.produced[s - 1]);
        }
    }
    img_row(s, y);
    img_rt.produced[s]++;
}

unsigned img_run_stages(const img_stage_t *st, unsigned nst, uint32_t w, uint32_t h,
                        uint32_t border, img_line_in_fn in, img_line_out_fn out, void *ctx) {
    if (nst == 0 || nst > IMG_MAX_STAGES) {
        return IMG_ERR_OP;
    }
    if (w == 0 || h == 0 || (w & 15) || w > IMG_MAX_W) {
        return IMG_ERR_SIZE;
    }
    for (unsigned s = 0; s < nst; s++) {
        if (st[s].n > IMG_MAX_N || (st[s].n & 1) == 0 || st[s].ka == 0) {
            return IMG_ERR_OP;
        }
    }

    img_rt.nst = nst;
    img_rt.w = w;
    img_rt.h = h;
    img_rt.border = border;
    img_rt.chunks = w / 16;
    img_rt.slot_rows = w / 16 + 2;
    img_rt.in = in;
    img_rt.out = out;
    img_rt.ctx = ctx;

    uint32_t ring = VMEM_ROW_ADDRESS(img_ring_mem);
    volatile uint32_t *last = IMG_VM(img_cfg_mem);
    for (unsigned s = 0; s < nst; s++) {
        img_srt_t *rt = &img_rt.s[s];
        rt->n = st[s].n;
        rt->r = (st[s].n - 1) / 2;
        rt->ring_row = ring;
        ring += rt->n * img_rt.slot_rows;
        rt->cfg_row = VMEM_ROW_ADDRESS(img_cfg_mem) + s;
        rt->coef_row = VMEM_ROW_ADDRESS(img_coef_mem) + s * IMG_MAX_TAPS;

        volatile uint32_t *c = IMG_VM(img_cfg_mem) + 16 * s;
        c[0] = img_cfg_word0(&st[s].cfg);
        c[1] = img_cfg_word1(&st[s].cfg);
        for (unsigned b = 2; b < 16; b++) {
            c[b] = 0;
        }
        volatile uint32_t *k = IMG_VM(img_coef_mem) + 16 * IMG_MAX_TAPS * s;
        for (unsigned t = 0; t < rt->n * rt->n; t++) {
            const uint32_t word = img_tap_word(&st[s], t);
            for (unsigned b = 0; b < 16; b++) {
                k[16 * t + b] = word;
            }
            last = &k[16 * t + 15];
        }
        img_rt.produced[s] = 0;
    }
    (void)*last;   // read back before the vector unit loads the rows
    IMG_BARRIER();

    img_skew_load();
    img_rt.cur_cfg = 0xFFFFFFFFu;
    img_rt.loaded = 0;
    img_rt.out_idx = 0;

    for (uint32_t y = 0; y < h; y++) {
        img_produce(nst - 1, y);
    }
    return 0;
}

// --------------------------------------------------------------- stream --
static img_stats_t img_stats;
static uint32_t img_cycles;
static uint32_t img_fmt;

const img_stats_t *img_last_stats(void) {
    return &img_stats;
}

uint32_t img_last_cycles(void) {
    return img_cycles;
}

static void img_dma_in(uint32_t dma_addr, uint32_t n) {
    unsigned occ;
    dma_block_get(dma_addr, n);
    STALL(4);
    do {
        CSR_READ(DMA_0_SCHEDULE_OCCUPANCY, occ);
    } while (occ);
    STALL(8);
}

static void img_dma_out(uint32_t dma_addr, uint32_t n) {
    dma_block_send(dma_addr, n);
    STALL(4);
}

static void img_dma_out_idle(void) {
    unsigned occ;
    do {
        CSR_READ(DMA_1_SCHEDULE_OCCUPANCY, occ);
    } while (occ);
}

static void img_stream_line_in(uint32_t y, uint32_t dma_addr, uint32_t w, void *ctx) {
    (void)y;
    (void)ctx;
    img_dma_in(dma_addr, w);
}

/// Update the stats and tile counts with output line y, then send it.
static void img_stream_line_out(uint32_t y, volatile uint32_t *p, uint32_t dma_addr, uint32_t w, void *ctx) {
    (void)ctx;
    img_stats_t *st = &img_stats;
    volatile uint32_t *tiles = IMG_VM(img_trl_mem) + IMG_TRL_TILE0 + (y >> 4) * (w >> 4);
    const int gray = (img_fmt == IMG_FMT_GRAY);
    uint32_t x = 0;
    for (uint32_t tx = 0; tx < (w >> 4); tx++) {
        uint32_t cnt = 0;
        for (uint32_t k = 0; k < 16; k++, x++) {
            const uint32_t word = p[x];
            uint32_t v = word & 0xFFu;
            if (!gray) {
                const uint32_t g = (word >> 8) & 0xFFu;
                const uint32_t b = (word >> 16) & 0xFFu;
                if (g > v) {
                    v = g;
                }
                if (b > v) {
                    v = b;
                }
            }
            if ((int32_t)v > st->max_v) {
                st->max_v = (int32_t)v;
                st->max_x = (int32_t)x;
                st->max_y = (int32_t)y;
            }
            if ((int32_t)v < st->min_v) {
                st->min_v = (int32_t)v;
                st->min_x = (int32_t)x;
                st->min_y = (int32_t)y;
            }
            if (v) {
                cnt++;
            }
            st->sum += v;
        }
        if (cnt) {
            st->nz += cnt;
            tiles[tx] += cnt;
        }
    }
    img_dma_out(dma_addr, w);
}

static void img_send_trailer(const img_job_t *job) {
    volatile uint32_t *t = IMG_VM(img_trl_mem);
    const uint32_t tw = job->w >> 4;
    const uint32_t th = (job->h + 15) >> 4;
    const uint32_t nt = tw * th;
    uint32_t cnt = 0;
    uint32_t tx0 = 0xFFFFu, ty0 = 0xFFFFu, tx1 = 0, ty1 = 0;
    for (uint32_t i = 0; i < nt; i++) {
        const uint32_t s = t[IMG_TRL_TILE0 + i];
        if (s && s >= job->roi_thr) {
            const uint32_t tx = i % tw;
            const uint32_t ty = i / tw;
            cnt++;
            tx0 = (tx < tx0) ? tx : tx0;
            ty0 = (ty < ty0) ? ty : ty0;
            tx1 = (tx > tx1) ? tx : tx1;
            ty1 = (ty > ty1) ? ty : ty1;
        }
    }
    t[0] = IMG_TRL_MAGIC | (IMG_STATS_WORDS + nt);
    t[1] = (uint32_t)img_stats.max_v;
    t[2] = (uint32_t)img_stats.max_x;
    t[3] = (uint32_t)img_stats.max_y;
    t[4] = (uint32_t)img_stats.min_v;
    t[5] = (uint32_t)img_stats.min_x;
    t[6] = (uint32_t)img_stats.min_y;
    t[7] = img_stats.nz;
    t[8] = img_stats.sum;
    t[9] = cnt;
    if (cnt) {
        uint32_t x1 = (tx1 + 1) * 16;
        uint32_t y1 = (ty1 + 1) * 16;
        t[10] = tx0 * 16;
        t[11] = ty0 * 16;
        t[12] = ((x1 < job->w) ? x1 : job->w) - 1;
        t[13] = ((y1 < job->h) ? y1 : job->h) - 1;
    } else {
        t[10] = t[11] = t[12] = t[13] = 0xFFFFu;
    }
    (void)t[13];
    img_dma_out(VMEM_DMA_ADDRESS(img_trl_mem), IMG_TRL_TILE0 + nt);
}

unsigned img_job_check(const img_job_t *job) {
    img_stage_t tmp[IMG_MAX_STAGES];
    if (img_op_stages(job->op, job->fmt, job->thr, tmp) == 0) {
        return IMG_ERR_OP;
    }
    if (job->w == 0 || job->h == 0 || (job->w & 15) || job->w > IMG_MAX_W) {
        return IMG_ERR_SIZE;
    }
    if ((job->w >> 4) * ((job->h + 15) >> 4) > IMG_MAX_TILES) {
        return IMG_ERR_TILES;
    }
    return 0;
}

unsigned img_job_parse(const uint32_t hdr[3], img_job_t *job) {
    job->op = hdr[0] & 0xFFu;
    job->fmt = (hdr[0] >> 8) & 1u;
    job->border = (hdr[0] >> 9) & 1u;
    job->w = hdr[1] & 0xFFFFu;
    job->h = hdr[1] >> 16;
    job->thr = hdr[2] & 0xFFu;
    job->roi_thr = (hdr[2] >> 8) & 0xFFu;
    if ((hdr[0] & 0xFFFF0000u) != IMG_HDR_MAGIC) {
        return IMG_ERR_HDR;
    }
    return img_job_check(job);
}

static void img_send_header(const img_job_t *job, unsigned err) {
    volatile uint32_t *o = IMG_VM(img_hout_mem);
    o[0] = IMG_HDR_MAGIC | job->border << 9 | job->fmt << 8 | job->op;
    o[1] = job->h << 16 | job->w;
    o[2] = job->thr | job->roi_thr << 8;
    o[3] = IMG_ERR_MAGIC | err;
    (void)o[3];
    img_dma_out(VMEM_DMA_ADDRESS(img_hout_mem), err ? 4 : 3);
}

void img_stream_job(const img_job_t *job, unsigned err) {
    uint32_t t0, t1;
    CSR_READ(TIMER_VALUE, t0);
    img_dma_out_idle();   // header and trailer buffers are free
    img_send_header(job, err);

    if (err) {
        if (err != IMG_ERR_HDR) {
            // drain the job's pixels to stay in sync with the stream
            uint32_t left = job->w * job->h;
            while (left) {
                const uint32_t n = (left > IMG_RING_SLOTS * IMG_SLOT_WORDS) ? IMG_RING_SLOTS * IMG_SLOT_WORDS : left;
                img_dma_in(VMEM_DMA_ADDRESS(img_ring_mem), n);
                left -= n;
            }
        }
    } else {
        img_stage_t st[IMG_MAX_STAGES];
        const unsigned nst = img_op_stages(job->op, job->fmt, job->thr, st);
        const uint32_t nt = (job->w >> 4) * ((job->h + 15) >> 4);
        volatile uint32_t *tiles = IMG_VM(img_trl_mem) + IMG_TRL_TILE0;
        for (uint32_t i = 0; i < nt; i++) {
            tiles[i] = 0;
        }
        img_stats.max_v = -1;
        img_stats.min_v = 256;
        img_stats.max_x = img_stats.max_y = img_stats.min_x = img_stats.min_y = 0;
        img_stats.nz = img_stats.sum = 0;
        img_fmt = job->fmt;
        img_run_stages(st, nst, job->w, job->h, job->border,
                       img_stream_line_in, img_stream_line_out, 0);
        img_send_trailer(job);
    }
    CSR_READ(TIMER_VALUE, t1);
    img_cycles = t1 - t0;
}

unsigned img_stream_loop(void) {
    unsigned jobs = 0;
    uint32_t hdr[3];
    img_job_t job;
    while (1) {
        img_dma_in(VMEM_DMA_ADDRESS(img_hin_mem), 3);
        volatile uint32_t *h = IMG_VM(img_hin_mem);
        hdr[0] = h[0];
        hdr[1] = h[1];
        hdr[2] = h[2];
        const unsigned err = img_job_parse(hdr, &job);
        if (err != IMG_ERR_HDR && job.op == IMG_OP_END) {
            img_dma_out_idle();
            img_send_header(&job, 0);
            img_dma_out_idle();
            return jobs;
        }
        img_stream_job(&job, err);
        jobs++;
    }
}
