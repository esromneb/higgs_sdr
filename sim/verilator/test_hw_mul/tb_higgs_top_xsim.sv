// XSIM parity testbench for Jenkins test_hw_mul. The full nine-tile
// platform wiring matches tb.cpp: CS11 runs the test firmware and the other
// CS tiles retain only ring-bus relay logic. The ring-bus result sequence and
// hardware divide/multiply cycle limits are checked exactly as in C++.

module tb_higgs_top_xsim;

  localparam int RESET_CYCLES = 40;
  localparam int TICK_CYCLES = (90 + 40) * 500;

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

  logic [31:0] ring_items[$];

  always @(posedge clk) begin
    if (ring_bus_i0_ready && ringbus_out_data_vld) begin
      ring_items.push_back(ringbus_out_data);
      $display("0x%08h", ringbus_out_data);
    end
  end

  initial begin
    int i;
    bit fail;

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

    repeat (TICK_CYCLES) @(posedge clk);

    fail = 0;
    if (ring_items.size() != 5) begin
      $display("FAIL: ring-bus item count %0d != 5", ring_items.size());
      fail = 1;
    end
    if (ring_items.size() == 5) begin
      if (ring_items[0] !== 32'h0000dead ||
          ring_items[1] !== 32'h0000002d ||
          ring_items[2] !== 32'h00000499 ||
          ring_items[3] !== 32'h0000000c ||
          ring_items[4] !== 32'h0102c5a0) begin
        $display("FAIL: hardware multiply/divide result sequence mismatch");
        fail = 1;
      end
      if (ring_items[1] >= 60) begin
        $display("FAIL: divide took %0d cycles", ring_items[1]);
        fail = 1;
      end
      if (ring_items[3] >= 40) begin
        $display("FAIL: multiply took %0d cycles", ring_items[3]);
        fail = 1;
      end
    end

    if (!fail)
      $display("All Tests Passed");

    $finish;
  end

endmodule
