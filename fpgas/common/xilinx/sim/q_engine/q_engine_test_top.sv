module q_engine_test_top (
    input wire clk,
    input wire srst,
    input wire [31:0] in_data,
    input wire in_last,
    input wire in_valid,
    output wire in_ready,
    output wire [31:0] out_data,
    output wire out_last,
    output wire out_valid,
    input wire out_ready,
    output wire [21:0] gpio
);
    wire proc_interrupt;
    wire [31:0] control;
    wire [1023:0] mapmov_mover_active;
    wire [31:0] mapmov_trim_start;
    wire [31:0] mapmov_trim_end;
    wire [9:0] mapmov_pilot_ram_addr;
    wire [31:0] mapmov_pilot_ram_wdata;
    wire mapmov_pilot_ram_we;
    wire mapmov_reset;
    wire [15:0] mapmov_one_value;
    wire [15:0] mapmov_zero_value;
    wire ringbus_0;
    wire ringbus_1;
    wire uart_txd;
    wire jtag_tdo;

    q_engine dut (
        .clk(clk),
        .srst(srst),
        .debugReset(srst),
        .t0_data(in_data),
        .t0_last(in_last),
        .t0_valid(in_valid),
        .t0_ready(in_ready),
        .i0_data(out_data),
        .i0_last(out_last),
        .i0_valid(out_valid),
        .i0_ready(out_ready),
        .proc_interrupt(proc_interrupt),
        .sat_detect(1'b0),
        .gpio(gpio),
        .status(32'b0),
        .control(control),
        .mapmov_mover_active(mapmov_mover_active),
        .mapmov_trim_start(mapmov_trim_start),
        .mapmov_trim_end(mapmov_trim_end),
        .mapmov_pilot_ram_addr(mapmov_pilot_ram_addr),
        .mapmov_pilot_ram_wdata(mapmov_pilot_ram_wdata),
        .mapmov_pilot_ram_we(mapmov_pilot_ram_we),
        .mapmov_reset(mapmov_reset),
        .mapmov_one_value(mapmov_one_value),
        .mapmov_zero_value(mapmov_zero_value),
        .i_ringbus_0(1'b1),
        .o_ringbus_0(ringbus_0),
        .i_ringbus_1(1'b1),
        .o_ringbus_1(ringbus_1),
        .io_uart_txd(uart_txd),
        .io_uart_rxd(1'b1),
        .jtag_tms(1'b0),
        .jtag_tdi(1'b0),
        .jtag_tdo(jtag_tdo),
        .jtag_tck(1'b0)
    );
endmodule
