module core_top #(
    parameter integer CLOCK_SHIFT_TRAINING_COUNTER_LIMIT = 100,
    parameter integer NUM_SYS_CLK_SRSTS = 1,
    parameter SYS_CLK_SRSTS_EXTRA_CLOCKS = 0,
    parameter integer NUM_MIB_CLK_SRSTS = 1,
    parameter MIB_CLK_SRSTS_EXTRA_CLOCKS = 0,
    parameter integer INT_OSC_DIV_VAL = 12,
    parameter integer NUM_INT_OSC_SRST_CLOCKS = 128,
    parameter bit [3:0] MIB_SLAVE_ADDR_MSN = 4'h0,
    parameter bit MIB_CLOCK_DESKEW_ENABLE = 1'b1,
    parameter bit INCLUDE_MIB_SLAVE = 1'b1,
    parameter bit VERILATE = 1'b0
) (
    input wire logic i_fpga_clk,
    input wire logic i_fpga_ext_arst,
    output wire logic o_int_osc_clk,
    output wire logic o_int_osc_clk_srst,
    output wire logic o_sys_clk,
    output wire logic o_sys_clk_srsts,
    output wire logic o_mib_clk,
    output wire logic o_mib_clk_srsts,
    output wire logic o_mib_deskew_done,
    output wire logic o_sys_pll_locked,
    input wire logic i_mib_tbit,
    input wire logic i_mib_start,
    input wire logic i_mib_rd_wr_n,
    inout wire logic [15:0] b_mib_ad,
    output wire logic o_mib_slave_ack,
    intf_cmd.master cmd_sys
);
    sys_pll sys_pll (
        .CLKI(i_fpga_clk),
        .CLKOP(o_sys_clk),
        .CLKOS(o_mib_clk),
        .PHASESEL(2'b00),
        .PHASEDIR(1'b0),
        .PHASESTEP(1'b0),
        .PHASELOADREG(1'b0),
        .LOCK(o_sys_pll_locked)
    );

    assign o_int_osc_clk = i_fpga_clk;
    assign o_int_osc_clk_srst = i_fpga_ext_arst;
    assign o_sys_clk_srsts = i_fpga_ext_arst | ~o_sys_pll_locked;
    assign o_mib_clk_srsts = i_fpga_ext_arst | ~o_sys_pll_locked;
    assign o_mib_deskew_done = 1'b1;
    assign b_mib_ad = 16'bz;
    assign o_mib_slave_ack = 1'b0;
endmodule
