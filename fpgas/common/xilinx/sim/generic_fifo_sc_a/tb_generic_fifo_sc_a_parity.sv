// XSIM testbench for `generic_fifo_sc_a`
// (libs/ip-library/fwft_fifos/sc_fifo/hdl/generic_fifo_sc_a.v).
//
// This is the actual FIFO storage leaf used by `fwft_sc_fifo` /
// `pmi_fifo_sc_fwft_v1_0` (in the committed CS12 manifest), and it
// internally instantiates `generic_dpram` (separately proven correct by its
// own harness). It has no separate Xilinx implementation, so it is tested
// the same way as `muladdsub`/`alu54b_wrapper`: a single shared RTL
// implementation, self-checked every cycle against an independent,
// hand-written control-plane model (write/read pointers, guard bits, fill
// count, threshold flags), covering only *defined* transactions (writing
// while full or reading while empty is explicitly documented by the RTL as
// leaving the FIFO in an undefined state, so the fuzz generator gates `we`
// on `!full` and `re` on `!empty`, per the repo's existing "RAM behavior
// compared through defined transactions" convention). `dout`'s correctness
// is left to the separate `generic_dpram` harness, since it is forwarded
// unmodified from that leaf; this harness still traces it for
// cross-simulator CSV comparison.
module tb_generic_fifo_sc_a_parity;

  localparam int DW = 8;
  localparam int AW = 4;
  localparam int N = 4;
  localparam int ALMOST_FULL = 5;
  localparam int MAX_SIZE = 1 << AW;

  logic clk = 0;
  always #5 clk = ~clk;

  logic        rst; // active LOW
  logic        clr; // active HIGH, synchronous
  logic [DW-1:0] din;
  logic        we;
  logic [DW-1:0] dout;
  logic        re;
  logic        full, afull, afull_n, o_afull_n_d, empty;
  logic        full_r, empty_r;
  logic        full_n, empty_n, full_n_r, empty_n_r;
  logic [1:0]  level;
  logic [31:0] fillcount;

  generic_fifo_sc_a #(
      .dw(DW),
      .aw(AW),
      .n(N),
      .ALMOST_FULL(ALMOST_FULL)
  ) dut (
      .clk        (clk),
      .rst        (rst),
      .clr        (clr),
      .din        (din),
      .we         (we),
      .dout       (dout),
      .re         (re),
      .full       (full),
      .afull      (afull),
      .afull_n    (afull_n),
      .o_afull_n_d(o_afull_n_d),
      .empty      (empty),
      .full_r     (full_r),
      .empty_r    (empty_r),
      .full_n     (full_n),
      .empty_n    (empty_n),
      .full_n_r   (full_n_r),
      .empty_n_r  (empty_n_r),
      .level      (level),
      .fillcount  (fillcount)
  );

  // ---- Independent control-plane shadow model ----
  logic [AW-1:0] m_wp, m_rp;
  logic          m_gb, m_gb2;
  logic [AW:0]   m_cnt;
  logic          m_full_r, m_empty_r, m_full_n_r, m_empty_n_r;
  logic [31:0]   m_fillcount;
  logic          m_afull, m_afull_n, m_o_afull_n_d, m_temp;
  logic          m_full, m_empty, m_full_n, m_empty_n;
  logic [1:0]    m_level;

  task automatic model_reset();
    m_wp = '0; m_rp = '0; m_gb = 0; m_gb2 = 0; m_cnt = '0;
    m_full_r = 0; m_empty_r = 1; m_full_n_r = 0; m_empty_n_r = 1;
    m_fillcount = 0; m_afull = 0; m_afull_n = 0; m_o_afull_n_d = 0; m_temp = 0;
  endtask

  task automatic model_update(input bit i_rst, input bit i_clr, input bit i_we,
                               input bit i_re);
    // Capture pre-edge ("old") state before computing any new state, to
    // mirror the RTL's parallel nonblocking-assignment update semantics
    // (every always block reads the same pre-edge register values).
    logic [AW-1:0] o_wp = m_wp, o_rp = m_rp;
    logic          o_gb = m_gb, o_gb2 = m_gb2;
    logic [AW:0]   o_cnt = m_cnt;
    logic [31:0]   o_fillcount = m_fillcount;
    logic          o_temp = m_temp;
    logic [AW-1:0] wp_pl1 = o_wp + 1'b1;
    logic [AW-1:0] wp_pl2 = o_wp + 2'b10;
    logic [AW-1:0] rp_pl1 = o_rp + 1'b1;

    if (!i_rst) begin
      model_reset();
      return;
    end

    if (i_clr) begin
      m_wp = '0; m_rp = '0; m_gb = 0; m_gb2 = 0; m_cnt = '0;
      m_full_r = 0; m_empty_r = 1; m_full_n_r = 0; m_empty_n_r = 1;
      // NOTE: fillcount/afull/afull_n/o_afull_n_d/temp deliberately do NOT
      // respond to clr in the RTL (only to rst) -- a discovered asymmetry,
      // documented in the README and faithfully reproduced here rather
      // than "fixed".
    end else begin
      if (wp_pl1 == o_rp && i_we) m_gb = 1'b1;
      else if (i_re) m_gb = 1'b0;

      if (wp_pl2 == o_rp && i_we) m_gb2 = 1'b1;
      else if (o_wp != o_rp && i_re) m_gb2 = 1'b0;

      if (i_we) m_wp = wp_pl1;
      if (i_re) m_rp = rp_pl1;

      if (i_re && !i_we) m_cnt = o_cnt - 1'b1;
      else if (!i_re && i_we) m_cnt = o_cnt + 1'b1;

      if (i_we && (wp_pl1 == o_rp) && o_gb2 && !i_re) m_full_r = 1'b1;
      else if (i_re && ((wp_pl1 != o_rp) || !o_gb2) && !i_we) m_full_r = 1'b0;

      if (i_we && ((o_wp != rp_pl1) || o_gb2) && !i_re) m_empty_r = 1'b0;
      else if (i_re && ((o_wp == rp_pl1) && !o_gb2) && !i_we) m_empty_r = 1'b1;

      if (i_we && (o_cnt >= (N - 1)) && !i_re) m_empty_n_r = 1'b0;
      else if (i_re && (o_cnt <= N) && !i_we) m_empty_n_r = 1'b1;

      if (i_we && (o_cnt >= (MAX_SIZE - N)) && !i_re) m_full_n_r = 1'b1;
      else if (i_re && (o_cnt <= (MAX_SIZE - N + 1)) && !i_we) m_full_n_r = 1'b0;
    end

    // fillcount/afull/afull_n/o_afull_n_d/temp live in a separate always
    // block in the RTL that is gated only by rst (never clr), and whose
    // afull threshold check and o_afull_n_d both read PRE-edge register
    // values (o_fillcount, o_temp) rather than the values computed later
    // in this same step.
    if (o_fillcount >= ALMOST_FULL) begin
      m_afull = 1'b1; m_afull_n = 1'b0; m_temp = 1'b0;
    end else begin
      m_afull = 1'b0; m_afull_n = 1'b1; m_temp = 1'b1;
    end
    m_o_afull_n_d = o_temp;
    if (o_wp > o_rp) m_fillcount = o_wp - o_rp;
    else if (o_rp > o_wp) m_fillcount = (1 << AW) - o_rp + o_wp;
    else m_fillcount = 0;
  endtask

  function automatic void model_derive_outputs();
    m_full  = (m_wp == m_rp) && m_gb;
    m_empty = (m_wp == m_rp) && !m_gb;
    m_full_n  = !(m_cnt < (MAX_SIZE - N + 1));
    m_empty_n = (m_cnt < N);
    m_level = {2{m_cnt[AW]}} | m_cnt[AW-1:AW-2];
  endfunction

  int errors = 0;
  int cycle = 0;
  int fd;

  initial begin
    fd = $fopen("trace.csv", "w");
    $fdisplay(fd, "cycle,rst,clr,we,re,din,dout,full,empty,full_r,empty_r,full_n,empty_n,full_n_r,empty_n_r,level,afull,afull_n,o_afull_n_d,fillcount");
  end

  task automatic check_field(string name, logic exp, logic got);
    if (exp !== got) begin
      errors++;
      $display("MISMATCH cycle=%0d field=%s expected=%0d got=%0d", cycle, name, exp, got);
    end
  endtask

  task automatic step(input bit i_we, input bit i_re, input bit i_clr,
                       input logic [DW-1:0] i_din);
    we = i_we; re = i_re; clr = i_clr; din = i_din;
    @(posedge clk);
    #1;
    cycle++;
    model_update(rst, i_clr, i_we, i_re);
    model_derive_outputs();

    check_field("full", m_full, full);
    check_field("empty", m_empty, empty);
    check_field("full_r", m_full_r, full_r);
    check_field("empty_r", m_empty_r, empty_r);
    check_field("full_n", m_full_n, full_n);
    check_field("empty_n", m_empty_n, empty_n);
    check_field("full_n_r", m_full_n_r, full_n_r);
    check_field("empty_n_r", m_empty_n_r, empty_n_r);
    check_field("level0", m_level[0], level[0]);
    check_field("level1", m_level[1], level[1]);
    check_field("afull", m_afull, afull);
    check_field("afull_n", m_afull_n, afull_n);
    check_field("o_afull_n_d", m_o_afull_n_d, o_afull_n_d);
    if (m_fillcount !== fillcount) begin
      errors++;
      $display("MISMATCH cycle=%0d field=fillcount expected=%0d got=%0d", cycle, m_fillcount, fillcount);
    end

    $fdisplay(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
              cycle, rst, i_clr, i_we, i_re, i_din, dout, full, empty,
              full_r, empty_r, full_n, empty_n, full_n_r, empty_n_r, level,
              afull, afull_n, o_afull_n_d, fillcount);
  endtask

  logic [31:0] lfsr = 32'h1234_5678;
  function automatic logic [31:0] next_lfsr();
    logic [31:0] x;
    x = lfsr;
    x = x ^ (x << 13);
    x = x ^ (x >> 17);
    x = x ^ (x << 5);
    lfsr = x;
    return x;
  endfunction

  initial begin
    rst = 1'b0; // assert reset (active low)
    clr = 0; we = 0; re = 0; din = 0;
    model_reset();
    repeat (3) step(1'b0, 1'b0, 1'b0, 8'h00);

    rst = 1'b1; // release reset
    step(1'b0, 1'b0, 1'b0, 8'h00);

    // Phase A: fill to full.
    for (int i = 0; i < MAX_SIZE; i++) step(1'b1, 1'b0, 1'b0, 8'h10 + i[7:0]);

    // Phase B: drain to empty.
    for (int i = 0; i < MAX_SIZE; i++) step(1'b0, 1'b1, 1'b0, 8'h00);

    // Phase C: clr mid-operation (push a few, then clr, verify wp/rp/gb
    // reset but afull/fillcount do NOT, per the documented asymmetry).
    for (int i = 0; i < 6; i++) step(1'b1, 1'b0, 1'b0, 8'h20 + i[7:0]);
    step(1'b0, 1'b0, 1'b1, 8'h00); // clr pulse
    step(1'b0, 1'b0, 1'b0, 8'h00);

    // Phase D: simultaneous we&re (push+pop same cycle) at a partial fill
    // level -- net cnt should be unchanged.
    for (int i = 0; i < 4; i++) step(1'b1, 1'b0, 1'b0, 8'h30 + i[7:0]);
    for (int i = 0; i < 8; i++) step(1'b1, 1'b1, 1'b0, 8'h40 + i[7:0]);
    for (int i = 0; i < 4; i++) step(1'b0, 1'b1, 1'b0, 8'h00);

    // Phase E: cross the ALMOST_FULL threshold explicitly and observe the
    // one-cycle-lagged afull/afull_n/o_afull_n_d relationship.
    for (int i = 0; i < MAX_SIZE; i++) step(1'b1, 1'b0, 1'b0, 8'h50 + i[7:0]);
    for (int i = 0; i < MAX_SIZE; i++) step(1'b0, 1'b1, 1'b0, 8'h00);

    // Phase F: mid-run reset re-assertion.
    rst = 1'b0;
    step(1'b0, 1'b0, 1'b0, 8'h00);
    rst = 1'b1;
    step(1'b0, 1'b0, 1'b0, 8'h00);

    // Phase G: deterministic fuzz, gated to defined transactions only
    // (never write while full, never read while empty), matching this
    // repo's existing convention for undefined-behavior avoidance.
    for (int i = 0; i < 5000; i++) begin
      automatic logic [31:0] r = next_lfsr();
      automatic bit want_we = r[0];
      automatic bit want_re = r[1];
      automatic bit want_clr = (r[9:2] == 8'hFF); // rare
      automatic bit fifo_we = want_we && !full;
      automatic bit fifo_re = want_re && !empty;
      step(fifo_we, fifo_re, want_clr, r[23:16]);
    end

    if (errors == 0) $display("PASS: generic_fifo_sc_a matches independent control-plane model");
    else $display("FAIL: %0d mismatches", errors);
    $fclose(fd);
    $finish;
  end

endmodule
