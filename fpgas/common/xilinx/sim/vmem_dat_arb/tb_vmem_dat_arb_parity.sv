`timescale 1ns/1ps

module tb_vmem_dat_arb_parity;
  localparam int TRANSACTIONS = 512;
  logic clk = 0;
  always #5 clk = ~clk;

  logic resetn;
  logic return_valid;
  logic return_ready;
  logic [3:0] return_slice;
  logic [1:0] return_dma;
  logic [31:0] return_data;
  logic order_valid;
  logic order_ready;
  logic [1:0] order_dma;
  logic [3:0] order_slice;
  logic [3:0] out_valid;
  logic [3:0] out_ready;
  logic [127:0] out_data;

  int order_q[4][$];
  logic [31:0] data_q[4][16][$];
  int order_index;
  int return_index;
  int completed;
  int cycle;
  int errors;
  int fd;
  logic [31:0] lfsr = 32'h91e1_0da5;

  vmem_dat_arb_test_top dut (.*);

  function automatic logic [31:0] tx_data(input int index);
    return 32'ha500_0000 | index;
  endfunction

  function automatic int tx_dma(input int index);
    return (index * 3 + 1) & 3;
  endfunction

  function automatic int tx_slice(input int index);
    return (index * 5 + 7) & 15;
  endfunction

  function automatic logic [31:0] next_lfsr();
    logic [31:0] x;
    x = lfsr;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    lfsr = x;
    return x;
  endfunction

  task automatic fail(input string message);
    errors++;
    $display("MISMATCH cycle=%0d: %s", cycle, message);
  endtask

  task automatic check_outputs();
    for (int dma = 0; dma < 4; dma++) begin
      bit expected_valid;
      logic [31:0] expected_data;
      expected_valid = order_q[dma].size() != 0
                       && data_q[dma][order_q[dma][0]].size() != 0;
      expected_data = expected_valid ? data_q[dma][order_q[dma][0]][0] : 0;
      if (out_valid[dma] !== expected_valid)
        fail($sformatf("dma%0d valid expected=%0d got=%0d",
                       dma, expected_valid, out_valid[dma]));
      if (expected_valid && out_data[dma*32 +: 32] !== expected_data)
        fail($sformatf("dma%0d data expected=0x%08x got=0x%08x",
                       dma, expected_data, out_data[dma*32 +: 32]));
    end
  endtask

  initial begin
    string trace_path;
    if (!$value$plusargs("TRACE=%s", trace_path))
      trace_path = "trace.csv";
    fd = $fopen(trace_path, "w");
    $fdisplay(fd, "cycle,resetn,order_valid,order_ready,order_dma,order_slice,return_valid,return_ready,return_dma,return_slice,return_data,out_ready,out_valid,out0,out1,out2,out3");

    resetn = 0;
    return_valid = 0;
    order_valid = 0;
    out_ready = 0;
    return_slice = 0;
    return_dma = 0;
    return_data = 0;
    order_dma = 0;
    order_slice = 0;
    repeat (4) @(posedge clk);
    @(negedge clk);
    resetn = 1;

    while (completed < TRANSACTIONS) begin
      logic [31:0] random_bits;
      logic [3:0] output_fire;
      bit order_fire;
      bit return_fire;
      random_bits = next_lfsr();

      if (!order_valid && order_index < TRANSACTIONS && random_bits[0]) begin
        order_valid = 1;
        order_dma = tx_dma(order_index);
        order_slice = tx_slice(order_index);
      end

      if (!return_valid && return_index < TRANSACTIONS && random_bits[1]) begin
        return_valid = 1;
        return_dma = tx_dma(return_index);
        return_slice = tx_slice(return_index);
        return_data = tx_data(return_index);
      end

      out_ready = random_bits[5:2];
      #1;
      check_outputs();
      output_fire = out_valid & out_ready;
      order_fire = order_valid && order_ready;
      return_fire = return_valid && return_ready;
      @(posedge clk);
      #1;
      cycle++;

      if (order_fire) begin
        order_q[order_dma].push_back(order_slice);
        order_index++;
        order_valid = 0;
      end
      if (return_fire) begin
        data_q[return_dma][return_slice].push_back(return_data);
        return_index++;
        return_valid = 0;
      end

      for (int dma = 0; dma < 4; dma++) begin
        if (output_fire[dma]) begin
          void'(data_q[dma][order_q[dma][0]].pop_front());
          void'(order_q[dma].pop_front());
          completed++;
        end
      end
      check_outputs();

      $fdisplay(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0h,%0h,%0h,%0h,%0h,%0h",
                cycle, resetn, order_valid, order_ready, order_dma, order_slice,
                return_valid, return_ready, return_dma, return_slice, return_data,
                out_ready, out_valid, out_data[31:0], out_data[63:32],
                out_data[95:64], out_data[127:96]);

      if (cycle > 20000)
        $fatal(1, "timeout");
    end

    repeat (4) begin
      out_ready = 4'hf;
      @(posedge clk);
      #1;
      cycle++;
      check_outputs();
    end

    $fclose(fd);
    if (errors != 0)
      $fatal(1, "FAIL: %0d VMEM arbiter mismatches", errors);
    $display("PASS: VMEM arbiter preserved 512 ordered transactions under independent input and output stalls");
    $finish;
  end
endmodule
