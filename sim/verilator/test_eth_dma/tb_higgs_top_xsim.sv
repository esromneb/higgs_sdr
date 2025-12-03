// XSIM parity testbench for this test's actual DUT: `tb_higgs_top`
// (sim/hdl/tb_higgs_top.sv), configured identically to tb.cpp (no
// TB_USE_CS*/TB_USE_DAC/TB_USE_ADC/ETH_USE_MEGA_WRAPPER at all -- this
// test only exercises `eth_top`, unconditionally instantiated by
// tb_higgs_top.sv). Because none of those defines are set, none of the
// per-tile `snap_csXX_riscv_out_*`/`snap_csXX_io_uart_*` ports exist on
// this configuration of `tb_higgs_top` (they are declared `` `ifdef ``
// inside the module's own port list) -- this testbench's port
// connections are correspondingly a strict subset of
// test_fft_lib_1/tb_higgs_top_xsim.sv's.
//
// Mirrors tb.cpp exactly:
//  - t->reset(40)     -> RESET_CYCLES = 40 (see test_fft_lib_1's
//    tb_higgs_top_xsim.sv header comment for the full half-edge-counter
//    derivation of HiggsHelper::reset(), reproduced identically here)
//  - postReset(top)   -> i_data_valid_adc driven to 1 right after reset
//  - t->tick(1000)     -> a fixed 1000-cycle wait, no PC-polling loop
//    (this test's firmware override, fpgas/grav/eth/c/src/main.c, is a
//    one-shot DMA_1 config + push, not a polling loop watched for a
//    specific exit PC, so tb.cpp itself just ticks a fixed count and
//    checks the result -- reproduced identically here)
//  - ring-bus capture identical to test_fft_lib_1's (gated on
//    `ring_bus_i0_ready && ringbus_out_data_vld`)
//  - self-check: exactly 4 items, data[i] == i+1 for i in 0..3 (see
//    tb.cpp's asserts directly, not the looser first/last-item check
//    test_fft_lib_1 uses)
//
// See tb.cpp and README.md for the full derivation of the stimulus/
// tie-off table below.
//
// Deliberately has no `` `timescale `` directive of its own -- see
// test_fft_lib_1/tb_higgs_top_xsim.sv's header comment for why (xelab
// requires every module in a design to consistently either have or lack
// a timescale, and none of the ~150 files reachable from tb_higgs_top
// declare one, aside from the patched exceptions the shared
// scripts/make_include/xsim_common.mk handles).

module tb_higgs_top_xsim;

  localparam int RESET_CYCLES = 40;
  localparam int TICK_CYCLES  = 1000;

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
  // derivation (matches tb.cpp's handle_uart_neg()). This test's eth
  // firmware override is a one-shot program (no polling loop), so the
  // spurious-retrigger bug found there does not reproduce here, but the
  // idle-high tie-off is still the behaviorally-correct match to tb.cpp
  // and is kept for consistency.
  logic        snap_eth_io_uart_rxd = 1;

  wire [31:0]  ringbus_out_data;
  wire         ringbus_out_data_vld;

  logic        ring_bus_i0_ready    = 1;

  wire         o_data_valid_dac;
  wire [31:0]  o_data_dac;

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
      $display("0x%08h", ringbus_out_data);
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

    // t->tick(1000): fixed wait, no PC-polling loop in this test.
    repeat (TICK_CYCLES) @(posedge clk);

    $display("Ringbus got out %0d items", ring_count);

    fail = 0;
    if (ring_count == 0) begin
      $display("FAIL: didn't get any output");
      fail = 1;
    end else if (ring_count != 4) begin
      $display("FAIL: got wrong number of dma items (%0d != 4)", ring_count);
      fail = 1;
    end else begin
      for (i = 0; i < 4; i++) begin
        if (ring_items[i] !== (i + 1)) begin
          $display("FAIL: got wrong value in dma at index %0d: 0x%08h != 0x%08h",
                    i, ring_items[i], i + 1);
          fail = 1;
        end
      end
    end

    if (!fail) $display("All Tests Passed");

    $finish;
  end

endmodule
