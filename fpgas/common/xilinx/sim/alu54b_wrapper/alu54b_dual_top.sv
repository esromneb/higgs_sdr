// Structural-only wrapper instantiating the renamed legacy reference
// `alu54b_wrapper` (build-generated copy, forced down its `VERILATE`
// behavioral branch) side by side with the real `alu54b_wrapper_xilinx`,
// exposing `ref_*`/`xil_*` outputs for direct comparison. Used unmodified by
// both XSIM and Verilator.
module alu54b_dual_top (
    input wire clk,
    input wire rst,
    input wire [35:0] a,
    input wire [35:0] b,
    input wire subadd,
    input wire ce,
    output wire [54:0] ref_c,
    output wire [54:0] xil_c
);

    alu54b_wrapper_ref ref_inst (
        .a(a),
        .b(b),
        .subadd(subadd),
        .ce(ce),
        .c(ref_c),
        .clk(clk),
        .rst(rst)
    );

    alu54b_wrapper_xilinx xil_inst (
        .a(a),
        .b(b),
        .subadd(subadd),
        .ce(ce),
        .c(xil_c),
        .clk(clk),
        .rst(rst)
    );

endmodule
