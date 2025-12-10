#!/usr/bin/env python3
"""Bit-exact fixed-point model of the Higgs image-kernel datapath.

Spec: doc/kernel/NOTES.md (section 5 is the datapath contract, section 7 is
the test stream format). The model is pure Python with no numpy, so it runs
anywhere the Makefiles run.

There are two model levels, and ``selftest`` cross-checks them:

* ``Datapath``: beat level. Each call takes one k8 row (16 x u32) and one k9
  row (16 x u32), exactly like the RTL, and returns a k1 row on LAST. It
  generates and checks the RTL unit-test vectors.
* ``run_stage`` / ``run_job``: image level. They apply a kernel stage to an
  image with the same border rules as the C library, and compute the feature
  statistics / ROI trailer. They produce the expected cs22 output stream for
  sim/verilator/test_image_1.

CLI:
  img_model.py selftest
  img_model.py gen-unit   OUT.txt [--seed N] [--seqs N]
  img_model.py gen-stream IN.hex EXPECT.hex
  img_model.py compare    EXPECT.hex GOT.hex
"""

import argparse
import io
import sys

# --------------------------------------------------------------------------
# constants (NOTES section 5)
# --------------------------------------------------------------------------
OP_MAC, OP_MIN, OP_MAX = 0, 1, 2
COMB_A, COMB_ABS_A, COMB_L1, COMB_MAXABS = 0, 1, 2, 3
F_FIRST, F_LAST, F_CENTER = 1 << 24, 1 << 25, 1 << 26

FMT_GRAY, FMT_RGBX = 0, 1
BORDER_ZERO, BORDER_REPLICATE = 0, 1

HDR_MAGIC = 0x1A6E0000
TRL_MAGIC = 0x5A7A0000
OP_END = 0xFF

SLICES = 16
LANES = 64
ACC_BITS = 24


def s8(v):
    v &= 0xFF
    return v - 256 if v & 0x80 else v


def wrap_signed(v, bits):
    m = 1 << bits
    v &= m - 1
    return v - m if v & (m >> 1) else v


# --------------------------------------------------------------------------
# config / coefficient words
# --------------------------------------------------------------------------
class Cfg:
    """Datapath config: words 0 and 1 of the k14 row."""

    __slots__ = ("op", "comb", "shift", "rnd", "thr_en", "peak_en",
                 "perlane", "lane_mask", "thr", "offset")

    def __init__(self, op=OP_MAC, comb=COMB_A, shift=0, rnd=False,
                 thr_en=False, peak_en=False, perlane=False, lane_mask=0x1,
                 thr=0, offset=0):
        self.op, self.comb, self.shift, self.rnd = op, comb, shift, rnd
        self.thr_en, self.peak_en, self.perlane = thr_en, peak_en, perlane
        self.lane_mask, self.thr, self.offset = lane_mask, thr, offset

    def words(self):
        w0 = ((self.op & 3) | (self.comb & 3) << 2 | (self.shift & 15) << 4 |
              int(bool(self.rnd)) << 8 | int(bool(self.thr_en)) << 9 |
              int(bool(self.peak_en)) << 10 | int(bool(self.perlane)) << 11 |
              (self.lane_mask & 15) << 12 | (self.thr & 0xFF) << 16)
        return [w0, self.offset & 0xFFFF]

    def row(self):
        return self.words() + [0] * 14

    @classmethod
    def from_words(cls, w0, w1):
        return cls(op=w0 & 3, comb=(w0 >> 2) & 3, shift=(w0 >> 4) & 15,
                   rnd=bool(w0 >> 8 & 1), thr_en=bool(w0 >> 9 & 1),
                   peak_en=bool(w0 >> 10 & 1), perlane=bool(w0 >> 11 & 1),
                   lane_mask=(w0 >> 12) & 15, thr=(w0 >> 16) & 0xFF,
                   offset=wrap_signed(w1, 16))


def coef_word(ca=0, cb=0, flags=0, c2=0):
    """Build a coefficient word. In normal mode ca and cb are broadcast to
    every lane. In per-lane mode ca, cb and c2 are the cA values for lanes 0,
    1 and 2."""
    return (ca & 0xFF) | (cb & 0xFF) << 8 | (c2 & 0xFF) << 16 | flags


