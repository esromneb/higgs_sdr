module alu54b_wrapper_xilinx (
    input wire [35:0] a,
    input wire [35:0] b,
    input wire subadd,
    input wire ce,
    output reg [54:0] c,
    input wire clk,
    input wire rst
);
    wire signed [36:0] a_extended = {a[35], a};
    wire signed [36:0] b_extended = {b[35], b};
    wire signed [36:0] arithmetic_result =
        subadd ? a_extended - b_extended : a_extended + b_extended;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            c <= '0;
        end else begin
            c <= {{18{arithmetic_result[36]}}, arithmetic_result};
        end
    end
endmodule
