module memory_slice #(parameter MEMINIT = "vmem0.mif", parameter DEPTH = 4096) (
    input clk,
    input reset_n,
    input wire [11:0] t0_addr,
    input wire [31:0] t0_data,
    input t0_we,
    input wire t0_valid,
    output wire t0_ready,
    output reg [11:0] i0_addr,
    output wire [31:0] i0_data,
    output reg i0_valid,
    input wire i0_ready,
    input wire [11:0] t1_addr,
    input wire [31:0] t1_data,
    input t1_we,
    input wire t1_valid,
    output wire t1_ready,
    output reg [11:0] i1_addr,
    output reg [31:0] i1_data,
    output reg i1_valid,
    input wire i1_ready
);
    wire [31:0] i1_data_nxt;
    reg i1_valid_nxt;
    reg [11:0] i1_addr_nxt;
    wire re_0;

    dpram #(.MEMINIT(MEMINIT), .DEPTH(DEPTH)) dpram_inst (
        .clk(clk),
        .addr_0(t0_addr),
        .din_0(t0_data),
        .we_0(t0_we),
        .re_0(re_0),
        .dout_0(i0_data),
        .addr_1(t1_addr),
        .din_1(t1_data),
        .we_1(t1_we),
        .dout_1(i1_data_nxt)
    );

    assign t0_ready = ~i0_valid | i0_ready;
    assign t1_ready = ~i1_valid | i1_ready;
    assign re_0 = (~t0_we && t0_valid) & t0_ready;

    always @(posedge clk) begin
        i0_valid <= (~t0_we && t0_valid) | ~t0_ready;
        i1_valid_nxt <= (~t1_we && t1_valid) | ~t1_ready;
        i1_valid <= i1_valid_nxt;
        i1_data <= i1_data_nxt;
        i0_addr <= t0_addr;
        i1_addr_nxt <= t1_addr;
        i1_addr <= i1_addr_nxt;
    end
endmodule

module dpram #(parameter DEPTH = 4096, parameter MEMINIT = "vmem0.mif") (
    input clk,
    input [11:0] addr_0,
    input [31:0] din_0,
    input we_0,
    input re_0,
    output wire [31:0] dout_0,
    input [11:0] addr_1,
    input [31:0] din_1,
    input we_1,
    output wire [31:0] dout_1
);
    xpm_memory_tdpram #(
        .ADDR_WIDTH_A($clog2(DEPTH)),
        .ADDR_WIDTH_B($clog2(DEPTH)),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(32),
        .BYTE_WRITE_WIDTH_B(32),
        .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(DEPTH * 32),
        .MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_A(32),
        .READ_DATA_WIDTH_B(32),
        .READ_LATENCY_A(1),
        .READ_LATENCY_B(1),
        .READ_RESET_VALUE_A("0"),
        .READ_RESET_VALUE_B("0"),
        .RST_MODE_A("SYNC"),
        .RST_MODE_B("SYNC"),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT(0),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(32),
        .WRITE_DATA_WIDTH_B(32),
        .WRITE_MODE_A("write_first"),
        .WRITE_MODE_B("write_first")
    ) memory (
        .addra(addr_0),
        .addrb(addr_1),
        .clka(clk),
        .clkb(clk),
        .dina(din_0),
        .dinb(din_1),
        .douta(dout_0),
        .doutb(dout_1),
        .ena(re_0 | we_0),
        .enb(1'b1),
        .injectdbiterra(1'b0),
        .injectdbiterrb(1'b0),
        .injectsbiterra(1'b0),
        .injectsbiterrb(1'b0),
        .regcea(1'b1),
        .regceb(1'b1),
        .rsta(1'b0),
        .rstb(1'b0),
        .sleep(1'b0),
        .wea(we_0),
        .web(we_1)
    );
endmodule