# --------------------------------------------------------------------------
# lane arithmetic shared by both model levels
# --------------------------------------------------------------------------
def lane_coefs(word, byte, perlane):
    if perlane:
        return (s8(word >> (8 * byte)) if byte < 3 else 0), 0
    return s8(word), s8(word >> 8)


def lane_step(cfg, first, ca, cb, p, a, b, m):
    """One tap for one lane. Returns the new (a, b, m)."""
    if cfg.op == OP_MAC:
        a = wrap_signed(p * ca + (0 if first else a), ACC_BITS)
        b = wrap_signed(p * cb + (0 if first else b), ACC_BITS)
    elif cfg.op in (OP_MIN, OP_MAX):
        is_min = cfg.op == OP_MIN
        cur = (255 if is_min else 0) if first else m
        if ca != 0:
            cur = min(cur, p) if is_min else max(cur, p)
        m = cur
    # op 3 is reserved and behaves like MAC in the RTL; not modelled
    return a, b, m


def post_process(cfg, a, b, m, c):
    """Return the u8 result for one lane. The caller applies the lane mask."""
    if cfg.op == OP_MAC:
        if cfg.comb == COMB_A:
            v = a
        elif cfg.comb == COMB_ABS_A:
            v = abs(a)
        elif cfg.comb == COMB_L1:
            v = abs(a) + abs(b)
        else:
            v = max(abs(a), abs(b))
        if cfg.rnd and cfg.shift:
            v += 1 << (cfg.shift - 1)
        v >>= cfg.shift          # python >> is an arithmetic (floor) shift
        v += cfg.offset
        v = 0 if v < 0 else 255 if v > 255 else v
    else:
        v = m
    if cfg.peak_en:
        v = c if (c == v and c >= cfg.thr) else 0
    elif cfg.thr_en:
        v = 255 if v >= cfg.thr else 0
    return v


# --------------------------------------------------------------------------
# beat-level model (mirrors the RTL)
# --------------------------------------------------------------------------
class Datapath:
    """64-lane beat model. FIRST, LAST and CENTER come from slice 0's word.
    Coefficients come from each slice's own word."""

    def __init__(self):
        self.cfg = Cfg()
        self.a = [0] * LANES
        self.b = [0] * LANES
        self.m = [0] * LANES
        self.c = [0] * LANES

    def config(self, row):
        self.cfg = Cfg.from_words(row[0], row[1])

    def beat(self, k8, k9):
        """Take one beat (k8 and k9 are 16 x u32). Returns the 16 x u32 k1
        row on LAST, else None."""
        cfg = self.cfg
        fl = k9[0]
        first, last, center = bool(fl & F_FIRST), bool(fl & F_LAST), bool(fl & F_CENTER)
        for s in range(SLICES):
            for byte in range(4):
                lane = 4 * s + byte
                p = (k8[s] >> (8 * byte)) & 0xFF
                ca, cb = lane_coefs(k9[s], byte, cfg.perlane)
                self.a[lane], self.b[lane], self.m[lane] = lane_step(
                    cfg, first, ca, cb, p, self.a[lane], self.b[lane], self.m[lane])
                if center:
                    self.c[lane] = p
        if not last:
            return None
        out = []
        for s in range(SLICES):
            word = 0
            for byte in range(4):
                lane = 4 * s + byte
                if cfg.lane_mask >> byte & 1:
                    v = post_process(cfg, self.a[lane], self.b[lane], self.m[lane], self.c[lane])
                    word |= v << (8 * byte)
            out.append(word)
        return out


# --------------------------------------------------------------------------
# kernels and the op table (NOTES sections 2 and 3)
# --------------------------------------------------------------------------
def outer(u, v):
    return [[a * b for b in v] for a in u]


def transpose(k):
    return [list(r) for r in zip(*k)]


def const_kernel(n, c):
    return [[c] * n for _ in range(n)]


GX = [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]]
PX = [[-1, 0, 1]] * 3
SX = [[-3, 0, 3], [-10, 0, 10], [-3, 0, 3]]
G3 = outer([1, 2, 1], [1, 2, 1])
G5 = outer([1, 4, 6, 4, 1], [1, 4, 6, 4, 1])
G7 = outer([1, 3, 7, 10, 7, 3, 1], [1, 3, 7, 10, 7, 3, 1])

