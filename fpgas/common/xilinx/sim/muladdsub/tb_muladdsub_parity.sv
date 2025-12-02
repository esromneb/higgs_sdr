// Parity harness for `muladdsub` (libs/datapath/rtl/muladdsub.v), the
// multiply-add/sub DSP macro instantiated throughout Q-engine `piston.v`.
//
// Unlike `memory_slice`, this leaf has no separate Xilinx implementation
// file: `HIGGS_FPGA_XILINX` and `VERILATE` both select the exact same
// `HIGGS_MULADDSUB_BEHAVIORAL_IMPL` branch inside `muladdsub.v` (the
// original Lattice `ALU54B`/`MULT18X18D` primitive path is used only for the
// real Lattice hardware build and cannot be simulated by either open-source
// tool here). This test therefore does two things:
//   1. Self-checks the DUT every cycle against an independent behavioral
//      model of the same 3-stage CE-gated pipeline, written directly from
//      the RTL's documented semantics (catches a bug common to both
//      simulators, not just a cross-simulator disagreement).
//   2. Cross-simulator CSV trace comparison (XSIM compiles the DUT with
//      `+define+HIGGS_FPGA_XILINX`, matching the real CS12 Vivado build;
//      Verilator compiles it with `+define+VERILATE`, this repo's existing
//      convention -- both select identical source lines).
module tb_muladdsub_parity;

    reg clk = 1'b0;
    reg rst = 1'b0;
    reg ce0, ce1, ce2;
    reg addnsub;
    reg [17:0] a0, a1, b0, b1;

    wire [35:0] sum;

    integer trace;
    integer errors;
    integer cycle;
    reg [31:0] random_state;
    reg [8*256-1:0] trace_path;

    // Independent behavioral model of the 3-stage pipeline, mirroring
    // muladdsub.v's HIGGS_MULADDSUB_BEHAVIORAL_IMPL branch exactly.
    reg [17:0] m_a0_r, m_a1_r, m_b0_r, m_b1_r;
    reg signed [35:0] m_ab0_r, m_ab1_r;
    reg signed [35:0] m_ab_r;

    muladdsub dut (
        .CLK0(clk),
        .CE0(ce0),
        .CE1(ce1),
        .CE2(ce2),
        .RST0(rst),
        .ADDNSUB(addnsub),
        .A0(a0),
        .A1(a1),
        .B0(b0),
        .B1(b1),
        .SUM(sum)
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
            // Model update: all three stages read pre-edge state, mirroring
            // the RTL's independent always blocks sampling the same
            // pre-edge registers before any of them commit.
            begin : model_update
                reg [17:0] old_a0_r, old_a1_r, old_b0_r, old_b1_r;
                reg signed [35:0] old_ab0_r, old_ab1_r;
                old_a0_r = m_a0_r; old_a1_r = m_a1_r;
                old_b0_r = m_b0_r; old_b1_r = m_b1_r;
                old_ab0_r = m_ab0_r; old_ab1_r = m_ab1_r;

                if (rst) begin
                    m_a0_r <= 18'b0; m_a1_r <= 18'b0;
                    m_b0_r <= 18'b0; m_b1_r <= 18'b0;
                end else if (ce0) begin
                    m_a0_r <= a0; m_a1_r <= a1;
                    m_b0_r <= b0; m_b1_r <= b1;
                end

                if (rst) begin
                    m_ab0_r <= 36'sb0; m_ab1_r <= 36'sb0;
                end else if (ce1) begin
                    m_ab0_r <= $signed(old_a0_r) * $signed(old_b0_r);
                    m_ab1_r <= $signed(old_a1_r) * $signed(old_b1_r);
                end

                if (rst) begin
                    m_ab_r <= 36'sb0;
                end else if (ce2) begin
                    m_ab_r <= addnsub ? (old_ab0_r + old_ab1_r)
                                       : (old_ab0_r - old_ab1_r);
                end
            end
            #1;
            cycle = cycle + 1;

            if (sum !== m_ab_r) begin
                $display("mismatch at cycle %0d: dut=%h model=%h", cycle, sum, m_ab_r);
                errors = errors + 1;
            end

            $fdisplay(trace, "%0d,%b,%b,%b,%b,%b,%h,%h,%h,%h,%h",
                      cycle, rst, ce0, ce1, ce2, addnsub, a0, a1, b0, b1, sum);
        end
    endtask

    task drive;
        input r;
        input c0;
        input c1;
        input c2;
        input asub;
        input [17:0] ta0;
        input [17:0] ta1;
        input [17:0] tb0;
        input [17:0] tb1;
        begin
            rst = r;
            ce0 = c0;
            ce1 = c1;
            ce2 = c2;
            addnsub = asub;
            a0 = ta0;
            a1 = ta1;
            b0 = tb0;
            b1 = tb1;
            check_and_trace();
        end
    endtask

    initial begin
        if (!$value$plusargs("TRACE=%s", trace_path))
            trace_path = "muladdsub_parity.csv";
        trace = $fopen(trace_path, "w");
        if (!trace) $fatal(1, "cannot open trace file");
        $fdisplay(trace, "cycle,rst,ce0,ce1,ce2,addnsub,a0,a1,b0,b1,sum");

        errors = 0;
        cycle = 0;
        random_state = 32'h1;
        rst = 1'b0; ce0 = 1'b0; ce1 = 1'b0; ce2 = 1'b0; addnsub = 1'b0;
        a0 = 18'b0; a1 = 18'b0; b0 = 18'b0; b1 = 18'b0;
        m_a0_r = 0; m_a1_r = 0; m_b0_r = 0; m_b1_r = 0;
        m_ab0_r = 0; m_ab1_r = 0; m_ab_r = 0;

        // Reset assertion/deassertion with CEs already high.
        drive(1, 1, 1, 1, 0, 0, 0, 0, 0);
        drive(1, 1, 1, 1, 0, 0, 0, 0, 0);
        drive(0, 1, 1, 1, 0, 0, 0, 0, 0);

        // Flow-through: distinct small positive values, all CEs held high.
        drive(0, 1, 1, 1, 0, 18'd3, 18'd5, 18'd7, 18'd11);
        drive(0, 1, 1, 1, 1, 18'd3, 18'd5, 18'd7, 18'd11);
        drive(0, 1, 1, 1, 0, 18'd0, 18'd0, 18'd0, 18'd0);
        drive(0, 1, 1, 1, 0, 18'd0, 18'd0, 18'd0, 18'd0);
        drive(0, 1, 1, 1, 0, 18'd0, 18'd0, 18'd0, 18'd0);

        // Signed extremes: max positive and max negative 18-bit operands.
        drive(0, 1, 1, 1, 0, 18'h1FFFF, 18'h1FFFF, 18'h1FFFF, 18'h1FFFF);
        drive(0, 1, 1, 1, 1, 18'h20000, 18'h20000, 18'h20000, 18'h20000);
        drive(0, 1, 1, 1, 0, 18'h20000, 18'h1FFFF, 18'h1FFFF, 18'h20000);
        drive(0, 1, 1, 1, 0, 18'd0, 18'd0, 18'd0, 18'd0);
        drive(0, 1, 1, 1, 0, 18'd0, 18'd0, 18'd0, 18'd0);
        drive(0, 1, 1, 1, 0, 18'd0, 18'd0, 18'd0, 18'd0);

        // CE0 gating: freeze stage 1 while inputs keep changing.
        drive(0, 1, 1, 1, 0, 18'd9, 18'd2, 18'd4, 18'd1);
        drive(0, 0, 1, 1, 0, 18'd99, 18'd88, 18'd77, 18'd66);
        drive(0, 0, 1, 1, 0, 18'd55, 18'd44, 18'd33, 18'd22);
        drive(0, 1, 1, 1, 0, 18'd1, 18'd1, 18'd1, 18'd1);
        drive(0, 1, 1, 1, 0, 18'd0, 18'd0, 18'd0, 18'd0);
        drive(0, 1, 1, 1, 0, 18'd0, 18'd0, 18'd0, 18'd0);
        drive(0, 1, 1, 1, 0, 18'd0, 18'd0, 18'd0, 18'd0);

        // CE1 gating: freeze stage 2 (the multiply result) mid-flow.
        drive(0, 1, 1, 1, 0, 18'd6, 18'd3, 18'd2, 18'd9);
        drive(0, 1, 0, 1, 0, 18'd1, 18'd1, 18'd1, 18'd1);
        drive(0, 1, 0, 1, 0, 18'd2, 18'd2, 18'd2, 18'd2);
        drive(0, 1, 1, 1, 0, 18'd0, 18'd0, 18'd0, 18'd0);
        drive(0, 1, 1, 1, 0, 18'd0, 18'd0, 18'd0, 18'd0);
        drive(0, 1, 1, 1, 0, 18'd0, 18'd0, 18'd0, 18'd0);

        // CE2 gating: freeze the final add/sub output mid-flow.
        drive(0, 1, 1, 1, 0, 18'd10, 18'd4, 18'd3, 18'd2);
        drive(0, 1, 1, 0, 1, 18'd1, 18'd1, 18'd1, 18'd1);
        drive(0, 1, 1, 0, 1, 18'd2, 18'd2, 18'd2, 18'd2);
        drive(0, 1, 1, 1, 0, 18'd0, 18'd0, 18'd0, 18'd0);
        drive(0, 1, 1, 1, 0, 18'd0, 18'd0, 18'd0, 18'd0);
        drive(0, 1, 1, 1, 0, 18'd0, 18'd0, 18'd0, 18'd0);

        // Idle cycle with all CEs low.
        drive(0, 0, 0, 0, 0, 18'd0, 18'd0, 18'd0, 18'd0);

        // Deterministic fuzz: random operands, CE gating, and ADDNSUB.
        for (integer index = 0; index < 1000; index = index + 1) begin
            random_state = next_random(random_state);
            a0 = random_state[17:0];
            addnsub = random_state[18];
            ce0 = random_state[19];
            random_state = next_random(random_state);
            a1 = random_state[17:0];
            ce1 = random_state[18];
            random_state = next_random(random_state);
            b0 = random_state[17:0];
            ce2 = random_state[18];
            random_state = next_random(random_state);
            b1 = random_state[17:0];
            rst = 1'b0;
            check_and_trace();
        end

        if (errors == 0)
            $display("PASS: muladdsub self-check and directed/fuzz tests");
        else
            $display("FAIL: %0d muladdsub mismatches", errors);

        $fclose(trace);
        $finish;
    end

endmodule
