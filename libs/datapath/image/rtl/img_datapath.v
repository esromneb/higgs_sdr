// Image kernel datapath for the Higgs Q-engine (piston).
//
// Replaces the 16I/16Q complex FFT datapath when HIGGS_IMG_DATAPATH is
// defined. Bit-exact contract: doc/kernel/NOTES.md section 5. Reference
// model: libs/datapath/image/img_model.py (class Datapath).
//
// One beat = one k8 row (64 u8 pixels) joined with one k9 row
// (coefficients + FIRST/LAST/CENTER flags). Each of the 64 byte-lanes has two
// u8 x s8 multipliers feeding 24-bit accumulators A and B, a MIN/MAX register
// M and a centre-capture register C. On a LAST beat the post stage
// (combine -> round/shift -> offset -> saturate -> threshold/peak -> lane
// mask) produces one k1 row.
//
// Pipeline (global stall, adv = output empty or accepted):
//   S0 input regs (pixels, selected coefficients, flags, cfg)
//   S1 products          S2 accumulate / min-max / centre
//   S3 combine           S4 round + shift + offset
//   S5 saturate + threshold/peak + lane mask = k1 output register
// The k1 row is valid 5 clocks after the LAST beat is accepted (no stalls).
// The config (k14 words 0,1) is sampled with each beat and travels down the
// pipeline with it, so a k14 update never affects rows already in flight.

module img_datapath (
    input  wire         clk,
    input  wire         reset_n,

    input  wire [511:0] t_k8_dat,
    input  wire         t_k8_req,
    output wire         t_k8_ack,

    input  wire [511:0] t_k9_dat,
    input  wire         t_k9_req,
    output wire         t_k9_ack,

    /* verilator lint_off UNUSED */
    input  wire [511:0] t_k14_dat,    // only words 0 and 1 are used
    /* verilator lint_on UNUSED */
    input  wire         t_k14_req,
    output wire         t_k14_ack,

    output wire [511:0] i_k1_dat,
    output wire         i_k1_req,
    input  wire         i_k1_ack
);

// ---------------------------------------------------------------------------
// config: {offset[15:0], w0[23:0]}
// ---------------------------------------------------------------------------
localparam CW = 40;

