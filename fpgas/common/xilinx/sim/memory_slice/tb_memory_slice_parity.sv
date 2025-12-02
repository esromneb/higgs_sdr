// Shared parity harness for the Q-engine vector-memory leaf `memory_slice`.
// Drives the reference and Xilinx-selected implementations (instantiated
// side by side in `memory_slice_dual_top`) with identical stimulus and
// self-checks every output every cycle.  The same directed vectors,
// deterministic LFSR seed, and CSV schema are reproduced by the Verilator
// cycle-driver in `verilator_memory_slice_parity.cpp` (see that file and
// `README.md` for why the two harnesses differ).
//
// Same-address, same-cycle accesses across the two ports are excluded from
// the fuzz stimulus whenever either port is writing: the original RTL, and
// the real `xpm_memory_tdpram` primitive it is replaced with, both leave that
// case undefined (confirmed empirically -- see README.md).  Same-address
// concurrent *reads* are unaffected and are not excluded.
module tb_memory_slice_parity;

    localparam integer DEPTH = 16;

    reg clk = 1'b0;
    reg reset_n = 1'b0;

    reg [11:0] t0_addr;
    reg [31:0] t0_data;
    reg t0_we;
    reg t0_valid;
    reg i0_ready;

    reg [11:0] t1_addr;
    reg [31:0] t1_data;
    reg t1_we;
    reg t1_valid;
    reg i1_ready;

    wire ref_t0_ready, ref_i0_valid, ref_t1_ready, ref_i1_valid;
    wire [11:0] ref_i0_addr, ref_i1_addr;
    wire [31:0] ref_i0_data, ref_i1_data;

    wire xil_t0_ready, xil_i0_valid, xil_t1_ready, xil_i1_valid;
    wire [11:0] xil_i0_addr, xil_i1_addr;
    wire [31:0] xil_i0_data, xil_i1_data;

    integer trace;
    integer errors;
    integer cycle;
    integer index;
    reg [31:0] random_state;
    reg [8*256-1:0] trace_path;

    memory_slice_dual_top #(
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .t0_addr(t0_addr),
        .t0_data(t0_data),
        .t0_we(t0_we),
        .t0_valid(t0_valid),
        .i0_ready(i0_ready),
        .t1_addr(t1_addr),
        .t1_data(t1_data),
        .t1_we(t1_we),
        .t1_valid(t1_valid),
        .i1_ready(i1_ready),
        .ref_t0_ready(ref_t0_ready),
        .ref_i0_addr(ref_i0_addr),
        .ref_i0_data(ref_i0_data),
        .ref_i0_valid(ref_i0_valid),
        .ref_t1_ready(ref_t1_ready),
        .ref_i1_addr(ref_i1_addr),
        .ref_i1_data(ref_i1_data),
        .ref_i1_valid(ref_i1_valid),
        .xil_t0_ready(xil_t0_ready),
        .xil_i0_addr(xil_i0_addr),
        .xil_i0_data(xil_i0_data),
        .xil_i0_valid(xil_i0_valid),
        .xil_t1_ready(xil_t1_ready),
        .xil_i1_addr(xil_i1_addr),
        .xil_i1_data(xil_i1_data),
        .xil_i1_valid(xil_i1_valid)
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
            // Data is only compared when the shared output-valid signal is
            // asserted: it is a don't-care otherwise, and uninitialized
            // memory reads as 'x' from the plain-array reference but as 0
            // from the real `xpm_memory_tdpram` (a benign simulator/vendor
            // initialization-convention difference, not a functional bug).
            if (ref_t0_ready !== xil_t0_ready || ref_i0_addr !== xil_i0_addr ||
                ref_i0_valid !== xil_i0_valid ||
                (xil_i0_valid === 1'b1 && ref_i0_data !== xil_i0_data)) begin
                $display("port0 mismatch at cycle %0d: ref=%b/%h/%h/%b xil=%b/%h/%h/%b",
                         cycle, ref_t0_ready, ref_i0_addr, ref_i0_data, ref_i0_valid,
                         xil_t0_ready, xil_i0_addr, xil_i0_data, xil_i0_valid);
                errors = errors + 1;
            end
            if (ref_t1_ready !== xil_t1_ready || ref_i1_addr !== xil_i1_addr ||
                ref_i1_valid !== xil_i1_valid ||
                (xil_i1_valid === 1'b1 && ref_i1_data !== xil_i1_data)) begin
                $display("port1 mismatch at cycle %0d: ref=%b/%h/%h/%b xil=%b/%h/%h/%b",
                         cycle, ref_t1_ready, ref_i1_addr, ref_i1_data, ref_i1_valid,
                         xil_t1_ready, xil_i1_addr, xil_i1_data, xil_i1_valid);
                errors = errors + 1;
            end
            $fdisplay(trace, "%0d,%b,%b,%h,%b,%b,%h,%h,%b,%b,%b,%h,%b,%b,%h,%h,%b",
                      cycle, t0_valid, t0_we, t0_addr, i0_ready,
                      xil_t0_ready, xil_i0_addr, xil_i0_data, xil_i0_valid,
                      t1_valid, t1_we, t1_addr, i1_ready,
                      xil_t1_ready, xil_i1_addr, xil_i1_data, xil_i1_valid);
        end
    endtask

    task drive;
        input [3:0] addr0;
        input valid0;
        input we0;
        input [31:0] data0;
        input ready0;
        input [3:0] addr1;
        input valid1;
        input we1;
        input [31:0] data1;
        input ready1;
        begin
            t0_addr = {8'd0, addr0};
            t0_valid = valid0;
            t0_we = we0;
            t0_data = data0;
            i0_ready = ready0;
            t1_addr = {8'd0, addr1};
            t1_valid = valid1;
            t1_we = we1;
            t1_data = data1;
            i1_ready = ready1;
            check_and_trace();
        end
    endtask

    initial begin
        if (!$value$plusargs("TRACE=%s", trace_path))
            trace_path = "memory_slice_parity.csv";
        trace = $fopen(trace_path, "w");
        if (!trace) $fatal(1, "cannot open trace file");
        $fdisplay(trace,
                  "cycle,t0_valid,t0_we,t0_addr,i0_ready,xil_t0_ready,xil_i0_addr,xil_i0_data,xil_i0_valid,t1_valid,t1_we,t1_addr,i1_ready,xil_t1_ready,xil_i1_addr,xil_i1_data,xil_i1_valid");

        errors = 0;
        cycle = 0;
        random_state = 32'h1;
        t0_addr = 0; t0_data = 0; t0_we = 0; t0_valid = 0; i0_ready = 1;
        t1_addr = 0; t1_data = 0; t1_we = 0; t1_valid = 0; i1_ready = 1;

        // Reset assertion/deassertion.  `reset_n` is not consumed by either
        // implementation; this proves both remain identically unaffected.
        reset_n = 1'b0;
        drive(0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
        drive(0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
        reset_n = 1'b1;

        // Initialize every location with disjoint, non-colliding writes.
        for (index = 0; index < 8; index = index + 1)
            drive(index, 1, 1, 32'h1000_0000 + index, 1,
                  index + 8, 1, 1, 32'h2000_0000 + index, 1);

        // Directed port-0 backpressure: request a read, withhold i0_ready,
        // then release it, exercising the single-entry skid buffer.
        drive(3, 1, 0, 0, 0, 0, 0, 0, 0, 1);
        drive(3, 0, 0, 0, 0, 0, 0, 0, 0, 1);
        drive(3, 0, 0, 0, 0, 0, 0, 0, 0, 1);
        drive(3, 0, 0, 0, 1, 0, 0, 0, 0, 1);
        drive(0, 0, 0, 0, 1, 0, 0, 0, 0, 1);

        // Directed port-1 backpressure and its extra pipeline stage.
        drive(0, 0, 0, 0, 1, 9, 1, 0, 0, 0);
        drive(0, 0, 0, 0, 1, 9, 0, 0, 0, 0);
        drive(0, 0, 0, 0, 1, 9, 0, 0, 0, 1);
        drive(0, 0, 0, 0, 1, 0, 0, 0, 0, 1);

        // Same-address concurrent reads on both ports: defined and safe.
        drive(5, 1, 0, 0, 1, 5, 1, 0, 0, 1);
        drive(0, 0, 0, 0, 1, 0, 0, 0, 0, 1);

        // Idle cycle.
        drive(0, 0, 0, 0, 1, 0, 0, 0, 0, 1);

        // Deterministic fuzzing.  A write commits whenever `we` is asserted
        // on either port, independent of `valid` (confirmed in the original
        // RTL); the exclusion below matches that, not merely `valid && we`.
        for (index = 0; index < 500; index = index + 1) begin
            random_state = next_random(random_state);
            begin : fuzz_vars
                reg [3:0] addr0, addr1;
                reg valid0, we0, ready0, valid1, we1, ready1;
                reg [31:0] data0, data1;
                addr0 = random_state[3:0];
                valid0 = random_state[4];
                we0 = random_state[5];
                ready0 = random_state[6];
                data0 = random_state;
                random_state = next_random(random_state);
                addr1 = random_state[3:0];
                valid1 = random_state[4];
                we1 = random_state[5];
                ready1 = random_state[6];
                data1 = random_state;
                if (addr0 == addr1 && (we0 || we1))
                    addr1 = addr1 ^ 4'h1;
                drive(addr0, valid0, we0, data0, ready0,
                      addr1, valid1, we1, data1, ready1);
            end
        end

        $fclose(trace);
        if (errors != 0) $fatal(1, "memory_slice parity had %0d errors", errors);
        $display("PASS: memory_slice reference/Xilinx parity, directed and fuzz tests");
        $finish;
    end
endmodule
