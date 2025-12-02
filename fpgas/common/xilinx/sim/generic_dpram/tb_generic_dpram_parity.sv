// XSIM testbench for `generic_dpram`
// (libs/ip-library/fwft_fifos/sc_fifo/hdl/generic_dpram.v).
//
// This leaf has no separate Xilinx implementation and no reset pin (real
// block RAM contents are undefined until written), so it is tested the same
// way as `scalar_memory`: directed vectors (full-depth write, full-depth
// read-back, same-address read/write collisions, an idle-cycle
// write-to-currently-latched-read-address glitch-forwarding case) plus a
// deterministic fuzz test, self-checked every cycle against a small,
// independently-written shadow model, with the DUT's own CSV trace also
// diffed against the Verilator run via ../compare_traces.py.

module tb_generic_dpram_parity;

  localparam int AW = 4;
  localparam int DW = 8;
  localparam int DEPTH = 1 << AW;

  logic clk = 0;
  always #5 clk = ~clk;

  logic rce;
  logic [AW-1:0] raddr;
  logic [DW-1:0] dout;
  logic wce;
  logic we;
  logic [AW-1:0] waddr;
  logic [DW-1:0] di;

  generic_dpram #(
      .aw(AW),
      .dw(DW)
  ) dut (
      .rclk (clk),
      .rce  (rce),
      .raddr(raddr),
      .dout (dout),
      .wclk (clk),
      .wce  (wce),
      .we   (we),
      .waddr(waddr),
      .di   (di)
  );

  // Independent shadow model: mirrors only the two documented update rules
  // (registered read address latch, registered write, asynchronous
  // continuous read of the addressed cell) rather than re-deriving them
  // from the DUT's own source text.
  logic [DW-1:0] shadow_mem [0:DEPTH-1];
  logic [AW-1:0] shadow_read_addr;
  logic          read_addr_valid;
  logic [DW-1:0] expected_dout;
  int errors = 0;
  int cycle = 0;

  int fd;

  initial begin
    fd = $fopen("trace.csv", "w");
    $fdisplay(fd, "cycle,rce,wce,we,raddr,waddr,di,dout");
  end

  task automatic step();
    @(posedge clk);
    #1;
    cycle++;
    // Update shadow model from the state that was just latched/written.
    if (wce && we) shadow_mem[waddr] = di;
    if (rce) begin
      shadow_read_addr = raddr;
      read_addr_valid  = 1'b1;
    end
    expected_dout = shadow_mem[shadow_read_addr];
    // read_addr is a genuinely-undefined register in real hardware/XSIM
    // until the first rce pulse latches it (Verilator zero-initializes
    // instead, the same benign init-convention difference already
    // documented for memory_slice), so dout is a don't-care until then.
    if (read_addr_valid && expected_dout !== dout) begin
      errors++;
      $display("MISMATCH cycle=%0d rce=%0d wce=%0d we=%0d raddr=%0d waddr=%0d di=%0d dout=%0d expected=%0d",
                cycle, rce, wce, we, raddr, waddr, di, dout, expected_dout);
    end
    $fdisplay(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
              cycle, rce, wce, we, raddr, waddr, di, dout);
  endtask

  task automatic drive(input bit i_rce, input bit i_wce, input bit i_we,
                       input int i_raddr, input int i_waddr, input int i_di);
    rce   = i_rce;
    wce   = i_wce;
    we    = i_we;
    raddr = i_raddr[AW-1:0];
    waddr = i_waddr[AW-1:0];
    di    = i_di[DW-1:0];
    step();
  endtask

  // Simple xorshift-style LFSR for a deterministic fuzz sequence.
  logic [31:0] lfsr = 32'hACE1_2024;
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
    for (int a = 0; a < DEPTH; a++) shadow_mem[a] = '0;
    shadow_read_addr = '0;
    read_addr_valid = 1'b0;
    rce = 0; wce = 0; we = 0; raddr = '0; waddr = '0; di = '0;

    // Phase A: write every address with a known pattern, no reads.
    for (int a = 0; a < DEPTH; a++) begin
      drive(1'b0, 1'b1, 1'b1, a, a, (a * 7 + 3) & 8'hFF);
    end

    // Phase B: read every address back in order.
    for (int a = 0; a < DEPTH; a++) begin
      drive(1'b1, 1'b0, 1'b0, a, 0, 0);
    end
    drive(1'b0, 1'b0, 1'b0, 0, 0, 0); // flush final latched read

    // Phase C: same-cycle read/write collisions, same address.
    for (int a = 0; a < DEPTH; a++) begin
      drive(1'b1, 1'b1, 1'b1, a, a, 8'hA0 + a[3:0]);
    end
    drive(1'b0, 1'b0, 1'b0, 0, 0, 0);

    // Phase D: same-cycle read/write, different (non-colliding) addresses.
    drive(1'b1, 1'b1, 1'b1, 0, 8, 8'h55);
    drive(1'b1, 1'b1, 1'b1, 8, 0, 8'hAA);
    drive(1'b0, 1'b0, 1'b0, 0, 0, 0);

    // Phase E: idle-cycle write-to-currently-latched-read-address glitch
    // forwarding case: latch a read address (rce=1), then, while rce=0
    // (address held), write new data to that exact address and confirm the
    // asynchronous read passes it through in the same cycle it is written.
    drive(1'b1, 1'b0, 1'b0, 3, 0, 0);        // latch read_addr = 3
    drive(1'b0, 1'b1, 1'b1, 0, 3, 8'hDE);    // write addr 3 while rce=0
    drive(1'b0, 1'b0, 1'b0, 0, 0, 0);        // idle, dout should hold 0xDE
    drive(1'b0, 1'b1, 1'b1, 0, 3, 8'hEF);    // write addr 3 again while idle
    drive(1'b0, 1'b0, 1'b0, 0, 0, 0);

    // Phase F: wce gating (write enable qualified by chip enable).
    drive(1'b1, 1'b0, 1'b0, 5, 0, 0);        // latch read_addr = 5
    drive(1'b0, 1'b0, 1'b1, 0, 5, 8'h11);    // wce=0: must NOT write
    drive(1'b0, 1'b0, 1'b0, 0, 0, 0);        // dout should show old data
    drive(1'b0, 1'b1, 1'b1, 0, 5, 8'h22);    // wce=1: writes now
    drive(1'b0, 1'b0, 1'b0, 0, 0, 0);        // dout should show 0x22

    // Phase G: deterministic fuzz.
    for (int i = 0; i < 2000; i++) begin
      automatic logic [31:0] r = next_lfsr();
      drive(r[0], r[1], r[2], r[7:4], r[11:8], r[23:16]);
    end

    if (errors == 0) $display("PASS: generic_dpram matches independent shadow model");
    else $display("FAIL: %0d mismatches", errors);
    $fclose(fd);
    $finish;
  end

endmodule