OP_COPY, OP_GAUSS3, OP_GAUSS5, OP_GAUSS7 = 0, 1, 2, 3
OP_BOX3, OP_BOX5, OP_SHARPEN, OP_UNSHARP = 4, 5, 6, 7
OP_LAPLACE, OP_SOBEL, OP_SOBEL_X, OP_PREWITT = 8, 9, 10, 11
OP_SCHARR, OP_EMBOSS, OP_ERODE3, OP_DILATE3 = 12, 13, 14, 15
OP_CUSTOM, OP_CHAN_GAUSS = 16, 17
OP_EDGES, OP_PEAKS = 32, 33

OP_NAMES = {
    OP_COPY: "COPY", OP_GAUSS3: "GAUSS3", OP_GAUSS5: "GAUSS5",
    OP_GAUSS7: "GAUSS7", OP_BOX3: "BOX3", OP_BOX5: "BOX5",
    OP_SHARPEN: "SHARPEN", OP_UNSHARP: "UNSHARP", OP_LAPLACE: "LAPLACE",
    OP_SOBEL: "SOBEL", OP_SOBEL_X: "SOBEL_X", OP_PREWITT: "PREWITT",
    OP_SCHARR: "SCHARR", OP_EMBOSS: "EMBOSS", OP_ERODE3: "ERODE3",
    OP_DILATE3: "DILATE3", OP_CHAN_GAUSS: "CHAN_GAUSS",
    OP_EDGES: "EDGES", OP_PEAKS: "PEAKS",
}


class Stage:
    """One streaming kernel pass. ka and kb are NxN s8 kernels (kb may be
    None). In per-lane mode ka is a list of 3 NxN kernels (R, G, B)."""

    def __init__(self, n, ka, kb=None, cfg=None):
        self.n, self.ka, self.kb = n, ka, kb
        self.cfg = cfg or Cfg()

    def taps(self):
        """Return [(dy, dx, coef_word)] in issue order (row-major)."""
        r = (self.n - 1) // 2
        last = self.n * self.n - 1
        out = []
        for t in range(self.n * self.n):
            i, j = divmod(t, self.n)
            dy, dx = i - r, j - r
            fl = (F_FIRST if t == 0 else 0) | (F_LAST if t == last else 0)
            if dy == 0 and dx == 0:
                fl |= F_CENTER
            if self.cfg.perlane:
                w = coef_word(self.ka[0][i][j], self.ka[1][i][j], fl, self.ka[2][i][j])
            else:
                w = coef_word(self.ka[i][j], self.kb[i][j] if self.kb else 0, fl)
            out.append((dy, dx, w))
        return out


def op_stages(op, fmt, thr=0):
    """Return the list of Stages for a stream op id."""
    lm = 0x1 if fmt == FMT_GRAY else 0x7

    def mac(**kw):
        return Cfg(op=OP_MAC, lane_mask=lm, **kw)

    sobel = mac(comb=COMB_L1, shift=2, rnd=True)
    table = {
        OP_COPY: lambda: [Stage(1, [[1]], cfg=mac())],
        OP_GAUSS3: lambda: [Stage(3, G3, cfg=mac(shift=4, rnd=True))],
        OP_GAUSS5: lambda: [Stage(5, G5, cfg=mac(shift=8, rnd=True))],
        OP_GAUSS7: lambda: [Stage(7, G7, cfg=mac(shift=10, rnd=True))],
        OP_BOX3: lambda: [Stage(3, const_kernel(3, 114), cfg=mac(shift=10, rnd=True))],
        OP_BOX5: lambda: [Stage(5, const_kernel(5, 82), cfg=mac(shift=11, rnd=True))],
        OP_SHARPEN: lambda: [Stage(3, [[0, -1, 0], [-1, 5, -1], [0, -1, 0]], cfg=mac())],
        OP_UNSHARP: lambda: [Stage(3, [[-1, -2, -1], [-2, 28, -2], [-1, -2, -1]],
                                   cfg=mac(shift=4, rnd=True))],
        OP_LAPLACE: lambda: [Stage(3, [[0, 1, 0], [1, -4, 1], [0, 1, 0]],
                                   cfg=mac(comb=COMB_ABS_A))],
        OP_SOBEL: lambda: [Stage(3, GX, transpose(GX), cfg=sobel)],
        OP_SOBEL_X: lambda: [Stage(3, GX, cfg=mac(comb=COMB_ABS_A, shift=2, rnd=True))],
        OP_PREWITT: lambda: [Stage(3, PX, transpose(PX), cfg=sobel)],
        OP_SCHARR: lambda: [Stage(3, SX, transpose(SX), cfg=mac(comb=COMB_L1, shift=4, rnd=True))],
        OP_EMBOSS: lambda: [Stage(3, [[-2, -1, 0], [-1, 1, 1], [0, 1, 2]], cfg=mac(offset=128))],
        OP_ERODE3: lambda: [Stage(3, const_kernel(3, 1), cfg=Cfg(op=OP_MIN, lane_mask=lm))],
        OP_DILATE3: lambda: [Stage(3, const_kernel(3, 1), cfg=Cfg(op=OP_MAX, lane_mask=lm))],
        OP_CHAN_GAUSS: lambda: [Stage(3, [[[2 * v for v in r] for r in G3], G3, const_kernel(3, 0)],
                                      cfg=mac(shift=4, rnd=True, perlane=True))],
        OP_EDGES: lambda: [Stage(3, GX, transpose(GX),
                                 cfg=mac(comb=COMB_L1, shift=2, rnd=True, thr_en=True, thr=thr))],
        OP_PEAKS: lambda: [Stage(3, GX, transpose(GX), cfg=sobel),
                           Stage(3, const_kernel(3, 1),
                                 cfg=Cfg(op=OP_MAX, peak_en=True, thr=thr, lane_mask=lm))],
    }
    if op not in table:
        raise ValueError("unknown op %d" % op)
    return table[op]()


