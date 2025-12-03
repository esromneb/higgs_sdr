// XSIM parity testbench for this test's actual DUT: `tb_higgs_top`
// (sim/hdl/tb_higgs_top.sv), configured identically to tb.cpp: ALL 8 CS
// tiles enabled (TB_USE_CS11/CS12/CS02/CS01/CS31/CS32/CS22/CS21/CS20),
// OVERRIDE_CS20_C=1 (only CS20 has its firmware overridden -- all other
// 7 tiles run CS*_NO_RISCV=1, i.e. no RISC-V core at all, just ring-bus
// passthrough), no TB_USE_DAC/TB_USE_ADC/ETH_USE_MEGA_WRAPPER. This is
// the largest port list of any XSIM port so far (9 FPGA tiles total:
// eth + 8x CS) -- see sim/hdl/tb_higgs_top.sv's per-`` `ifdef TB_USE_CSxx``
// port blocks for the authoritative per-tile port list this mirrors.
//
// Per-tile port asymmetries (transcribed directly from tb_higgs_top.sv,
// NOT uniform across tiles):
//  - cs11: riscv_out(data/last/valid/ready) + riscv_in(data/valid/ready
//    -- no `last`!) + uart(txd/rxd). All are `output wire` (monitor-only
//    taps; see higgs_helper.hpp's `i_data`/`i_valid` Port32Out-style
//    wiring for cs11in/cs31in -- these are read-only from the TB's POV
//    despite the "_in" name, which refers to CS11's own RX direction).
//  - cs31: riscv_out(4) + uart(2) + riscv_in(data/last/valid/ready --
//    *with* `last` this time). All `output wire`.
//  - cs22/cs21: riscv_out(4) + uart(2) + inject_riscv_in(data/last/valid
//    are `input wire` -- genuinely TB-driven -- + ready is `output
//    wire`). higgs_helper.hpp only wires these as driven inputs
//    (Port32In, `ins["cs22in"]`/`ins["cs21in"]`) when CS32_NO_RISCV/
//    CS22_NO_RISCV are defined (true here); since tb.cpp never calls
//    inStreamAppend() on either, HiggsHelper::handleDataInNegIndex()
//    drives `*t_valid = 0` every cycle (data.size()==0) -- reproduced
//    here as a permanent tie-off (valid=0, data/last=0).
//  - cs01/cs32/cs20/cs02/cs12: just riscv_out(4) + uart(2), all `output
//    wire` (same minimal bundle as test_fft_lib_1's single-tile CS20
//    connection).
//
// Mirrors tb.cpp exactly:
//  - t->reset(40)   -> RESET_CYCLES = 40 (see test_fft_lib_1's
//    tb_higgs_top_xsim.sv header comment for the full half-edge-counter
//    derivation of HiggsHelper::reset(), reproduced identically here)
//  - postReset(top) -> i_data_valid_adc driven to 1 right after reset
//  - `int us = 100; for (i = 0; i < us; i++) t->tick(500);` -> a fixed
//    100*500 = 50000-cycle wait, NO PC-polling loop (unlike
//    test_fft_lib_1) -- tb.cpp itself never inspects any PC for this
//    test, just ticks a fixed total and checks the result.
//  - cs20out capture: gated on `snap_cs20_riscv_out_ready &&
//    snap_cs20_riscv_out_valid` (HiggsHelper::handleDataOutPosIndex()'s
//    exact `i_ready && i_valid` condition; `control_ready=0` means the
//    TB never drives ready itself -- it is purely an internal DUT
//    signal being tapped/monitored here, same as test_fft_lib_1's
//    ring-bus capture).
//  - self-check mirrors tb.cpp's asserts exactly: first 1024 items must
//    equal `0xff000000 + i`, and total captured count must exceed 2048.
//    Deliberately NOT printing each item as a `` 0x... `` line (unlike
//    test_eth_dma/test_dma_slicer's testbenches) because tb.cpp itself
//    has no such per-item print loop for this test (just the two
//    asserts + a summary count) -- printing extra lines here would
//    make compare_ringbus.py falsely detect a stream mismatch (0 items
//    from Verilator's log vs N from XSIM's). The two simulators'
//    agreement is instead proven by both independently satisfying the
//    identical tb.cpp-derived assertion predicate on their own
//    captured data, plus both printing the same "All Tests Passed"
//    self-check success line.
//
// See tb.cpp, higgs_helper.hpp (preReset/postReset/reset) and README.md
// for the full derivation of the stimulus/tie-off table below.
//
// Deliberately has no `` `timescale `` directive of its own -- see
// test_fft_lib_1/tb_higgs_top_xsim.sv's header comment for why (xelab
// requires every module in a design to consistently either have or lack
// a timescale, and none of the ~150 files reachable from tb_higgs_top
// declare one, aside from the patched exceptions the shared
// scripts/make_include/xsim_common.mk handles).

