// XSIM parity testbench for the existing test_nco platform regression.
// It mirrors tb.cpp's reset and 400*500-cycle execution window, captures
// CS20's DMA output, and applies the same count, period, phase-anchor, and
// FNV-1a self-checks before writing the complete sample stream for an exact
// cross-simulator comparison.

module tb_higgs_top_xsim;

  localparam int RESET_CYCLES = 40;
  localparam int TICK_CYCLES = 400 * 500;
  localparam int EXPECTED_COUNT = 32768;
  localparam int EXPECTED_PERIOD = 4096;
  localparam logic [63:0] EXPECTED_FNV = 64'h6248f48c3198f9f5;

  logic clk = 0;
  always #5 clk = ~clk;

  logic MIB_MASTER_RESET = 1;
  logic [31:0] i_data_adc = 0;
  logic i_data_valid_adc = 0;

  logic [31:0] tx_turnstile_data_in = 0;
  logic tx_turnstile_data_last = 0;
  logic tx_turnstile_data_valid = 0;
  wire tx_turnstile_data_ready;

  logic [31:0] ringbus_in_data = 0;
  logic ringbus_in_data_vld = 0;
  wire ringbus_in_data_ready;
  wire snap_eth_io_uart_txd;
  logic snap_eth_io_uart_rxd = 1;
  wire [31:0] ringbus_out_data;
  wire ringbus_out_data_vld;
  logic ring_bus_i0_ready = 1;

  wire o_data_valid_dac;
  wire [31:0] o_data_dac;

  wire [31:0] snap_cs20_riscv_out_data;
  wire snap_cs20_riscv_out_last;
  wire snap_cs20_riscv_out_valid;
  wire snap_cs20_riscv_out_ready;
  wire snap_cs20_io_uart_txd;
  wire snap_cs20_io_uart_rxd;

  logic [31:0] adc_data_out = 0;
  logic adc_data_out_valid = 0;
  wire adc_data_out_ready;
  wire [31:0] snap_mapmov_in_data;
  wire snap_mapmov_in_valid;
  wire snap_mapmov_in_ready;
  wire [31:0] o_data_eth;
  wire o_data_valid_eth;
  wire o_data_last_eth;
  wire [31:0] o_rx_data_eth;
  wire o_rx_valid_eth;
  logic i_rx_ready_eth = 1;
  wire DAC_CTRL_SDIO;
  wire DAC_CTRL_SDENN;
  wire DAC_CTRL_SCLK;
  wire DAC_CTRL_RESETN;

  logic [31:0] nco_samples[$];
  logic [63:0] nco_fnv = 64'hcbf29ce484222325;

  function automatic logic [63:0] fnv_word(
      input logic [63:0] hash,
      input logic [31:0] word
  );
    logic [63:0] next_hash;
    int byte_index;
    begin
      next_hash = hash;
      for (byte_index = 0; byte_index < 4; byte_index++) begin
        next_hash = next_hash ^ word[byte_index*8 +: 8];
        next_hash = next_hash * 64'h00000100000001b3;
      end
      return next_hash;
    end
  endfunction

  tb_higgs_top dut (
    .clk(clk),
    .MIB_MASTER_RESET(MIB_MASTER_RESET),
    .i_data_adc(i_data_adc),
    .i_data_valid_adc(i_data_valid_adc),
    .tx_turnstile_data_in(tx_turnstile_data_in),
    .tx_turnstile_data_last(tx_turnstile_data_last),
    .tx_turnstile_data_valid(tx_turnstile_data_valid),
    .tx_turnstile_data_ready(tx_turnstile_data_ready),
    .ringbus_in_data(ringbus_in_data),
    .ringbus_in_data_vld(ringbus_in_data_vld),
    .ringbus_in_data_ready(ringbus_in_data_ready),
    .snap_eth_io_uart_txd(snap_eth_io_uart_txd),
    .snap_eth_io_uart_rxd(snap_eth_io_uart_rxd),
    .ringbus_out_data(ringbus_out_data),
    .ringbus_out_data_vld(ringbus_out_data_vld),
    .ring_bus_i0_ready(ring_bus_i0_ready),
    .o_data_valid_dac(o_data_valid_dac),
    .o_data_dac(o_data_dac),
    .snap_cs20_riscv_out_data(snap_cs20_riscv_out_data),
    .snap_cs20_riscv_out_last(snap_cs20_riscv_out_last),
    .snap_cs20_riscv_out_valid(snap_cs20_riscv_out_valid),
    .snap_cs20_riscv_out_ready(snap_cs20_riscv_out_ready),
    .snap_cs20_io_uart_txd(snap_cs20_io_uart_txd),
    .snap_cs20_io_uart_rxd(snap_cs20_io_uart_rxd),
    .adc_data_out(adc_data_out),
    .adc_data_out_valid(adc_data_out_valid),
    .adc_data_out_ready(adc_data_out_ready),
    .snap_mapmov_in_data(snap_mapmov_in_data),
    .snap_mapmov_in_valid(snap_mapmov_in_valid),
    .snap_mapmov_in_ready(snap_mapmov_in_ready),
    .o_data_eth(o_data_eth),
    .o_data_valid_eth(o_data_valid_eth),
    .o_data_last_eth(o_data_last_eth),
    .o_rx_data_eth(o_rx_data_eth),
    .o_rx_valid_eth(o_rx_valid_eth),
    .i_rx_ready_eth(i_rx_ready_eth),
    .DAC_CTRL_SDIO(DAC_CTRL_SDIO),
    .DAC_CTRL_SDENN(DAC_CTRL_SDENN),
    .DAC_CTRL_SCLK(DAC_CTRL_SCLK),
    .DAC_CTRL_RESETN(DAC_CTRL_RESETN)
  );

  always @(posedge clk) begin
    if (snap_cs20_riscv_out_ready && snap_cs20_riscv_out_valid) begin
      nco_samples.push_back(snap_cs20_riscv_out_data);
      nco_fnv = fnv_word(nco_fnv, snap_cs20_riscv_out_data);
    end
  end

  initial begin
    int sample_index;
    int output_file;
    bit fail;

    repeat (RESET_CYCLES/2 - 1) @(posedge clk);
    MIB_MASTER_RESET = 0;
    @(posedge clk);
    i_data_valid_adc = 1;

    repeat (TICK_CYCLES) @(posedge clk);

    output_file = $fopen("xsim_nco.hex", "w");
    for (sample_index = 0; sample_index < nco_samples.size(); sample_index++)
      $fdisplay(output_file, "%08h", nco_samples[sample_index]);
    $fclose(output_file);

    fail = 0;
    if (nco_samples.size() != EXPECTED_COUNT) begin
      $display("FAIL: NCO sample count %0d != %0d",
               nco_samples.size(), EXPECTED_COUNT);
      fail = 1;
    end
    if (nco_fnv !== EXPECTED_FNV) begin
      $display("FAIL: NCO FNV-1a 0x%016h != 0x%016h",
               nco_fnv, EXPECTED_FNV);
      fail = 1;
    end
    if (nco_samples.size() == EXPECTED_COUNT) begin
      for (sample_index = EXPECTED_PERIOD;
           sample_index < EXPECTED_COUNT;
           sample_index++) begin
        if (nco_samples[sample_index] !==
            nco_samples[sample_index % EXPECTED_PERIOD]) begin
          $display("FAIL: NCO period mismatch at sample %0d", sample_index);
          fail = 1;
          sample_index = EXPECTED_COUNT;
        end
      end
      if (nco_samples[0] !== 32'h80000041 ||
          nco_samples[1024] !== 32'hffe67fff ||
          nco_samples[2048] !== 32'h7ffffffc ||
          nco_samples[3072] !== 32'h00768000 ||
          nco_samples[4095] !== 32'h8000fff3) begin
        $display("FAIL: NCO phase-quadrant anchor mismatch");
        fail = 1;
      end
    end

    $display("NCO captured %0d samples", nco_samples.size());
    if (!fail)
      $display("All Tests Passed");
    $finish;
  end

endmodule