# --------------------------------------------------------------------------
# image-level model. An image is H rows of W u32 pixel words.
# --------------------------------------------------------------------------
def fetch(img, y, x, border):
    h, w = len(img), len(img[0])
    if border == BORDER_REPLICATE:
        return img[min(max(y, 0), h - 1)][min(max(x, 0), w - 1)]
    if 0 <= y < h and 0 <= x < w:
        return img[y][x]
    return 0


def run_stage(img, stage, border):
    """Apply one stage to an image, pixel by pixel. This is the reference
    that the chunked beat model and the hardware must match."""
    h, w = len(img), len(img[0])
    taps = stage.taps()
    cfg = stage.cfg
    out = []
    for y in range(h):
        row = []
        for x in range(w):
            a, b, m, c = [0] * 4, [0] * 4, [0] * 4, [0] * 4
            for dy, dx, cw in taps:
                pw = fetch(img, y + dy, x + dx, border)
                first = bool(cw & F_FIRST)
                for byte in range(4):
                    p = (pw >> (8 * byte)) & 0xFF
                    ca, cb = lane_coefs(cw, byte, cfg.perlane)
                    a[byte], b[byte], m[byte] = lane_step(cfg, first, ca, cb, p, a[byte], b[byte], m[byte])
                    if cw & F_CENTER:
                        c[byte] = p
            word = 0
            for byte in range(4):
                if cfg.lane_mask >> byte & 1:
                    word |= post_process(cfg, a[byte], b[byte], m[byte], c[byte]) << (8 * byte)
            row.append(word)
        out.append(row)
    return out


