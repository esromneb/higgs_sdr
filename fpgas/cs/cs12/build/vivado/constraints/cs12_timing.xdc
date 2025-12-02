create_clock -name clk_125m -period 8.000 [get_ports CLK]

create_generated_clock -name sys_clk -source [get_ports CLK] -divide_by 1 \
    [get_pins core_top/sys_pll/clkop_bufg/O]
