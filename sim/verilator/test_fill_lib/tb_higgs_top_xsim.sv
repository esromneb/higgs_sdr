// XSIM parity testbench for Jenkins test_fill_lib. It boots the same CS20
// firmware and checks the exact VMEM rows written by fill.h/fill.c.

module tb_higgs_top_xsim;

  localparam int RESET_CYCLES = 40;
  localparam int TICK_CYCLES = 50 * 500;

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

  logic [31:0] ring_items[$];

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
    if (ring_bus_i0_ready && ringbus_out_data_vld) begin
      ring_items.push_back(ringbus_out_data);
      $display("0x%08h", ringbus_out_data);
    end
  end

  initial begin
    int row;
    bit fail;

    repeat (RESET_CYCLES/2 - 1) @(posedge clk);
    MIB_MASTER_RESET = 0;
    @(posedge clk);
    i_data_valid_adc = 1;

    repeat (TICK_CYCLES) @(posedge clk);

    fail = 0;
    if (ring_items.size() != 2) begin
      $display("FAIL: fill test ring-bus count %0d != 2", ring_items.size());
      fail = 1;
    end else if (ring_items[0] !== 32'hdeadbeef ||
                 ring_items[1] !== 32'h00000000) begin
        $display("FAIL: fill test ring-bus sequence mismatch");
        fail = 1;
    end

    for (row = 0; row < 8; row++) begin
      if (dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_0.dpram_inst.mem[row] !== 32'hdead ||
          dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_1.dpram_inst.mem[row] !== 32'hdead ||
          dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_2.dpram_inst.mem[row] !== 32'hdead ||
          dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_3.dpram_inst.mem[row] !== 32'hdead ||
          dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_4.dpram_inst.mem[row] !== 32'hdead ||
          dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_5.dpram_inst.mem[row] !== 32'hdead ||
          dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_6.dpram_inst.mem[row] !== 32'hdead ||
          dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_7.dpram_inst.mem[row] !== 32'hdead ||
          dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_8.dpram_inst.mem[row] !== 32'hdead ||
          dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_9.dpram_inst.mem[row] !== 32'hdead ||
          dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_10.dpram_inst.mem[row] !== 32'hdead ||
          dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_11.dpram_inst.mem[row] !== 32'hdead ||
          dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_12.dpram_inst.mem[row] !== 32'hdead ||
          dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_13.dpram_inst.mem[row] !== 32'hdead ||
          dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_14.dpram_inst.mem[row] !== 32'hdead ||
          dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_15.dpram_inst.mem[row] !== 32'hdead) begin
        $display("FAIL: VMEM dead fill mismatch in row %0d", row);
        fail = 1;
      end
    end

    if (dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_0.dpram_inst.mem[8] !== 32'hcafe ||
        dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_1.dpram_inst.mem[8] !== 32'hcafe ||
        dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_2.dpram_inst.mem[8] !== 32'hcafe ||
        dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_3.dpram_inst.mem[8] !== 32'hcafe ||
        dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_4.dpram_inst.mem[8] !== 32'hcafe ||
        dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_5.dpram_inst.mem[8] !== 32'hcafe ||
        dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_6.dpram_inst.mem[8] !== 32'hcafe ||
        dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_7.dpram_inst.mem[8] !== 32'hcafe ||
        dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_8.dpram_inst.mem[8] !== 32'hcafe ||
        dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_9.dpram_inst.mem[8] !== 32'hcafe ||
        dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_10.dpram_inst.mem[8] !== 32'hcafe ||
        dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_11.dpram_inst.mem[8] !== 32'hcafe ||
        dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_12.dpram_inst.mem[8] !== 32'hcafe ||
        dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_13.dpram_inst.mem[8] !== 32'hcafe ||
        dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_14.dpram_inst.mem[8] !== 32'hcafe ||
        dut.cs20_top.vex_machine_top_inst.q_engine_inst.piston_inst.unode28.mem_slice_15.dpram_inst.mem[8] !== 32'hcafe) begin
      $display("FAIL: VMEM cafe fill mismatch in row 8");
      fail = 1;
    end

    if (!fail)
      $display("All Tests Passed");
    $finish;
  end

endmodule
