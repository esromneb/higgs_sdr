// XSIM testbench for test_image_1, mirroring tb.cpp:
//  - same reset sequence as HiggsHelper::reset(40) (see
//    test_fft_lib_1/tb_higgs_top_xsim.sv for the derivation)
//  - injects in.hex on cs22in with valid/ready
//  - captures cs22out on valid && ready until the END header echo, then
//    2000 more cycles
//  - writes xsim_got.hex. `make xsim_compare` compares it with the Python
//    model (exp.hex) and with Verilator's got.hex.
// No `timescale (see test_fft_lib_1/tb_higgs_top_xsim.sv).

module tb_higgs_top_xsim;

  localparam int RESET_CYCLES = 40;
  localparam int INJECT_DELAY = 100;
  localparam int MAX_CYCLES   = 40000 * 500;
  localparam int FLUSH_CYCLES = 2000;
  localparam int MAX_WORDS    = 65536;
  localparam logic [31:0] END_HEADER = 32'h1A6E00FF;

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
  logic        snap_eth_io_uart_rxd = 1;   // UART idle
  wire [31:0]  ringbus_out_data;
  wire         ringbus_out_data_vld;
  logic        ring_bus_i0_ready    = 1;
  wire         o_data_valid_dac;
  wire [31:0]  o_data_dac;

  wire [31:0]  snap_cs32_riscv_out_data;
  wire         snap_cs32_riscv_out_last;
  wire         snap_cs32_riscv_out_valid;
  wire         snap_cs32_riscv_out_ready;
  wire         snap_cs32_io_uart_txd;
  wire         snap_cs32_io_uart_rxd;

  wire [31:0]  snap_cs22_riscv_out_data;
  wire         snap_cs22_riscv_out_last;
  wire         snap_cs22_riscv_out_valid;
  wire         snap_cs22_riscv_out_ready;
  logic [31:0] inject_cs22_riscv_in_data;
  logic        inject_cs22_riscv_in_last = 0;
  logic        inject_cs22_riscv_in_valid;
  wire         inject_cs22_riscv_in_ready;
  wire         snap_cs22_io_uart_txd;
  wire         snap_cs22_io_uart_rxd;

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
  logic        i_rx_ready_eth       = 1;
  wire         DAC_CTRL_SDIO;
  wire         DAC_CTRL_SDENN;
  wire         DAC_CTRL_SCLK;
  wire         DAC_CTRL_RESETN;

  tb_higgs_top dut (
    .clk                        (clk),
    .MIB_MASTER_RESET           (MIB_MASTER_RESET),
    .i_data_adc                 (i_data_adc),
    .i_data_valid_adc           (i_data_valid_adc),
    .tx_turnstile_data_in       (tx_turnstile_data_in),
    .tx_turnstile_data_last     (tx_turnstile_data_last),
    .tx_turnstile_data_valid    (tx_turnstile_data_valid),
    .tx_turnstile_data_ready    (tx_turnstile_data_ready),
    .ringbus_in_data            (ringbus_in_data),
    .ringbus_in_data_vld        (ringbus_in_data_vld),
    .ringbus_in_data_ready      (ringbus_in_data_ready),
    .snap_eth_io_uart_txd       (snap_eth_io_uart_txd),
    .snap_eth_io_uart_rxd       (snap_eth_io_uart_rxd),
    .ringbus_out_data           (ringbus_out_data),
    .ringbus_out_data_vld       (ringbus_out_data_vld),
    .ring_bus_i0_ready          (ring_bus_i0_ready),
    .o_data_valid_dac           (o_data_valid_dac),
    .o_data_dac                 (o_data_dac),

    .snap_cs32_riscv_out_data   (snap_cs32_riscv_out_data),
    .snap_cs32_riscv_out_last   (snap_cs32_riscv_out_last),
    .snap_cs32_riscv_out_valid  (snap_cs32_riscv_out_valid),
    .snap_cs32_riscv_out_ready  (snap_cs32_riscv_out_ready),
    .snap_cs32_io_uart_txd      (snap_cs32_io_uart_txd),
    .snap_cs32_io_uart_rxd      (snap_cs32_io_uart_rxd),

    .snap_cs22_riscv_out_data   (snap_cs22_riscv_out_data),
    .snap_cs22_riscv_out_last   (snap_cs22_riscv_out_last),
    .snap_cs22_riscv_out_valid  (snap_cs22_riscv_out_valid),
    .snap_cs22_riscv_out_ready  (snap_cs22_riscv_out_ready),
    .inject_cs22_riscv_in_data  (inject_cs22_riscv_in_data),
    .inject_cs22_riscv_in_last  (inject_cs22_riscv_in_last),
    .inject_cs22_riscv_in_valid (inject_cs22_riscv_in_valid),
    .inject_cs22_riscv_in_ready (inject_cs22_riscv_in_ready),
    .snap_cs22_io_uart_txd      (snap_cs22_io_uart_txd),
    .snap_cs22_io_uart_rxd      (snap_cs22_io_uart_rxd),

    .snap_cs21_riscv_out_data   (snap_cs21_riscv_out_data),
    .snap_cs21_riscv_out_last   (snap_cs21_riscv_out_last),
    .snap_cs21_riscv_out_valid  (snap_cs21_riscv_out_valid),
    .snap_cs21_riscv_out_ready  (snap_cs21_riscv_out_ready),
    .inject_cs21_riscv_in_data  (inject_cs21_riscv_in_data),
    .inject_cs21_riscv_in_last  (inject_cs21_riscv_in_last),
    .inject_cs21_riscv_in_valid (inject_cs21_riscv_in_valid),
    .inject_cs21_riscv_in_ready (inject_cs21_riscv_in_ready),
    .snap_cs21_io_uart_txd      (snap_cs21_io_uart_txd),
    .snap_cs21_io_uart_rxd      (snap_cs21_io_uart_rxd),

    .adc_data_out               (adc_data_out),
    .adc_data_out_valid         (adc_data_out_valid),
    .adc_data_out_ready         (adc_data_out_ready),
    .snap_mapmov_in_data        (snap_mapmov_in_data),
    .snap_mapmov_in_valid       (snap_mapmov_in_valid),
    .snap_mapmov_in_ready       (snap_mapmov_in_ready),
    .o_data_eth                 (o_data_eth),
    .o_data_valid_eth           (o_data_valid_eth),
    .o_data_last_eth            (o_data_last_eth),
    .o_rx_data_eth              (o_rx_data_eth),
    .o_rx_valid_eth             (o_rx_valid_eth),
    .i_rx_ready_eth             (i_rx_ready_eth),
    .DAC_CTRL_SDIO              (DAC_CTRL_SDIO),
    .DAC_CTRL_SDENN             (DAC_CTRL_SDENN),
    .DAC_CTRL_SCLK              (DAC_CTRL_SCLK),
    .DAC_CTRL_RESETN            (DAC_CTRL_RESETN)
  );

  // ---------------------------------------------------------- stimulus --
  logic [31:0] in_mem [0:MAX_WORDS-1];
  int          n_in  = 0;
  int          in_idx = 0;
  bit          inj_en = 0;

  assign inject_cs22_riscv_in_valid = inj_en && (in_idx < n_in);
  assign inject_cs22_riscv_in_data  = (in_idx < n_in) ? in_mem[in_idx] : 32'h0;

  always @(posedge clk)
    if (inject_cs22_riscv_in_valid && inject_cs22_riscv_in_ready)
      in_idx <= in_idx + 1;

  // ----------------------------------------------------------- capture --
  logic [31:0] got[$];
  bit          seen_end = 0;

  always @(posedge clk)
    if (snap_cs22_riscv_out_valid && snap_cs22_riscv_out_ready) begin
      got.push_back(snap_cs22_riscv_out_data);
      if (snap_cs22_riscv_out_data == END_HEADER) seen_end = 1;
    end

  function automatic int read_hex(string path, ref logic [31:0] mem [0:MAX_WORDS-1]);
    int fd, n;
    logic [31:0] w;
    n = 0;
    fd = $fopen(path, "r");
    if (fd == 0) begin
      $display("FAIL: cannot open %s (run `make stream`)", path);
      $finish;
    end
    while (!$feof(fd) && $fscanf(fd, "%h\n", w) == 1) begin
      mem[n] = w;
      n++;
    end
    $fclose(fd);
    return n;
  endfunction

  initial begin
    int  fd, i;
    longint cyc;

    n_in = read_hex("in.hex", in_mem);
    $display("injecting %0d words", n_in);

    repeat (RESET_CYCLES/2 - 1) @(posedge clk);
    MIB_MASTER_RESET = 0;
    @(posedge clk);
    i_data_valid_adc = 1;   // postReset(top)
    // Hold the stream off until reset has settled. vex_machine_top's
    // valid-ready-prime input buffer writes on temp_valid && a one-cycle
    // delayed o_afull_n_d, which leaves reset a cycle after the port's
    // ready (o_afull_n). A word offered in that first cycle is acked but
    // never written. The Verilator TB starts its stream later, so it never
    // hits this.
    repeat (INJECT_DELAY) @(posedge clk);
    inj_en <= 1;

    cyc = 0;
    while (!seen_end && cyc < MAX_CYCLES) begin
      @(posedge clk);
      cyc++;
      if (cyc % 500000 == 0)
        $display("PROGRESS: %0d cycles, %0d words out", cyc, got.size());
    end
    repeat (FLUSH_CYCLES) @(posedge clk);

    $display("cs22out: %0d words, END after ~%0d cycles", got.size(), cyc);
    fd = $fopen("xsim_got.hex", "w");
    foreach (got[i]) $fwrite(fd, "%08x\n", got[i]);
    $fclose(fd);

    if (!seen_end) $display("FAIL: no END header from cs22");
    else           $display("xsim run complete (compare with `make xsim_compare`)");
    $finish;
  end

endmodule
