// Structural-only wrapper instantiating the legacy reference `memory_slice`
// implementation alongside the Xilinx-selected replacement so a single
// stimulus source can drive both and a checker can compare every output each
// cycle.  This file has no procedural code and no delays, so it compiles
// unmodified under both XSIM and Verilator; only the underlying true
// dual-port RAM primitive differs between simulators (the real
// `xpm_memory_tdpram` under XSIM, a Verilator-compatible behavioral stand-in
// under Verilator -- see `xpm_memory_tdpram_verilator_model.sv`).
//
// `memory_slice_ref` and `memory_slice_xil` are build-generated, renamed
// copies of `libs/q-engine/piston/hdl/memory_slice.v` and
// `fpgas/common/xilinx/memory_slice_xilinx.v` (see `Makefile`); the tracked
// sources are never modified.
module memory_slice_dual_top #(
    parameter DEPTH = 16
) (
    input wire clk,
    input wire reset_n,

    input wire [11:0] t0_addr,
    input wire [31:0] t0_data,
    input wire t0_we,
    input wire t0_valid,
    input wire i0_ready,

    input wire [11:0] t1_addr,
    input wire [31:0] t1_data,
    input wire t1_we,
    input wire t1_valid,
    input wire i1_ready,

    output wire ref_t0_ready,
    output wire [11:0] ref_i0_addr,
    output wire [31:0] ref_i0_data,
    output wire ref_i0_valid,
    output wire ref_t1_ready,
    output wire [11:0] ref_i1_addr,
    output wire [31:0] ref_i1_data,
    output wire ref_i1_valid,

    output wire xil_t0_ready,
    output wire [11:0] xil_i0_addr,
    output wire [31:0] xil_i0_data,
    output wire xil_i0_valid,
    output wire xil_t1_ready,
    output wire [11:0] xil_i1_addr,
    output wire [31:0] xil_i1_data,
    output wire xil_i1_valid
);

    memory_slice_ref #(
        .MEMINIT("vmem0.mif"),
        .DEPTH  (DEPTH)
    ) ref_dut (
        .clk(clk),
        .reset_n(reset_n),
        .t0_addr(t0_addr),
        .t0_data(t0_data),
        .t0_we(t0_we),
        .t0_valid(t0_valid),
        .t0_ready(ref_t0_ready),
        .i0_addr(ref_i0_addr),
        .i0_data(ref_i0_data),
        .i0_valid(ref_i0_valid),
        .i0_ready(i0_ready),
        .t1_addr(t1_addr),
        .t1_data(t1_data),
        .t1_we(t1_we),
        .t1_valid(t1_valid),
        .t1_ready(ref_t1_ready),
        .i1_addr(ref_i1_addr),
        .i1_data(ref_i1_data),
        .i1_valid(ref_i1_valid),
        .i1_ready(i1_ready)
    );

    memory_slice_xil #(
        .MEMINIT("vmem0.mif"),
        .DEPTH  (DEPTH)
    ) xil_dut (
        .clk(clk),
        .reset_n(reset_n),
        .t0_addr(t0_addr),
        .t0_data(t0_data),
        .t0_we(t0_we),
        .t0_valid(t0_valid),
        .t0_ready(xil_t0_ready),
        .i0_addr(xil_i0_addr),
        .i0_data(xil_i0_data),
        .i0_valid(xil_i0_valid),
        .i0_ready(i0_ready),
        .t1_addr(t1_addr),
        .t1_data(t1_data),
        .t1_we(t1_we),
        .t1_valid(t1_valid),
        .t1_ready(xil_t1_ready),
        .i1_addr(xil_i1_addr),
        .i1_data(xil_i1_data),
        .i1_valid(xil_i1_valid),
        .i1_ready(i1_ready)
    );

endmodule