def run_stage_beats(img, stage, border):
    """Evaluate a stage the way the C library schedules it on the hardware:
    16-pixel chunks, one Datapath.beat per tap."""
    h, w = len(img), len(img[0])
    dp = Datapath()
    dp.config(stage.cfg.row())
    taps = stage.taps()
    out = []
    for y in range(h):
        row = []
        for j in range(w // 16):
            res = None
            for dy, dx, cw in taps:
                k8 = [fetch(img, y + dy, 16 * j + s + dx, border) for s in range(16)]
                res = dp.beat(k8, [cw] * 16)
            row.extend(res)
        out.append(row)
    return out


def pixel_value(word, fmt):
    if fmt == FMT_GRAY:
        return word & 0xFF
    return max(word & 0xFF, (word >> 8) & 0xFF, (word >> 16) & 0xFF)


def stats_trailer(img, fmt, roi_thr):
    h, w = len(img), len(img[0])
    max_v, max_x, max_y = -1, 0, 0
    min_v, min_x, min_y = 256, 0, 0
    nz, total = 0, 0
    tw, th = (w + 15) // 16, (h + 15) // 16
    tiles = [0] * (tw * th)
    for y in range(h):
        for x in range(w):
            v = pixel_value(img[y][x], fmt)
            if v > max_v:
                max_v, max_x, max_y = v, x, y
            if v < min_v:
                min_v, min_x, min_y = v, x, y
            if v:
                nz += 1
                tiles[(y // 16) * tw + x // 16] += 1
            total += v
    roi = [(i % tw, i // tw) for i, s in enumerate(tiles) if s and s >= roi_thr]
    if roi:
        x0 = min(t[0] for t in roi) * 16
        y0 = min(t[1] for t in roi) * 16
        x1 = min(w, (max(t[0] for t in roi) + 1) * 16) - 1
        y1 = min(h, (max(t[1] for t in roi) + 1) * 16) - 1
    else:
        x0 = y0 = x1 = y1 = 0xFFFF
    body = [max_v, max_x, max_y, min_v, min_x, min_y, nz, total & 0xFFFFFFFF,
            len(roi), x0, y0, x1, y1] + tiles
    return [TRL_MAGIC | len(body)] + body


def header_words(op, fmt, border, w, h, thr, roi_thr):
    return [HDR_MAGIC | (border & 1) << 9 | (fmt & 1) << 8 | (op & 0xFF),
            (h & 0xFFFF) << 16 | (w & 0xFFFF),
            (thr & 0xFF) | (roi_thr & 0xFF) << 8]


def run_job(img, op, fmt, border, thr=0, roi_thr=0):
    """Return (output image, output stream words) for one job."""
    cur = img
    for st in op_stages(op, fmt, thr):
        cur = run_stage(cur, st, border)
    words = header_words(op, fmt, border, len(img[0]), len(img), thr, roi_thr)
    for row in cur:
        words.extend(row)
    words.extend(stats_trailer(cur, fmt, roi_thr))
    return cur, words


# --------------------------------------------------------------------------
# synthetic test scenes
# --------------------------------------------------------------------------
class Lcg:
    def __init__(self, seed):
        self.s = seed & 0xFFFFFFFF

    def next(self):
        self.s = (1664525 * self.s + 1013904223) & 0xFFFFFFFF
        return self.s >> 16


def scene_channel(w, h, seed, rect, disc, line_v):
    """A gradient background with a rectangle, a disc, an optional diagonal
    line (x == 2y) and +-8 LCG noise."""
    rng = Lcg(seed)
    x0, y0, x1, y1, rv = rect
    cx, cy, cr, dv = disc
    img = []
    for y in range(h):
        row = []
        for x in range(w):
            v = (x * 160) // max(1, w - 1) + 20
            if x0 <= x <= x1 and y0 <= y <= y1:
                v = rv
            if (x - cx) ** 2 + (y - cy) ** 2 <= cr * cr:
                v = dv
            if line_v is not None and x == 2 * y:
                v = line_v
            v += (rng.next() % 17) - 8
            row.append(0 if v < 0 else 255 if v > 255 else v)
        img.append(row)
    return img


def scene(w, h, fmt, seed=1):
    if fmt == FMT_GRAY:
        return scene_channel(w, h, seed, (8, 4, 23, 13, 250), (44, 12, 6, 5), 0)
    r = scene_channel(w, h, seed, (4, 3, 13, 9, 240), (22, 8, 4, 30), 0)
    g = scene_channel(w, h, seed + 1, (10, 6, 25, 12, 10), (6, 11, 3, 220), 255)
    b = scene_channel(w, h, seed + 2, (2, 1, 29, 4, 200), (26, 3, 2, 0), None)
    return [[r[y][x] | g[y][x] << 8 | b[y][x] << 16 for x in range(w)] for y in range(h)]


def default_jobs():
    """The job list for sim/verilator/test_image_1:
    (op, (w, h, fmt), border, thr, roi_thr)."""
    g = (64, 24, FMT_GRAY)
    c = (32, 16, FMT_RGBX)
    Z, R = BORDER_ZERO, BORDER_REPLICATE
    return [
        (OP_COPY, g, Z, 0, 0),
        (OP_GAUSS3, g, R, 0, 0),
        (OP_GAUSS5, g, Z, 0, 0),
        (OP_GAUSS7, g, R, 0, 0),
        (OP_BOX3, g, R, 0, 0),
        (OP_BOX5, g, Z, 0, 0),
        (OP_SHARPEN, g, R, 0, 0),
        (OP_UNSHARP, g, Z, 0, 0),
        (OP_LAPLACE, g, R, 0, 0),
        (OP_SOBEL, g, R, 0, 0),
        (OP_SOBEL_X, g, Z, 0, 0),
        (OP_PREWITT, g, R, 0, 0),
        (OP_SCHARR, g, Z, 0, 0),
        (OP_EMBOSS, g, R, 0, 0),
        (OP_ERODE3, g, R, 0, 0),
        (OP_DILATE3, g, Z, 0, 0),
        (OP_EDGES, g, R, 100, 24),
        (OP_PEAKS, g, R, 80, 4),
        (OP_GAUSS3, c, R, 0, 0),
        (OP_SOBEL, c, Z, 0, 0),
        (OP_CHAN_GAUSS, c, R, 0, 0),
        (OP_EDGES, c, R, 90, 16),
    ]


def build_streams(jobs=None):
    jobs = default_jobs() if jobs is None else jobs
    inp, exp = [], []
    for i, (op, (w, h, fmt), border, thr, roi) in enumerate(jobs):
        img = scene(w, h, fmt, seed=7 + i)
        inp.extend(header_words(op, fmt, border, w, h, thr, roi))
        for row in img:
            inp.extend(row)
        exp.extend(run_job(img, op, fmt, border, thr, roi)[1])
    end = header_words(OP_END, 0, 0, 0, 0, 0, 0)
    return inp + end, exp + end


# --------------------------------------------------------------------------
# RTL unit-test vectors
# --------------------------------------------------------------------------
def gen_unit_vectors(path, seed=1, n_seq=60):
    """Write the vector file for the standalone RTL test.

    Each line is space-separated hex:
      C w0 w1                  config row (the other 14 words are zero)
      B k8[0..15] k9[0..15]    one beat
      E k1[0..15]              expected output row after the previous B
    """
    rng = Lcg(seed)
    dp = Datapath()
    configs = []
    for op in (OP_MAC, OP_MIN, OP_MAX):
        for comb in range(4):
            configs.append(Cfg(op=op, comb=comb, shift=rng.next() % 16,
                               rnd=bool(rng.next() & 1), lane_mask=rng.next() & 15,
                               thr=rng.next() & 0xFF, offset=wrap_signed(rng.next(), 10)))
    configs += [
        Cfg(op=OP_MAC, comb=COMB_L1, shift=2, rnd=True, thr_en=True, thr=77, lane_mask=0xF),
        Cfg(op=OP_MAX, peak_en=True, thr=40, lane_mask=0xF),
        Cfg(op=OP_MIN, peak_en=True, thr=0, lane_mask=0x7),
        Cfg(op=OP_MAC, perlane=True, shift=3, rnd=True, lane_mask=0xF),
        Cfg(op=OP_MAC, comb=COMB_A, shift=0, offset=-300, lane_mask=0xF),
        Cfg(op=OP_MAC, comb=COMB_MAXABS, shift=15, rnd=True, lane_mask=0xF),
        Cfg(op=OP_MAC, comb=COMB_L1, shift=15, rnd=True, offset=32767, lane_mask=0xF),
        Cfg(op=OP_MAC, comb=COMB_A, shift=1, rnd=True, offset=-32768, lane_mask=0xF),
    ]
    lines = []
    for i in range(n_seq):
        cfg = configs[i % len(configs)]
        dp.config(cfg.row())
        lines.append("C %08x %08x" % tuple(cfg.words()))
        ntaps = [1, 2, 9, 25, 49, 81][rng.next() % 6]
        extreme = (i % 7 == 3)
        for t in range(ntaps):
            fl = (F_FIRST if t == 0 else 0) | (F_LAST if t == ntaps - 1 else 0)
            if rng.next() % 5 == 0:
                fl |= F_CENTER
            k8, k9 = [], []
            for s in range(16):
                if extreme:
                    ca, cb, c2 = -128, 127, -128
                    k8.append(0xFFFFFFFF)
                else:
                    ca, cb, c2 = rng.next() & 0xFF, rng.next() & 0xFF, rng.next() & 0xFF
                    if cfg.op != OP_MAC and rng.next() % 6 == 0:
                        ca = 0
                    k8.append((rng.next() << 16 | rng.next()) & 0xFFFFFFFF)
                # flags only matter in slice 0; randomise them elsewhere
                k9.append(coef_word(ca, cb, fl if s == 0 else (rng.next() & 7) << 24, c2))
            res = dp.beat(k8, k9)
            lines.append("B " + " ".join("%08x" % v for v in k8 + k9))
            if res is not None:
                lines.append("E " + " ".join("%08x" % v for v in res))
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return len(lines)


# --------------------------------------------------------------------------
# stream files and compare
# --------------------------------------------------------------------------
def write_hex(path, words):
    with open(path, "w") as f:
        for v in words:
            f.write("%08x\n" % (v & 0xFFFFFFFF))


def read_hex(path):
    out = []
    with open(path) as f:
        for line in f:
            line = line.split("#")[0].strip()
            if line:
                out.append(int(line, 16))
    return out


def compare_streams(exp, got, out=sys.stdout):
    """Compare job by job and print a readable report. Returns True when the
    streams are identical."""
    ok = True
    i = job = 0
    while i < len(exp):
        op = exp[i] & 0xFF
        if op == OP_END:
            if got[i:i + 3] != exp[i:i + 3]:
                out.write("END marker mismatch at word %d\n" % i)
                ok = False
            break
        fmt = (exp[i] >> 8) & 1
        wd, ht = exp[i + 1] & 0xFFFF, exp[i + 1] >> 16
        n = 3 + wd * ht
        n_all = n + 1 + (exp[i + n] & 0xFFFF)
        e, g = exp[i:i + n_all], got[i:i + n_all]
        name = "%-10s %s %dx%d" % (OP_NAMES.get(op, str(op)), "rgbx" if fmt else "gray", wd, ht)
        if e == g:
            out.write("job %2d %s: PASS\n" % (job, name))
        else:
            ok = False
            bad = [k for k in range(n_all) if k >= len(g) or e[k] != g[k]]
            out.write("job %2d %s: FAIL (%d/%d words differ)\n" % (job, name, len(bad), n_all))
            for k in bad[:8]:
                if k < 3:
                    where = "hdr[%d]" % k
                elif k < n:
                    where = "pix(%d,%d)" % ((k - 3) % wd, (k - 3) // wd)
                else:
                    where = "trl[%d]" % (k - n)
                out.write("   word %d %s exp %08x got %s\n" % (
                    i + k, where, e[k], "%08x" % g[k] if k < len(g) else "<missing>"))
        i += n_all
        job += 1
    if len(got) != len(exp):
        out.write("length mismatch: expected %d words, got %d\n" % (len(exp), len(got)))
        ok = False
    return ok


# --------------------------------------------------------------------------
# self test
# --------------------------------------------------------------------------
def selftest():
    fails = []

    def check(cond, msg):
        if not cond:
            fails.append(msg)
            print("FAIL:", msg)

    c = Cfg(op=OP_MAX, comb=3, shift=13, rnd=True, thr_en=True, peak_en=True,
            perlane=True, lane_mask=0xA, thr=0x5C, offset=-77)
    check(Cfg.from_words(*c.words()).words() == c.words(), "cfg round trip")

    img = scene(32, 8, FMT_RGBX, 3)
    out = run_stage(img, op_stages(OP_COPY, FMT_RGBX)[0], BORDER_ZERO)
    check(out == img, "copy")

    # vertical step edge: |Gx| at x=7,8 is 4*200 = 800, (800+2)>>2 = 200
    step = [[(0 if x < 8 else 200) for x in range(16)] for _ in range(4)]
    s = run_stage(step, op_stages(OP_SOBEL, FMT_GRAY)[0], BORDER_REPLICATE)
    check(s[1][7] == 200 and s[1][8] == 200 and s[1][3] == 0 and s[1][12] == 0,
          "sobel step %r" % s[1])

    flat = [[123] * 16 for _ in range(5)]
    for op in (OP_GAUSS3, OP_GAUSS5, OP_GAUSS7, OP_BOX3, OP_BOX5, OP_COPY):
        g = run_stage(flat, op_stages(op, FMT_GRAY)[0], BORDER_REPLICATE)
        check(all(v == 123 for r in g for v in r), "flat %s" % OP_NAMES[op])
    for op in (OP_SOBEL, OP_LAPLACE, OP_SCHARR, OP_PREWITT):
        g = run_stage(flat, op_stages(op, FMT_GRAY)[0], BORDER_REPLICATE)
        check(all(v == 0 for r in g for v in r), "flat %s is zero" % OP_NAMES[op])
    g = run_stage(flat, op_stages(OP_EMBOSS, FMT_GRAY)[0], BORDER_REPLICATE)
    check(all(v == 251 for r in g for v in r), "emboss flat = 123+128")

    dot = [[0] * 16 for _ in range(5)]
    dot[2][5] = 99
    d = run_stage(dot, op_stages(OP_DILATE3, FMT_GRAY)[0], BORDER_ZERO)
    check(sum(v == 99 for r in d for v in r) == 9, "dilate")
    check(run_stage(d, op_stages(OP_ERODE3, FMT_GRAY)[0], BORDER_ZERO) == dot,
          "erode(dilate(dot)) == dot")
    p = run_stage(d, op_stages(OP_PEAKS, FMT_GRAY, 50)[1], BORDER_ZERO)
    check(sum(v == 99 for r in p for v in r) == 9, "plateau keeps all peaks")
    p = run_stage(d, op_stages(OP_PEAKS, FMT_GRAY, 100)[1], BORDER_ZERO)
    check(all(v == 0 for r in p for v in r), "peak below thr suppressed")

    # beat model == image model for every op, both formats, both borders
    for fmt, (w, h) in ((FMT_GRAY, (32, 9)), (FMT_RGBX, (16, 7))):
        img = scene(w, h, fmt, 5)
        for op in OP_NAMES:
            for border in (BORDER_ZERO, BORDER_REPLICATE):
                cur_a = cur_b = img
                for st in op_stages(op, fmt, 60):
                    cur_a = run_stage(cur_a, st, border)
                    cur_b = run_stage_beats(cur_b, st, border)
                check(cur_a == cur_b, "beat vs image %s fmt=%d border=%d" % (OP_NAMES[op], fmt, border))

    # 81 taps of 255*-128 fits in 24 bits without wrapping
    dp = Datapath()
    dp.config(Cfg(op=OP_MAC, comb=COMB_A, shift=15, lane_mask=0xF).row())
    for t in range(81):
        fl = (F_FIRST if t == 0 else 0) | (F_LAST if t == 80 else 0)
        dp.beat([0xFFFFFFFF] * 16, [coef_word(-128, 127, fl)] * 16)
    check(dp.a[0] == -128 * 255 * 81 and dp.b[0] == 127 * 255 * 81, "headroom")

    # the ROI box is clipped to the image
    img = [[0] * 40 for _ in range(20)]
    img[19][39] = 1
    t = stats_trailer(img, FMT_GRAY, 1)
    check(t[9:14] == [1, 32, 16, 39, 19], "roi clip %r" % t[9:14])
    check(stats_trailer([[0] * 16], FMT_GRAY, 0)[9:14] == [0, 0xFFFF] * 1 + [0xFFFF] * 3, "no roi")

    inp, exp = build_streams(default_jobs()[:2])
    check(compare_streams(exp, list(exp), io.StringIO()), "compare identity")
    bad = list(exp)
    bad[10] ^= 1
    check(not compare_streams(exp, bad, io.StringIO()), "compare detects a diff")

    print("selftest: %s (%d failures)" % ("PASS" if not fails else "FAIL", len(fails)))
    return not fails


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("selftest")
    p = sub.add_parser("gen-unit")
    p.add_argument("out")
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--seqs", type=int, default=60)
    p = sub.add_parser("gen-stream")
    p.add_argument("inp")
    p.add_argument("expect")
    p = sub.add_parser("compare")
    p.add_argument("expect")
    p.add_argument("got")
    a = ap.parse_args(argv)
    if a.cmd == "selftest":
        return 0 if selftest() else 1
    if a.cmd == "gen-unit":
        print("wrote %d vector lines to %s" % (gen_unit_vectors(a.out, a.seed, a.seqs), a.out))
        return 0
    if a.cmd == "gen-stream":
        inp, exp = build_streams()
        write_hex(a.inp, inp)
        write_hex(a.expect, exp)
        print("wrote %d input words, %d expected words" % (len(inp), len(exp)))
        return 0
    ok = compare_streams(read_hex(a.expect), read_hex(a.got))
    print("RESULT: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
