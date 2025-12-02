// XSIM parity testbench for `vex_machine_top`
// (fpgas/common/modules/vex_machine_top.v).
//
// Mirrors verilator_vex_machine_top_parity.cpp: same reset/warmup/capture
// cycle counts, same tie-offs, same trace columns and the same i0_data
// don't-care gating (masked to 0 whenever i0_valid is low). See that file
// and README.md for the rationale and overall scope of this harness.
//
// Deliberately has no `` `timescale `` directive of its own: XSIM's
// `xelab` requires every module in a design to consistently either have
// or lack a timescale, and almost none of the ~55 leaf files reachable
// from vex_machine_top declare one (see the Makefile's fifo_patch comment
// for the one exception, stripped at build time). Without an explicit
// timescale, `#5` below resolves to 5 of the simulator's default time
// unit, which is irrelevant here since only relative edge counts (not
// absolute times) are ever compared between simulators.

module tb_vex_machine_top_parity;

  localparam int RESET_CYCLES = 20;
  localparam int WARMUP_CYCLES = 500;
  localparam int CAPTURE_CYCLES = 6000;

  logic clk = 0;
  always #5 clk = ~clk;

  logic reset = 1;
  logic debugReset = 0;

  logic [31:0] t0_data = 0;
  logic        t0_last = 0;
  logic        t0_valid = 0;
  logic        t0_ready;

  logic [31:0] i0_data;
  logic        i0_last;
  logic        i0_valid;
  logic        i0_ready = 1;

  logic [31:0] outside_status = 0;
  logic [31:0] outside_control;

  logic        io_uart_txd;
  logic        io_uart_rxd = 1;

  logic        sat_detect = 0;
  wire  [21:0] gpio; // left undriven here; DUT's tri-state drivers are the
                      // sole driver, matching the Verilator side.
  logic        i_ringbus = 0;
  logic        o_ringbus;

  vex_machine_top dut (
    .clk             (clk),
    .reset           (reset),
    .debugReset      (debugReset),
    .t0_data         (t0_data),
    .t0_last         (t0_last),
    .t0_valid        (t0_valid),
    .t0_ready        (t0_ready),
    .i0_data         (i0_data),
    .i0_last         (i0_last),
    .i0_valid        (i0_valid),
    .i0_ready        (i0_ready),
    .outside_status  (outside_status),
    .outside_control (outside_control),
    .io_uart_txd     (io_uart_txd),
    .io_uart_rxd     (io_uart_rxd),
    .sat_detect      (sat_detect),
    .gpio            (gpio),
    .i_ringbus       (i_ringbus),
    .o_ringbus       (o_ringbus)
  );

  int trace_file;
  string trace_path;
  longint cycle;

  initial begin
    if (!$value$plusargs("TRACE=%s", trace_path)) trace_path = "trace.csv";
    trace_file = $fopen(trace_path, "w");
    $fdisplay(trace_file, "cycle,t0_ready,i0_valid,i0_data,io_uart_txd,gpio");

    cycle = 0;
    repeat (RESET_CYCLES) @(posedge clk);
    reset = 0;

    repeat (WARMUP_CYCLES) @(posedge clk);

    repeat (CAPTURE_CYCLES) begin
      @(posedge clk);
      cycle++;
      begin
        // i0_data is architecturally meaningless whenever i0_valid is low;
        // see verilator_vex_machine_top_parity.cpp for the rationale.
        logic [31:0] i0_data_reported;
        i0_data_reported = i0_valid ? i0_data : 32'h0;
        $fdisplay(trace_file, "%0d,%0d,%0d,%08x,%0d,%06x",
                  cycle, t0_ready, i0_valid, i0_data_reported, io_uart_txd,
                  gpio & 22'h3fffff);
      end
    end

    $fclose(trace_file);
    $display("vex_machine_top: ran %0d capture cycles, wrote trace to %s",
              CAPTURE_CYCLES, trace_path);
    $finish;
  end

endmodule