reg [CW-1:0] cfg;
always @(posedge clk or negedge reset_n)
    if (~reset_n)       cfg <= {CW{1'b0}};
    else if (t_k14_req) cfg <= {t_k14_dat[47:32], t_k14_dat[23:0]};

assign t_k14_ack = 1'b1;

// field accessors (pass a CW-bit config vector)
`define IMG_OP(c)      c[1:0]
`define IMG_COMB(c)    c[3:2]
`define IMG_SHIFT(c)   c[7:4]
`define IMG_RND(c)     c[8]
`define IMG_THR_EN(c)  c[9]
`define IMG_PEAK_EN(c) c[10]
`define IMG_PERLANE(c) c[11]
`define IMG_MASK(c)    c[15:12]
`define IMG_THR(c)     c[23:16]
`define IMG_OFFSET(c)  c[39:24]

// ---------------------------------------------------------------------------
// pipeline control
// ---------------------------------------------------------------------------
reg v0, v1, last2, v3, v4, v5;
wire adv  = ~v5 | i_k1_ack;
wire take = adv & t_k8_req & t_k9_req;

assign t_k8_ack = take;
assign t_k9_ack = take;
assign i_k1_req = v5;

reg [2:0] fl0, fl1;       // {CENTER, LAST, FIRST} from slice 0
reg [CW-1:0] cfg0, cfg1, cfg2, cfg3;
/* verilator lint_off UNUSED */
reg [CW-1:0] cfg4;                 // only the S5 fields are used
/* verilator lint_on UNUSED */

always @(posedge clk or negedge reset_n)
    if (~reset_n) begin
        v0 <= 1'b0; v1 <= 1'b0; last2 <= 1'b0; v3 <= 1'b0; v4 <= 1'b0; v5 <= 1'b0;
        fl0 <= 3'b0; fl1 <= 3'b0;
        cfg0 <= {CW{1'b0}}; cfg1 <= {CW{1'b0}}; cfg2 <= {CW{1'b0}};
        cfg3 <= {CW{1'b0}}; cfg4 <= {CW{1'b0}};
    end else if (adv) begin
        v0    <= t_k8_req & t_k9_req;
        fl0   <= t_k9_dat[26:24];
        cfg0  <= cfg;
        v1    <= v0;
        fl1   <= fl0;
        cfg1  <= cfg0;
        last2 <= v1 & fl1[1];
        cfg2  <= cfg1;
        v3    <= last2;
        cfg3  <= cfg2;
        v4    <= v3;
        cfg4  <= cfg3;
        v5    <= v4;
    end

wire acc_en = adv & v1;

// ---------------------------------------------------------------------------
// 64 lanes
// ---------------------------------------------------------------------------
genvar s, b;
generate
    for (s = 0; s < 16; s = s + 1) begin : g_slice
        wire [31:0] w = t_k9_dat[32*s +: 32];
        for (b = 0; b < 4; b = b + 1) begin : g_lane
            wire [7:0] ca_in = `IMG_PERLANE(cfg) ? ((b < 3) ? w[8*b +: 8] : 8'd0) : w[7:0];
            wire [7:0] cb_in = `IMG_PERLANE(cfg) ? 8'd0 : w[15:8];
            img_lane u_lane (
                .clk      (clk),
                .adv      (adv),
                .acc_en   (acc_en),
                .p_in     (t_k8_dat[32*s + 8*b +: 8]),
                .ca_in    (ca_in),
                .cb_in    (cb_in),
                .first1   (fl1[0]),
                .center1  (fl1[2]),
                .is_min1  (`IMG_OP(cfg1) == 2'd1),
                .comb2    (`IMG_COMB(cfg2)),
                .rnd3     (`IMG_RND(cfg3)),
                .shift3   (`IMG_SHIFT(cfg3)),
                .offset3  (`IMG_OFFSET(cfg3)),
                .is_mac4  (`IMG_OP(cfg4) == 2'd0),
                .peak4    (`IMG_PEAK_EN(cfg4)),
                .thr_en4  (`IMG_THR_EN(cfg4)),
                .thr4     (`IMG_THR(cfg4)),
                .lane_en4 (cfg4[12 + b]),
                .out5     (i_k1_dat[32*s + 8*b +: 8])
            );
        end
    end
endgenerate

`undef IMG_OP
`undef IMG_COMB
`undef IMG_SHIFT
`undef IMG_RND
`undef IMG_THR_EN
`undef IMG_PEAK_EN
`undef IMG_PERLANE
`undef IMG_MASK
`undef IMG_THR
`undef IMG_OFFSET

endmodule


/* verilator lint_off DECLFILENAME */
// One byte-lane: S0..S5 data registers. All registers advance on adv; the
// accumulator/min-max/centre registers only on acc_en (adv with a valid S1).
module img_lane (
    input  wire              clk,
    input  wire              adv,
    input  wire              acc_en,
    input  wire        [7:0] p_in,
    input  wire        [7:0] ca_in,
    input  wire        [7:0] cb_in,
    input  wire              first1,
    input  wire              center1,
    input  wire              is_min1,
    input  wire        [1:0] comb2,
    input  wire              rnd3,
    input  wire        [3:0] shift3,
    input  wire       [15:0] offset3,
    input  wire              is_mac4,
    input  wire              peak4,
    input  wire              thr_en4,
    input  wire        [7:0] thr4,
    input  wire              lane_en4,
    output reg         [7:0] out5
);

// S0
reg        [7:0] p0;
reg signed [7:0] ca0, cb0;
always @(posedge clk) if (adv) begin
    p0  <= p_in;
    ca0 <= ca_in;
    cb0 <= cb_in;
end

// S1: u8 x s8 products
(* use_dsp = "yes" *) reg signed [16:0] pa1;
(* use_dsp = "yes" *) reg signed [16:0] pb1;
reg [7:0] p1;
reg       nz1;
always @(posedge clk) if (adv) begin
    pa1 <= $signed({1'b0, p0}) * ca0;
    pb1 <= $signed({1'b0, p0}) * cb0;
    p1  <= p0;
    nz1 <= |ca0;
end

// S2: accumulate (24-bit wrapping), min/max, centre
(* use_dsp = "yes" *) reg signed [23:0] acc_a2;
(* use_dsp = "yes" *) reg signed [23:0] acc_b2;
reg [7:0] m2, c2;
wire signed [23:0] pa1x = {{7{pa1[16]}}, pa1};
wire signed [23:0] pb1x = {{7{pb1[16]}}, pb1};
wire [7:0] m_cur = first1 ? (is_min1 ? 8'hFF : 8'h00) : m2;
wire [7:0] m_red = is_min1 ? ((p1 < m_cur) ? p1 : m_cur)
                           : ((p1 > m_cur) ? p1 : m_cur);
always @(posedge clk) if (acc_en) begin
    acc_a2 <= first1 ? pa1x : acc_a2 + pa1x;
    acc_b2 <= first1 ? pb1x : acc_b2 + pb1x;
    m2     <= nz1 ? m_red : m_cur;
    if (center1) c2 <= p1;
end

// S3: combine (26-bit signed)
wire signed [25:0] a2x = {{2{acc_a2[23]}}, acc_a2};
wire signed [25:0] b2x = {{2{acc_b2[23]}}, acc_b2};
wire signed [25:0] abs_a = acc_a2[23] ? -a2x : a2x;
wire signed [25:0] abs_b = acc_b2[23] ? -b2x : b2x;
reg  signed [25:0] comb;
always @* begin
    case (comb2)
        2'd0:    comb = a2x;
        2'd1:    comb = abs_a;
        2'd2:    comb = abs_a + abs_b;
        default: comb = (abs_a > abs_b) ? abs_a : abs_b;
    endcase
end

reg signed [25:0] sum3;
reg        [7:0]  m3, c3;
always @(posedge clk) if (adv) begin
    sum3 <= comb;
    m3   <= m2;
    c3   <= c2;
end

// S4: round, arithmetic shift, offset (27-bit signed)
wire signed [26:0] sum3x = {sum3[25], sum3};
wire signed [26:0] rnd_v = (rnd3 && shift3 != 4'd0) ? (27'sd1 <<< (shift3 - 4'd1)) : 27'sd0;
wire signed [26:0] shv   = (sum3x + rnd_v) >>> shift3;
wire signed [26:0] off_x = {{11{offset3[15]}}, offset3};

reg signed [26:0] val4;
reg        [7:0]  m4, c4;
always @(posedge clk) if (adv) begin
    val4 <= shv + off_x;
    m4   <= m3;
    c4   <= c3;
end

// S5: saturate, select, threshold / peak, lane mask
wire [7:0] sat  = val4[26] ? 8'd0 : (|val4[25:8]) ? 8'd255 : val4[7:0];
wire [7:0] v    = is_mac4 ? sat : m4;
wire [7:0] pk   = (c4 == v && c4 >= thr4) ? c4 : 8'd0;
wire [7:0] th   = (v >= thr4) ? 8'd255 : 8'd0;

always @(posedge clk) if (adv)
    out5 <= ~lane_en4 ? 8'd0 : peak4 ? pk : thr_en4 ? th : v;

endmodule
/* verilator lint_on DECLFILENAME */
