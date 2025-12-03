// XSIM parity testbench for this test's actual DUT: `tb_higgs_top`
// (sim/hdl/tb_higgs_top.sv), configured identically to tb.cpp (no
// TB_USE_CS*/TB_USE_DAC/TB_USE_ADC/ETH_USE_MEGA_WRAPPER at all -- this
// test only exercises `eth_top`'s output slicer, unconditionally
// instantiated by tb_higgs_top.sv). Port list/connections are identical
// to test_eth_dma/tb_higgs_top_xsim.sv's (same Makefile TB_USE_*/
// OVERRIDE_* configuration -- ETH-only, see both tests' README.md/
// Makefile).
//
// Mirrors tb.cpp exactly:
//  - t->reset(40)      -> RESET_CYCLES = 40 (see test_fft_lib_1's
//    tb_higgs_top_xsim.sv header comment for the full half-edge-counter
//    derivation of HiggsHelper::reset(), reproduced identically here)
//  - postReset(top)    -> i_data_valid_adc driven to 1 right after reset
//  - int us = 15; t->tick(500*us) -> a fixed 7500-cycle wait, no
//    PC-polling loop (same one-shot-firmware pattern as test_eth_dma)
//  - ring-bus capture identical to test_eth_dma's (gated on
//    ring_bus_i0_ready && ringbus_out_data_vld)
//  - self-check: exact 235-item sequence match against tb.cpp's `ver[]`
//    reference array (this test exercises several output-slicer modes
//    -- 1:1/16:1/8:1/4:1/2:1 -- back to back, hence the long fixed
//    reference sequence; values transcribed verbatim from tb.cpp)
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
  localparam int TICK_CYCLES  = 500*15;
  localparam int NUM_VER      = 235;

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

  // tb.cpp's reference `ver[]` array (verbatim, see tb.cpp).
  localparam logic [31:0] ver [0:NUM_VER-1] = '{
        32'h00000000, 32'h00010001, 32'h00020002, 32'h00030003, 32'h00040004, 32'h00050005,
        32'h00060006, 32'h00070007, 32'h00080008, 32'h00090009, 32'h000a000a, 32'h000b000b,
        32'h000c000c, 32'h000d000d, 32'h000e000e, 32'h000f000f, 32'h00100010, 32'h00110011,
        32'h00120012, 32'h00130013, 32'h00140014, 32'h00150015, 32'h00160016, 32'h00170017,
        32'h00180018, 32'h00190019, 32'h001a001a, 32'h001b001b, 32'h001c001c, 32'h001d001d,
        32'h001e001e, 32'h001f001f, 32'h00200020, 32'h00210021, 32'h00220022, 32'h00230023,
        32'h00240024, 32'h00250025, 32'h00260026, 32'h00270027, 32'h00280028, 32'h00290029,
        32'h002a002a, 32'h002b002b, 32'h002c002c, 32'h002d002d, 32'h002e002e, 32'h002f002f,
        32'h00300030, 32'h00310031, 32'h00320032, 32'h00330033, 32'h00340034, 32'h00350035,
        32'h00360036, 32'h00370037, 32'h00380038, 32'h00390039, 32'h003a003a, 32'h003b003b,
        32'h003c003c, 32'h003d003d, 32'h003e003e, 32'h003f003f, 32'h01010000, 32'h03030202,
        32'h05050404, 32'h07070606, 32'h09090808, 32'h0b0b0a0a, 32'h0d0d0c0d, 32'h0f0f0e0e,
        32'h11111010, 32'h13131212, 32'h15151414, 32'h17171616, 32'h19191818, 32'h1b1b1a1a,
        32'h1d1d1c1c, 32'h1f1f1e1e, 32'h21212020, 32'h23232222, 32'h25252424, 32'h27272626,
        32'h29292828, 32'h2b2b2a2a, 32'h2d2d2c2c, 32'h2f2f2e2e, 32'h31313030, 32'h33333232,
        32'h35353434, 32'h37373636, 32'h39393838, 32'h3b3b3a3a, 32'h3d3d3c3c, 32'h3f3f3e3e,
        32'h41414040, 32'h43434242, 32'h45454444, 32'h47474646, 32'h49494848, 32'h4b4b4a4a,
        32'h4d4d4c4c, 32'h4f4f4e4e, 32'h51515050, 32'h53535252, 32'h55555454, 32'h57575656,
        32'h59595858, 32'h5b5b5a5a, 32'h5d5d5c5c, 32'h5f5f5e5e, 32'h61616060, 32'h63636262,
        32'h65656464, 32'h67676666, 32'h69696868, 32'h6b6b6a6a, 32'h6d6d6c6c, 32'h6f6f6e6e,
        32'h71717070, 32'h73737272, 32'h75757474, 32'h77777776, 32'h79797878, 32'h7b7b7a7a,
        32'h7d7d7c7c, 32'h7f7f7e7e, 32'h33221100, 32'h77665544, 32'hbbaa9988, 32'hffeeddcc,
        32'h33221100, 32'h77665544, 32'hbbaa9988, 32'hffeeddcc, 32'h33221100, 32'h77665544,
        32'hbbaa9988, 32'hffeeddcc, 32'h33221100, 32'h77665544, 32'hbbaa9988, 32'hffeeddcc,
        32'h33221100, 32'h77665544, 32'hbbaa9988, 32'hffeeddcc, 32'h33221100, 32'h77665544,
        32'hbbaa9988, 32'hffeeddcc, 32'h33221100, 32'h77665544, 32'hbbaa9988, 32'hffeeddcc,
        32'h33221100, 32'h77665544, 32'hbbaa9988, 32'hffeeddcc, 32'h33221100, 32'h77665544,
        32'hbbaa9988, 32'hffeeddcc, 32'h33221100, 32'h77665544, 32'hbbaa9988, 32'hffeeddcc,
        32'h33221100, 32'h77665544, 32'hbbaa9988, 32'hffeeddcc, 32'h33221100, 32'h77665544,
        32'hbbaa9988, 32'hffeeddcc, 32'h33221100, 32'h77665544, 32'hbbaa9988, 32'hffeeddcc,
        32'h33221100, 32'h77665544, 32'hbbaa9988, 32'hffeeddcc, 32'h33221100, 32'h77665544,
        32'hbbaa9988, 32'hffeeddcc, 32'h33221100, 32'h77665544, 32'hbbaa9988, 32'hffeeddcc,
        32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000,
        32'h00000000, 32'h00000000, 32'h44444444, 32'h44444444, 32'h44444444, 32'h44444444,
        32'h44444444, 32'h44444444, 32'h44444444, 32'h44444444, 32'h88888888, 32'h88888888,
        32'h88888888, 32'h88888888, 32'h88888888, 32'h88888888, 32'h88888888, 32'h88888888,
        32'hcccccccc, 32'hcccccccc, 32'hcccccccc, 32'hcccccccc, 32'hcccccccc, 32'hcccccccc,
        32'hcccccccc, 32'hcccccccc, 32'hdeadbeef, 32'hcafebabe, 32'h00000001, 32'h00000002,
        32'h00000003, 32'h00000004, 32'h00000005, 32'h00000006, 32'h00000007, 32'h00000008,
        32'h00000009
  };

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

    // t->tick(500*15): fixed wait, no PC-polling loop in this test.
    repeat (TICK_CYCLES) @(posedge clk);

    $display("Eth DMA out got %0d items", ring_count);

    fail = 0;
    if (ring_count == 0) begin
      $display("FAIL: didn't get any output");
      fail = 1;
    end else begin
      for (i = 0; i < ring_count && i < NUM_VER; i++) begin
        if (ring_items[i] !== ver[i]) begin
          $display("FAIL: got wrong item from DMA at index %0d: 0x%08h != 0x%08h",
                    i, ring_items[i], ver[i]);
          fail = 1;
        end
      end
      if (ring_count != NUM_VER) begin
        $display("FAIL: got wrong number of items from DMA (%0d != %0d)",
                  ring_count, NUM_VER);
        fail = 1;
      end
    end

    if (!fail) $display("All Tests Passed");

    $finish;
  end

endmodule
