module sys_pll (
    input wire CLKI,
    input wire [1:0] PHASESEL,
    input wire PHASEDIR,
    input wire PHASESTEP,
    input wire PHASELOADREG,
    output wire CLKOP,
    output wire CLKOS,
    output wire LOCK
);
    wire clkfb;
    wire clkop_unbuffered;
    wire clkos_unbuffered;

    MMCME4_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(8.0),
        .CLKIN1_PERIOD(8.0),
        .CLKOUT0_DIVIDE_F(8.0),
        .CLKOUT1_DIVIDE(128),
        .DIVCLK_DIVIDE(1),
        .STARTUP_WAIT("FALSE")
    ) mmcm (
        .CLKFBOUT(clkfb),
        .CLKFBOUTB(),
        .CLKOUT0(clkop_unbuffered),
        .CLKOUT0B(),
        .CLKOUT1(clkos_unbuffered),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .CLKFBIN(clkfb),
        .CLKIN1(CLKI),
        .PWRDWN(1'b0),
        .RST(1'b0),
        .LOCKED(LOCK)
    );

    BUFG clkop_bufg (.I(clkop_unbuffered), .O(CLKOP));
    BUFG clkos_bufg (.I(clkos_unbuffered), .O(CLKOS));
endmodule