module tb_higgs_top_xsim;

  localparam int RESET_CYCLES = 40;
  localparam int OUTER_ITERS  = 100;
  localparam int INNER_CYCLES = 500;
  localparam int CHECK_PREFIX = 1024;
  localparam int MIN_COUNT    = 2048;

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
  // UART RX idle state is logic-1 (mark/idle); see
  // test_fft_lib_1/tb_higgs_top_xsim.sv's header comment for the full
  // derivation. This test's eth firmware is the DEFAULT (no
  // OVERRIDE_ETH_C), same default polling-loop firmware that caused the
  // spurious-retrigger bug found there if left idle-low; kept idle-high
  // for correctness/consistency.
  logic        snap_eth_io_uart_rxd = 1;

  wire [31:0]  ringbus_out_data;
  wire         ringbus_out_data_vld;

  logic        ring_bus_i0_ready    = 1;

  wire         o_data_valid_dac;
  wire [31:0]  o_data_dac;

  // CS11
  wire [31:0]  snap_cs11_riscv_out_data;
  wire         snap_cs11_riscv_out_last;
  wire         snap_cs11_riscv_out_valid;
  wire         snap_cs11_riscv_out_ready;
  wire [31:0]  snap_cs11_riscv_in_data;
  wire         snap_cs11_riscv_in_valid;
  wire         snap_cs11_riscv_in_ready;
  wire         snap_cs11_io_uart_txd;
  wire         snap_cs11_io_uart_rxd;

  // CS01
  wire [31:0]  snap_cs01_riscv_out_data;
  wire         snap_cs01_riscv_out_last;
  wire         snap_cs01_riscv_out_valid;
  wire         snap_cs01_riscv_out_ready;
  wire         snap_cs01_io_uart_txd;
  wire         snap_cs01_io_uart_rxd;

  // CS31
  wire [31:0]  snap_cs31_riscv_out_data;
  wire         snap_cs31_riscv_out_last;
  wire         snap_cs31_riscv_out_valid;
  wire         snap_cs31_riscv_out_ready;
  wire         snap_cs31_io_uart_txd;
  wire         snap_cs31_io_uart_rxd;
  wire [31:0]  snap_cs31_riscv_in_data;
  wire         snap_cs31_riscv_in_last;
  wire         snap_cs31_riscv_in_valid;
  wire         snap_cs31_riscv_in_ready;

  // CS32
  wire [31:0]  snap_cs32_riscv_out_data;
  wire         snap_cs32_riscv_out_last;
  wire         snap_cs32_riscv_out_valid;
  wire         snap_cs32_riscv_out_ready;
  wire         snap_cs32_io_uart_txd;
  wire         snap_cs32_io_uart_rxd;

  // CS22 (+ inject_cs22_riscv_in_*, tied to inactive -- see header comment)
  wire [31:0]  snap_cs22_riscv_out_data;
  wire         snap_cs22_riscv_out_last;
  wire         snap_cs22_riscv_out_valid;
  wire         snap_cs22_riscv_out_ready;
  logic [31:0] inject_cs22_riscv_in_data  = 0;
  logic        inject_cs22_riscv_in_last  = 0;
  logic        inject_cs22_riscv_in_valid = 0;
  wire         inject_cs22_riscv_in_ready;
  wire         snap_cs22_io_uart_txd;
  wire         snap_cs22_io_uart_rxd;

  // CS21 (+ inject_cs21_riscv_in_*, tied to inactive -- see header comment)
  wire [31:0]  snap_cs21_riscv_out_data;
  wire         snap_cs21_riscv_out_last;
  wire         snap_cs21_riscv_out_valid;
  wire         snap_cs21_riscv_out_ready;
  logic [31:0] inject_cs21_riscv_in_data  = 0;
  logic        inject_cs21_riscv_in_last  = 0;
  logic        inject_cs21_riscv_in_valid = 0;
  wire         inject_cs21_riscv_in_ready;
  wire         snap_cs21_io_uart_txd;
  wire         snap_cs21_io_uart_rxd;

  // CS20 (the tile under test -- firmware override lives here)
  wire [31:0]  snap_cs20_riscv_out_data;
  wire         snap_cs20_riscv_out_last;
  wire         snap_cs20_riscv_out_valid;
  wire         snap_cs20_riscv_out_ready;
  wire         snap_cs20_io_uart_txd;
  wire         snap_cs20_io_uart_rxd;

  // CS02
  wire [31:0]  snap_cs02_riscv_out_data;
  wire         snap_cs02_riscv_out_last;
  wire         snap_cs02_riscv_out_valid;
  wire         snap_cs02_riscv_out_ready;
  wire         snap_cs02_io_uart_txd;
  wire         snap_cs02_io_uart_rxd;

  // CS12
  wire [31:0]  snap_cs12_riscv_out_data;
  wire         snap_cs12_riscv_out_last;
  wire         snap_cs12_riscv_out_valid;
  wire         snap_cs12_riscv_out_ready;
  wire         snap_cs12_io_uart_txd;
  wire         snap_cs12_io_uart_rxd;

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

    .snap_cs11_riscv_out_data  (snap_cs11_riscv_out_data),
    .snap_cs11_riscv_out_last  (snap_cs11_riscv_out_last),
    .snap_cs11_riscv_out_valid (snap_cs11_riscv_out_valid),
    .snap_cs11_riscv_out_ready (snap_cs11_riscv_out_ready),
    .snap_cs11_riscv_in_data   (snap_cs11_riscv_in_data),
    .snap_cs11_riscv_in_valid  (snap_cs11_riscv_in_valid),
    .snap_cs11_riscv_in_ready  (snap_cs11_riscv_in_ready),
    .snap_cs11_io_uart_txd     (snap_cs11_io_uart_txd),
    .snap_cs11_io_uart_rxd     (snap_cs11_io_uart_rxd),

    .snap_cs01_riscv_out_data  (snap_cs01_riscv_out_data),
    .snap_cs01_riscv_out_last  (snap_cs01_riscv_out_last),
    .snap_cs01_riscv_out_valid (snap_cs01_riscv_out_valid),
    .snap_cs01_riscv_out_ready (snap_cs01_riscv_out_ready),
    .snap_cs01_io_uart_txd     (snap_cs01_io_uart_txd),
    .snap_cs01_io_uart_rxd     (snap_cs01_io_uart_rxd),

    .snap_cs31_riscv_out_data  (snap_cs31_riscv_out_data),
    .snap_cs31_riscv_out_last  (snap_cs31_riscv_out_last),
    .snap_cs31_riscv_out_valid (snap_cs31_riscv_out_valid),
    .snap_cs31_riscv_out_ready (snap_cs31_riscv_out_ready),
    .snap_cs31_io_uart_txd     (snap_cs31_io_uart_txd),
    .snap_cs31_io_uart_rxd     (snap_cs31_io_uart_rxd),
    .snap_cs31_riscv_in_data   (snap_cs31_riscv_in_data),
    .snap_cs31_riscv_in_last   (snap_cs31_riscv_in_last),
    .snap_cs31_riscv_in_valid  (snap_cs31_riscv_in_valid),
    .snap_cs31_riscv_in_ready  (snap_cs31_riscv_in_ready),

    .snap_cs32_riscv_out_data  (snap_cs32_riscv_out_data),
    .snap_cs32_riscv_out_last  (snap_cs32_riscv_out_last),
    .snap_cs32_riscv_out_valid (snap_cs32_riscv_out_valid),
    .snap_cs32_riscv_out_ready (snap_cs32_riscv_out_ready),
    .snap_cs32_io_uart_txd     (snap_cs32_io_uart_txd),
    .snap_cs32_io_uart_rxd     (snap_cs32_io_uart_rxd),

    .snap_cs22_riscv_out_data  (snap_cs22_riscv_out_data),
    .snap_cs22_riscv_out_last  (snap_cs22_riscv_out_last),
    .snap_cs22_riscv_out_valid (snap_cs22_riscv_out_valid),
    .snap_cs22_riscv_out_ready (snap_cs22_riscv_out_ready),
    .inject_cs22_riscv_in_data  (inject_cs22_riscv_in_data),
    .inject_cs22_riscv_in_last  (inject_cs22_riscv_in_last),
    .inject_cs22_riscv_in_valid (inject_cs22_riscv_in_valid),
    .inject_cs22_riscv_in_ready (inject_cs22_riscv_in_ready),
    .snap_cs22_io_uart_txd     (snap_cs22_io_uart_txd),
    .snap_cs22_io_uart_rxd     (snap_cs22_io_uart_rxd),

    .snap_cs21_riscv_out_data  (snap_cs21_riscv_out_data),
    .snap_cs21_riscv_out_last  (snap_cs21_riscv_out_last),
    .snap_cs21_riscv_out_valid (snap_cs21_riscv_out_valid),
    .snap_cs21_riscv_out_ready (snap_cs21_riscv_out_ready),
    .inject_cs21_riscv_in_data  (inject_cs21_riscv_in_data),
    .inject_cs21_riscv_in_last  (inject_cs21_riscv_in_last),
    .inject_cs21_riscv_in_valid (inject_cs21_riscv_in_valid),
    .inject_cs21_riscv_in_ready (inject_cs21_riscv_in_ready),
    .snap_cs21_io_uart_txd     (snap_cs21_io_uart_txd),
    .snap_cs21_io_uart_rxd     (snap_cs21_io_uart_rxd),

    .snap_cs20_riscv_out_data  (snap_cs20_riscv_out_data),
    .snap_cs20_riscv_out_last  (snap_cs20_riscv_out_last),
    .snap_cs20_riscv_out_valid (snap_cs20_riscv_out_valid),
    .snap_cs20_riscv_out_ready (snap_cs20_riscv_out_ready),
    .snap_cs20_io_uart_txd     (snap_cs20_io_uart_txd),
    .snap_cs20_io_uart_rxd     (snap_cs20_io_uart_rxd),

    .snap_cs02_riscv_out_data  (snap_cs02_riscv_out_data),
    .snap_cs02_riscv_out_last  (snap_cs02_riscv_out_last),
    .snap_cs02_riscv_out_valid (snap_cs02_riscv_out_valid),
    .snap_cs02_riscv_out_ready (snap_cs02_riscv_out_ready),
    .snap_cs02_io_uart_txd     (snap_cs02_io_uart_txd),
    .snap_cs02_io_uart_rxd     (snap_cs02_io_uart_rxd),

    .snap_cs12_riscv_out_data  (snap_cs12_riscv_out_data),
    .snap_cs12_riscv_out_last  (snap_cs12_riscv_out_last),
    .snap_cs12_riscv_out_valid (snap_cs12_riscv_out_valid),
    .snap_cs12_riscv_out_ready (snap_cs12_riscv_out_ready),
    .snap_cs12_io_uart_txd     (snap_cs12_io_uart_txd),
    .snap_cs12_io_uart_rxd     (snap_cs12_io_uart_rxd),

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

  // cs20out capture: fires whenever the handshake completes, exactly
  // HiggsHelper::handleDataOutPosIndex()'s `i_ready && i_valid` gate
  // (ready is a DUT-internal signal only tapped here, never driven by
  // this TB -- control_ready=0 in higgs_helper.hpp).
  int          cs20_count = 0;
  logic [31:0] cs20_items[$];

  always @(posedge clk) begin
    if (snap_cs20_riscv_out_ready && snap_cs20_riscv_out_valid) begin
      cs20_items.push_back(snap_cs20_riscv_out_data);
      cs20_count++;
    end
  end

  initial begin
    int i;
    bit  fail;

    // See test_fft_lib_1/tb_higgs_top_xsim.sv's header comment for the
    // full derivation: RESET_CYCLES (40) is a half-edge count in the C++
    // model, not a full-cycle count. Only the first (RESET_CYCLES/2 - 1)
    // = 19 rising edges see RESET==1; RESET is deasserted before the
    // 20th (final) rising edge of the reset() call.
    repeat (RESET_CYCLES/2 - 1) @(posedge clk);
    MIB_MASTER_RESET = 0;
    @(posedge clk); // the 20th (final) reset()-call cycle, RESET already 0

    // postReset(top): i_data_valid_adc driven high from here on.
    i_data_valid_adc = 1;

    // for (i = 0; i < 100; i++) t->tick(500): fixed 50000-cycle wait, no
    // PC-polling loop in this test.
    for (i = 0; i < OUTER_ITERS; i++) begin
      repeat (INNER_CYCLES) @(posedge clk);
    end

    $display("CS20 gave us %0d samples", cs20_count);

    fail = 0;
    if (cs20_count <= MIN_COUNT) begin
      $display("FAIL: got too few cs20out samples (%0d <= %0d)", cs20_count, MIN_COUNT);
      fail = 1;
    end
    for (i = 0; i < CHECK_PREFIX && i < cs20_count; i++) begin
      logic [31:0] expected;
      expected = 32'hff000000 + i;
      if (cs20_items[i] !== expected) begin
        $display("FAIL: cs20out[%0d] = 0x%08h != 0x%08h", i, cs20_items[i], expected);
        fail = 1;
      end
    end
    if (cs20_count < CHECK_PREFIX) begin
      $display("FAIL: got fewer than %0d cs20out samples (%0d)", CHECK_PREFIX, cs20_count);
      fail = 1;
    end

    if (!fail) $display("All Tests Passed");

    $finish;
  end

endmodule
