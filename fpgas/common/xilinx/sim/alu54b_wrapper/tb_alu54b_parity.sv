// Parity harness for `alu54b_wrapper` (libs/datapath/rtl/alu54b_wrapper.v)
// vs. its Xilinx replacement `alu54b_wrapper_xilinx.sv`
// (libs/datapath/rtl/alu54b_wrapper_xilinx.sv). Both are genuinely distinct
// implementation files (unlike `muladdsub`, which shares one source between
// VERILATE and HIGGS_FPGA_XILINX), so this test follows the `memory_slice`
// pattern: a dual instantiation (`alu54b_dual_top.sv`) directly compares
// the legacy reference (`alu54b_wrapper.v`'s `VERILATE` behavioral branch --
// the only branch either open-source simulator can run; the real Lattice
// `ALU54B` hardware primitive path is out of scope) against the Xilinx
// implementation every cycle.
//
// Note: neither implementation actually gates the output register on `ce`
// for simulation purposes -- both compute the add/sub unconditionally every
// clock (the real Lattice `ALU54B` primitive's CE0 pin is only meaningful to
// the excluded hardware-primitive path). `ce` is still driven with varied
// values here so that a future accidental divergence between the two
// implementations would be caught.
module tb_alu54b_parity;

    reg clk = 1'b0;
    reg rst = 1'b0;
    reg [35:0] a, b;
    reg subadd;
    reg ce;

    wire [54:0] ref_c, xil_c;

    integer trace;
    integer errors;
    integer cycle;
    reg [31:0] random_state;
    reg [8*256-1:0] trace_path;

    alu54b_dual_top dut (
        .clk(clk),
        .rst(rst),
        .a(a),
        .b(b),
        .subadd(subadd),
        .ce(ce),
        .ref_c(ref_c),
        .xil_c(xil_c)
    );

    always #5 clk = ~clk;

    function [31:0] next_random;
        input [31:0] value;
        begin
            next_random = {value[30:0], value[31] ^ value[21] ^ value[1] ^ value[0]};
        end
    endfunction

    task check_and_trace;
        begin
            @(posedge clk);
            #1;
            cycle = cycle + 1;

            if (ref_c !== xil_c) begin
                $display("mismatch at cycle %0d: ref=%h xil=%h", cycle, ref_c, xil_c);
                errors = errors + 1;
            end

            $fdisplay(trace, "%0d,%b,%b,%h,%h,%b,%h",
                      cycle, rst, ce, a, b, subadd, xil_c);
        end
    endtask

    task drive;
        input r;
        input c;
        input [35:0] ta;
        input [35:0] tb;
        input sa;
        begin
            rst = r;
            ce = c;
            a = ta;
            b = tb;
            subadd = sa;
            check_and_trace();
        end
    endtask

    initial begin
        if (!$value$plusargs("TRACE=%s", trace_path))
            trace_path = "alu54b_parity.csv";
        trace = $fopen(trace_path, "w");
        if (!trace) $fatal(1, "cannot open trace file");
        $fdisplay(trace, "cycle,rst,ce,a,b,subadd,xil_c");

        errors = 0;
        cycle = 0;
        random_state = 32'h1;
        rst = 1'b0; ce = 1'b0; a = 36'b0; b = 36'b0; subadd = 1'b0;

        // Reset assertion/deassertion.
        drive(1, 1, 0, 0, 0);
        drive(1, 1, 0, 0, 0);
        drive(0, 1, 0, 0, 0);

        // Basic add/sub with small positive values.
        drive(0, 1, 36'd10, 36'd3, 0);
        drive(0, 1, 36'd10, 36'd3, 1);
        drive(0, 1, 36'd0, 36'd0, 0);
        drive(0, 1, 36'd0, 36'd0, 0);

        // Signed extremes: max positive / max negative 36-bit operands.
        drive(0, 1, 36'h07FFFFFFFF, 36'h07FFFFFFFF, 0);
        drive(0, 1, 36'h800000000, 36'h800000000, 1);
        drive(0, 1, 36'h07FFFFFFFF, 36'h800000000, 0);
        drive(0, 1, 36'h800000000, 36'h07FFFFFFFF, 1);
        drive(0, 1, 36'd0, 36'd0, 0);
        drive(0, 1, 36'd0, 36'd0, 0);

        // ce toggling: proves no accidental divergence if either
        // implementation later gates on it.
        drive(0, 0, 36'd42, 36'd7, 0);
        drive(0, 0, 36'd99, 36'd1, 1);
        drive(0, 1, 36'd5, 36'd5, 0);
        drive(0, 0, 36'd5, 36'd5, 0);
        drive(0, 1, 36'd0, 36'd0, 0);

        // Idle cycle.
        drive(0, 1, 36'd0, 36'd0, 0);

        // Deterministic fuzz: random 36-bit signed operands, subadd, ce.
        for (integer index = 0; index < 1000; index = index + 1) begin
            reg [35:0] fa, fb;
            random_state = next_random(random_state);
            fa = {random_state[3:0], random_state};
            subadd = random_state[4];
            ce = random_state[5];
            random_state = next_random(random_state);
            fb = {random_state[3:0], random_state};
            rst = 1'b0;
            a = fa;
            b = fb;
            check_and_trace();
        end

        if (errors == 0)
            $display("PASS: alu54b_wrapper reference/Xilinx parity, directed and fuzz tests");
        else
            $display("FAIL: %0d alu54b_wrapper mismatches", errors);

        $fclose(trace);
        $finish;
    end

endmodule
