`timescale 1ns/1ps

module memory_slice_1_1 #(
    parameter MEMINIT = "vmem0.mif",
    parameter DEPTH = 4096,
    parameter W = 12,
    parameter WMO = 11,
    parameter EAB1 = 2
) (
    input wire clk,
    input wire reset_n,
    input wire [11:0] t0_addr,
    input wire [31:0] t0_data,
    input wire t0_we,
    input wire t0_valid,
    output wire t0_ready,
    output reg [11:0] i0_addr,
    output wire [31:0] i0_data,
    output reg i0_valid,
    input wire i0_ready,
    input wire [EAB1+11:0] t1_addr,
    input wire [31:0] t1_data,
    input wire t1_we,
    input wire t1_valid,
    output wire t1_ready,
    output reg [EAB1+11:0] i1_addr,
    output wire [31:0] i1_data,
    output reg i1_valid,
    input wire i1_ready
);
    reg [11:0] t0_addr_reg;
    reg [31:0] t0_data_reg;
    reg t0_we_reg;
    reg t0_valid_reg;
    reg [EAB1+11:0] t1_addr_reg;
    reg [31:0] t1_data_reg;
    reg t1_we_reg;
    reg t1_valid_reg;
    wire unused_sbiterra;
    wire unused_dbiterra;
    wire unused_sbiterrb;
    wire unused_dbiterrb;

    assign t0_ready = !t0_valid_reg || (i0_ready && i0_valid);
    assign t1_ready = !t1_valid_reg || (i1_ready && i1_valid);

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
        .addra(t0_addr_reg),
        .addrb(t1_addr_reg[WMO:0]),
        .clka(clk),
        .clkb(clk),
        .dina(t0_data_reg),
        .dinb(t1_data_reg),
        .douta(i0_data),
        .doutb(i1_data),
        .ena(t0_valid_reg),
        .enb(t1_valid_reg),
        .injectdbiterra(1'b0),
        .injectdbiterrb(1'b0),
        .injectsbiterra(1'b0),
        .injectsbiterrb(1'b0),
        .regcea(1'b1),
        .regceb(1'b1),
        .rsta(1'b0),
        .rstb(1'b0),
        .sbiterra(unused_sbiterra),
        .dbiterra(unused_dbiterra),
        .sbiterrb(unused_sbiterrb),
        .dbiterrb(unused_dbiterrb),
        .sleep(1'b0),
        .wea(t0_valid_reg && t0_we_reg),
        .web(t1_valid_reg && t1_we_reg)
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            t0_addr_reg <= '0;
            t0_data_reg <= '0;
            t0_we_reg <= 1'b0;
            t0_valid_reg <= 1'b0;
            i0_addr <= '0;
            i0_valid <= 1'b0;
        end else begin
            if (t0_ready && t0_valid) begin
                t0_addr_reg <= t0_addr;
                t0_data_reg <= t0_data;
                t0_we_reg <= t0_we;
                t0_valid_reg <= 1'b1;
            end else if (i0_ready && i0_valid) begin
                t0_valid_reg <= 1'b0;
            end

            if (t0_valid_reg && !i0_valid && !t0_we_reg) begin
                i0_addr <= t0_addr_reg;
                i0_valid <= 1'b1;
            end else if (i0_ready && i0_valid) begin
                i0_valid <= 1'b0;
            end else if (t0_valid_reg && t0_we_reg) begin
                t0_valid_reg <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            t1_addr_reg <= '0;
            t1_data_reg <= '0;
            t1_we_reg <= 1'b0;
            t1_valid_reg <= 1'b0;
            i1_addr <= '0;
            i1_valid <= 1'b0;
        end else begin
            if (t1_ready && t1_valid) begin
                t1_addr_reg <= t1_addr;
                t1_data_reg <= t1_data;
                t1_we_reg <= t1_we;
                t1_valid_reg <= 1'b1;
            end else if (i1_ready && i1_valid) begin
                t1_valid_reg <= 1'b0;
            end

            if (t1_valid_reg && !i1_valid && !t1_we_reg) begin
                i1_addr <= t1_addr_reg;
                i1_valid <= 1'b1;
            end else if (i1_ready && i1_valid) begin
                i1_valid <= 1'b0;
            end else if (t1_valid_reg && t1_we_reg) begin
                t1_valid_reg <= 1'b0;
            end
        end
    end
endmodule
