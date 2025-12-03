// XSIM parity testbench for this test's actual DUT: `tb_higgs_top`
// (sim/hdl/tb_higgs_top.sv), configured identically to tb.cpp (TB_USE_CS20
// only, no TB_USE_ADC/DAC, no ETH_USE_MEGA_WRAPPER).
//
// Mirrors tb.cpp exactly:
//  - t->reset(40)                  -> RESET_CYCLES  = 40
//    IMPORTANT: HiggsHelper::reset(count) does NOT hold RESET asserted for
//    `count` full clock cycles -- `count` there is a *half-edge* (toggle)
//    counter, and it deasserts RESET when `i+2 >= count`, i.e. *before*
//    the last full cycle's rising edge. For count=40 (20 full cycles),
//    that means only the first 19 rising edges see RESET==1; RESET is
//    already 0 by the 20th (final) rising edge of the reset() call. See
//    higgs_helper.hpp:758-778. Reproduced exactly below (assert for
//    RESET_CYCLES/2-1 = 19 cycles, deassert, then let one more posedge
//    elapse with RESET already low) rather than the naive "assert for
//    RESET_CYCLES full cycles" reading of the C++ call site.
//  - postReset(top)                -> i_data_valid_adc driven to 1 right
//                                      after reset is released
//  - the `for (us = 0; us < 20000; us++) { t->tick(500); poll pc; }` loop
//    -> MAX_OUTER_ITERS = 20000, INNER_CYCLES = 500, same 3 exit PCs
//  - t->tick(500*4) flush          -> FLUSH_CYCLES  = 2000
//  - ring-bus capture gated on `ring_bus_i0_ready && ringbus_out_data_vld`,
//    printed one hex value per line in the same minimal (non-zero-padded)
//    format tb.cpp's HEX_STRING() macro produces, for direct diffing
//    against a captured Verilator run's stdout.
//
// See tb.cpp, higgs_helper.hpp (preReset/postReset/reset) and README.md
// for the full derivation of the stimulus/tie-off table below.
//
// Deliberately has no `` `timescale `` directive of its own -- see the
// vex_machine_top harness's tb_vex_machine_top_parity.sv for why (xelab
// requires every module in a design to consistently either have or lack
// a timescale, and none of the ~150 files reachable from tb_higgs_top
// declare one, aside from the patched exceptions the Makefile handles).

