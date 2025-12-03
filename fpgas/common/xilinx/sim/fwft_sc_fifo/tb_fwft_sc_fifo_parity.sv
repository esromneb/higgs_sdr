module tb_fwft_sc_fifo_parity;

  localparam int DEPTH = 16;
  localparam int WIDTH = 8;
  localparam int ALMOST_FULL = 11;
  localparam int EFFECTIVE_CAPACITY = DEPTH + 2;

  logic clk = 0;
  always #5 clk = ~clk;

  logic             rst;
  logic             wren;
  logic [WIDTH-1:0] wdata;
  logic             full;
  logic             o_afull;
  logic             rden;
  logic [WIDTH-1:0] rdata;
  logic             rdata_vld;
  logic             o_afull_n;
  logic             o_afull_n_d;
  logic [31:0]      fillcount;

  logic [WIDTH-1:0] expected_q[$];
  logic [WIDTH-1:0] held_data;
  bit held_valid;
  int cycle = 0;
  int errors = 0;
  int fd;

  fwft_sc_fifo #(
      .DEPTH(DEPTH),
      .WIDTH(WIDTH),
      .ALMOST_FULL(ALMOST_FULL)
  ) dut (
      .clk(clk),
      .rst(rst),
      .wren(wren),
      .wdata(wdata),
      .full(full),
      .o_afull(o_afull),
      .rden(rden),
      .rdata(rdata),
      .rdata_vld(rdata_vld),
      .o_afull_n(o_afull_n),
      .o_afull_n_d(o_afull_n_d),
      .fillcount(fillcount)
  );

  task automatic fail(input string message);
    errors++;
    $display("MISMATCH cycle=%0d: %s", cycle, message);
  endtask

  task automatic step(input bit i_rst, input bit i_wren, input bit i_rden,
                      input logic [WIDTH-1:0] i_wdata);
    bit pre_valid;
    bit pre_full;
    bit pre_afull_n;
    logic [WIDTH-1:0] pre_data;
    logic [31:0] pre_fillcount;
    logic [WIDTH-1:0] expected_front;

    @(negedge clk);
    rst = i_rst;
    wren = i_wren;
    rden = i_rden;
    wdata = i_wdata;
    pre_valid = rdata_vld;
    pre_full = full;
    pre_afull_n = o_afull_n;
    pre_data = rdata;
    pre_fillcount = fillcount;

    @(posedge clk);
    #1;
    cycle++;

    if (i_rst) begin
      expected_q.delete();
      held_valid = 0;
    end else begin
      if (pre_valid && i_rden) begin
        if (expected_q.size() == 0) begin
          fail("read handshake occurred with an empty scoreboard");
        end else begin
          expected_front = expected_q.pop_front();
          if (pre_data !== expected_front)
            fail($sformatf("consumed payload expected=0x%0h got=0x%0h",
                           expected_front, pre_data));
        end
      end

      if (i_wren && !pre_full)
        expected_q.push_back(i_wdata);

      if (expected_q.size() > EFFECTIVE_CAPACITY)
        fail($sformatf("accepted occupancy %0d exceeds effective capacity %0d",
                       expected_q.size(), EFFECTIVE_CAPACITY));

      if (rdata_vld) begin
        if (expected_q.size() == 0) begin
          fail("rdata_vld asserted with an empty scoreboard");
        end else if (rdata !== expected_q[0]) begin
          fail($sformatf("presented payload expected=0x%0h got=0x%0h",
                         expected_q[0], rdata));
        end
      end

      if (held_valid && !i_rden) begin
        if (!rdata_vld)
          fail("rdata_vld dropped while output was backpressured");
        else if (rdata !== held_data)
          fail($sformatf("rdata changed under backpressure expected=0x%0h got=0x%0h",
                         held_data, rdata));
      end

      if (o_afull !== (pre_fillcount >= ALMOST_FULL))
        fail($sformatf("o_afull expected=%0d for prior fillcount=%0d got=%0d",
                       pre_fillcount >= ALMOST_FULL, pre_fillcount, o_afull));
      if (o_afull_n !== (pre_fillcount < ALMOST_FULL))
        fail($sformatf("o_afull_n expected=%0d for prior fillcount=%0d got=%0d",
                       pre_fillcount < ALMOST_FULL, pre_fillcount, o_afull_n));
      if (o_afull_n_d !== pre_afull_n)
        fail($sformatf("o_afull_n_d expected prior o_afull_n=%0d got=%0d",
                       pre_afull_n, o_afull_n_d));

      held_valid = rdata_vld;
      held_data = rdata;
    end

    $fdisplay(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
              cycle, i_rst, i_wren, i_rden, i_wdata, rdata, rdata_vld,
              full, o_afull, o_afull_n, o_afull_n_d, fillcount);
  endtask

  task automatic wait_for_valid(input int timeout);
    int waited;
    waited = 0;
    while (!rdata_vld && waited < timeout) begin
      step(0, 0, 0, 0);
      waited++;
    end
    if (!rdata_vld)
      fail($sformatf("timed out waiting %0d cycles for FWFT output", timeout));
  endtask

  logic [31:0] lfsr = 32'h6d2b_79f5;
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
    string trace_path;
    if (!$value$plusargs("TRACE=%s", trace_path))
      trace_path = "trace.csv";
    fd = $fopen(trace_path, "w");
    if (fd == 0)
      $fatal(1, "unable to open trace file %s", trace_path);
    $fdisplay(fd, "cycle,rst,wren,rden,wdata,rdata,rdata_vld,full,o_afull,o_afull_n,o_afull_n_d,fillcount");

    rst = 1;
    wren = 0;
    rden = 0;
    wdata = 0;
    held_valid = 0;
    repeat (3) step(1, 0, 0, 0);
    step(0, 0, 0, 0);

    // Single-word FWFT and output stability under backpressure.
    step(0, 1, 0, 8'ha5);
    wait_for_valid(5);
    repeat (4) step(0, 0, 0, 0);
    step(0, 0, 1, 0);

    // Bursty writes followed by a read stream with deliberate valid gaps.
    for (int i = 0; i < 8; i++)
      step(0, 1, 0, 8'h20 + i[7:0]);
    for (int i = 0; i < 24; i++)
      step(0, 0, (i % 3) != 0, 0);

    // Fill without reads. The wrapper can hold two prefetched words in
    // addition to the DEPTH entries in its backing FIFO.
    while (!full && expected_q.size() <= EFFECTIVE_CAPACITY)
      step(0, 1, 0, 8'h80 + expected_q.size());
    if (!full)
      fail("full did not assert at the bounded capacity");
    if (expected_q.size() != EFFECTIVE_CAPACITY)
      fail($sformatf("full asserted at occupancy %0d, expected %0d",
                     expected_q.size(), EFFECTIVE_CAPACITY));

    while (expected_q.size() != 0)
      step(0, 0, 1, 0);
    repeat (3) step(0, 0, 1, 0);
    if (rdata_vld)
      fail("rdata_vld remained asserted after complete drain");

    // Simultaneous traffic at steady state.
    for (int i = 0; i < 6; i++)
      step(0, 1, 0, 8'h40 + i[7:0]);
    wait_for_valid(5);
    for (int i = 0; i < 64; i++)
      step(0, 1, 1, 8'hc0 + i[7:0]);

    // Reset while buffered transactions are in flight.
    for (int i = 0; i < 5; i++)
      step(0, 1, 0, 8'he0 + i[7:0]);
    step(1, 0, 0, 0);
    step(0, 0, 0, 0);
    if (rdata_vld)
      fail("rdata_vld did not clear across reset");

    // Deterministic fuzz. Writes are suppressed when full, while reads are
    // allowed in any cycle; reading without valid data is a defined no-op at
    // this wrapper boundary.
    for (int i = 0; i < 5000; i++) begin
      logic [31:0] r;
      bit do_reset;
      bit do_write;
      r = next_lfsr();
      do_reset = (r[11:2] == 10'h3ff);
      do_write = r[0] && !full && !do_reset;
      step(do_reset, do_write, r[1] && !do_reset, r[23:16]);
      if (do_reset)
        step(0, 0, 0, 0);
    end

    while (expected_q.size() != 0)
      step(0, 0, 1, 0);
    repeat (3) step(0, 0, 1, 0);

    $fclose(fd);
    if (errors != 0)
      $fatal(1, "FAIL: fwft_sc_fifo had %0d mismatches", errors);
    $display("PASS: fwft_sc_fifo preserves ordering, FWFT, backpressure, capacity, and reset behavior");
    $finish;
  end

endmodule