module tb_higgs_top_xsim;

  localparam int RESET_CYCLES    = 40;
  localparam int MAX_OUTER_ITERS = 20000;
  localparam int INNER_CYCLES    = 500;
  localparam int FLUSH_CYCLES    = 500 * 4;

  localparam logic [31:0] PC_DONE_0 = 32'hE4;
  localparam logic [31:0] PC_DONE_1 = 32'hE8;
  localparam logic [31:0] PC_DONE_2 = 32'hEC;

  logic clk = 0;
  always #5 clk = ~clk;

  logic        MIB_MASTER_RESET     = 1;

  logic [31:0] i_data_adc           = 0;
  logic        i_data_valid_adc     = 0;

  logic [31:0] tx_turnstile_data_in    = 0;
  logic        tx_turnstile_data_last  = 0;
  logic        tx_turnstile_data_valid = 0;
  wire         tx_turnstile_data_ready;

  logic [31:0] ringbus_in_data      = 0;
  logic        ringbus_in_data_vld  = 0;
  wire         ringbus_in_data_ready;

  wire         snap_eth_io_uart_txd;
  // UART RX idle state is logic-1 (mark/idle), matching tb.cpp's
  // handle_uart_neg() which does `*(serial->line_in) = 1;` every cycle
  // by default (higgs_helper.hpp ~948-951; the tb->riscv direction is
  // otherwise unused/"TBD" in this test, so it just parks the line
  // idle-high). Leaving this at 0 mimics a permanent UART break/start
  // condition, which was found (via interactive xsim probing) to cause
  // eth_top's own firmware to repeatedly re-enter its UART-triggered
  // telemetry path and flood the shared ring bus with extra
  // `queue_dma_out()` pushes (fpgas/grav/eth/c/src/main.c) alongside the
  // real, expected 8 test items -- since those extra items are always
  // interleaved between the real ones (never before the initial
  // 0xdeadbeef nor replacing the final 0xf), this bug happened to be
  // invisible to tb.cpp/this TB's own pass/fail check (first==0xdeadbeef,
  // last==0xf) but made a byte-for-byte comparison against Verilator's
  // reference dump impossible.
  logic        snap_eth_io_uart_rxd = 1;

  wire [31:0]  ringbus_out_data;
  wire         ringbus_out_data_vld;

  logic        ring_bus_i0_ready    = 1;

  wire         o_data_valid_dac;
  wire [31:0]  o_data_dac;

  wire [31:0]  snap_cs20_riscv_out_data;
  wire         snap_cs20_riscv_out_last;
  wire         snap_cs20_riscv_out_valid;
  wire         snap_cs20_riscv_out_ready;
  wire         snap_cs20_io_uart_txd;
  wire         snap_cs20_io_uart_rxd;

  logic [31:0] adc_data_out         = 0;
  logic        adc_data_out_valid   = 0;
  wire         adc_data_out_ready;

  wire [31:0]  snap_mapmov_in_data;
  wire         snap_mapmov_in_valid;
  wire         snap_mapmov_in_ready;

  wire [31:0]  o_data_eth;
  wire         o_data_valid_eth;
  wire         o_data_last_eth;

  wire [31:0]  o_rx_data_eth;
  wire         o_rx_valid_eth;
  logic        i_rx_ready_eth       = 1; // tb always asserts ready (matches Verilator control_ready=1, random_ready=false)

  wire         DAC_CTRL_SDIO;
  wire         DAC_CTRL_SDENN;
  wire         DAC_CTRL_SCLK;
  wire         DAC_CTRL_RESETN;

  tb_higgs_top dut (
    .clk                       (clk),
    .MIB_MASTER_RESET          (MIB_MASTER_RESET),

    .i_data_adc                (i_data_adc),
    .i_data_valid_adc          (i_data_valid_adc),

    .tx_turnstile_data_in      (tx_turnstile_data_in),
    .tx_turnstile_data_last    (tx_turnstile_data_last),
    .tx_turnstile_data_valid   (tx_turnstile_data_valid),
    .tx_turnstile_data_ready   (tx_turnstile_data_ready),

    .ringbus_in_data           (ringbus_in_data),
    .ringbus_in_data_vld       (ringbus_in_data_vld),
    .ringbus_in_data_ready     (ringbus_in_data_ready),

    .snap_eth_io_uart_txd      (snap_eth_io_uart_txd),
    .snap_eth_io_uart_rxd      (snap_eth_io_uart_rxd),

    .ringbus_out_data          (ringbus_out_data),
    .ringbus_out_data_vld      (ringbus_out_data_vld),

    .ring_bus_i0_ready         (ring_bus_i0_ready),

    .o_data_valid_dac          (o_data_valid_dac),
    .o_data_dac                (o_data_dac),

    .snap_cs20_riscv_out_data  (snap_cs20_riscv_out_data),
    .snap_cs20_riscv_out_last  (snap_cs20_riscv_out_last),
    .snap_cs20_riscv_out_valid (snap_cs20_riscv_out_valid),
    .snap_cs20_riscv_out_ready (snap_cs20_riscv_out_ready),
    .snap_cs20_io_uart_txd     (snap_cs20_io_uart_txd),
    .snap_cs20_io_uart_rxd     (snap_cs20_io_uart_rxd),

    .adc_data_out              (adc_data_out),
    .adc_data_out_valid        (adc_data_out_valid),
    .adc_data_out_ready        (adc_data_out_ready),

    .snap_mapmov_in_data       (snap_mapmov_in_data),
    .snap_mapmov_in_valid      (snap_mapmov_in_valid),
    .snap_mapmov_in_ready      (snap_mapmov_in_ready),

    .o_data_eth                (o_data_eth),
    .o_data_valid_eth          (o_data_valid_eth),
    .o_data_last_eth           (o_data_last_eth),

    .o_rx_data_eth             (o_rx_data_eth),
    .o_rx_valid_eth            (o_rx_valid_eth),
    .i_rx_ready_eth            (i_rx_ready_eth),

    .DAC_CTRL_SDIO             (DAC_CTRL_SDIO),
    .DAC_CTRL_SDENN            (DAC_CTRL_SDENN),
    .DAC_CTRL_SCLK             (DAC_CTRL_SCLK),
    .DAC_CTRL_RESETN           (DAC_CTRL_RESETN)
  );

  // Ring-bus capture: fires whenever the handshake completes. Since
  // ring_bus_i0_ready is held constant at 1 throughout (matching tb.cpp,
  // which never deasserts it -- `random_ready` is unset), this is
  // equivalent to just logging every cycle ringbus_out_data_vld is high.
  int          ring_count = 0;
  logic [31:0] ring_items[$];

  always @(posedge clk) begin
    if (ring_bus_i0_ready && ringbus_out_data_vld) begin
      ring_items.push_back(ringbus_out_data);
      ring_count++;
      $display("0x%0h", ringbus_out_data);
    end
  end

  initial begin
    int i;
    logic [31:0] cs20_pc;
    bit          done;

    // See the reset() derivation in the header comment above: RESET_CYCLES
    // (40) is a half-edge count in the C++ model, not a full-cycle count.
    // Only the first (RESET_CYCLES/2 - 1) = 19 rising edges see RESET==1;
    // RESET is deasserted before the 20th (final) rising edge of the
    // reset() call.
    repeat (RESET_CYCLES/2 - 1) @(posedge clk);
    MIB_MASTER_RESET = 0;
    @(posedge clk); // the 20th (final) reset()-call cycle, RESET already 0

    // postReset(top): i_data_valid_adc driven high from here on.
    i_data_valid_adc = 1;

    done = 0;
    for (i = 0; i < MAX_OUTER_ITERS && !done; i++) begin
      repeat (INNER_CYCLES) @(posedge clk);
      cs20_pc = dut.cs20_top.vex_machine_top_inst.q_engine_inst.iBus_cmd_payload_pc;
      if (cs20_pc == PC_DONE_0 || cs20_pc == PC_DONE_1 || cs20_pc == PC_DONE_2) begin
        done = 1;
      end
      // Progress heartbeat only (mirrors tb.cpp's own "%dus" printfs, which
      // are likewise ignored by compare_ringbus.py); not part of the
      // pass/fail contract.
      if (i % 40 == 39) $display("PROGRESS: iter=%0d time=%0t pc=0x%0h", i + 1, $time, cs20_pc);
    end

    repeat (FLUSH_CYCLES) @(posedge clk);

    $display("Ring got out %0d items.", ring_count);

    if (ring_count == 0) begin
      $display("FAIL: didn't get any ringbus output");
    end else if (ring_items[0] !== 32'hdeadbeef) begin
      $display("FAIL: Test did not start (first item 0x%0h != 0xdeadbeef)", ring_items[0]);
    end else if (ring_items[ring_count-1] !== 32'h0000000f) begin
      $display("FAIL: One or more tests didn't pass (last item 0x%0h != 0xf)", ring_items[ring_count-1]);
    end else begin
      $display("All Tests Passed");
    end

    $finish;
  end

endmodule
