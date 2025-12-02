module tb_scalar_memory_xilinx;

    localparam integer DEPTH = 8;

    reg clk = 1'b0;
    reg srst = 1'b0;
    reg t0_valid, t0_we;
    reg [3:0] t0_mask;
    reg [31:0] t0_addr, t0_data;
    wire t0_ready;
    wire i0_valid;
    reg i0_ready = 1'b1;
    wire [31:0] i0_data;
    reg t1_valid, t1_we;
    reg [3:0] t1_mask;
    reg [31:0] t1_addr, t1_data;
    wire t1_ready;
    wire i1_valid;
    reg i1_ready = 1'b1;
    wire [31:0] i1_data;

    reg [31:0] expected [0:DEPTH-1];
    reg [31:0] random_state;
    reg [8*256-1:0] trace_path;
    integer trace;
    integer errors;
    integer cycle;
    integer index;
    reg [2:0] fuzz_addr0, fuzz_addr1;
    reg fuzz_we0, fuzz_we1;
    reg [3:0] fuzz_mask0, fuzz_mask1;
    reg [31:0] fuzz_data0, fuzz_data1;

    scalar_memory_xilinx #(
        .AWIDTH(3),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .srst(srst),
        .t0_valid(t0_valid),
        .t0_ready(t0_ready),
        .t0_we(t0_we),
        .t0_mask(t0_mask),
        .t0_addr(t0_addr),
        .t0_data(t0_data),
        .i0_valid(i0_valid),
        .i0_ready(i0_ready),
        .i0_data(i0_data),
        .t1_valid(t1_valid),
        .t1_ready(t1_ready),
        .t1_we(t1_we),
        .t1_mask(t1_mask),
        .t1_addr(t1_addr),
        .t1_data(t1_data),
        .i1_valid(i1_valid),
        .i1_ready(i1_ready),
        .i1_data(i1_data)
    );

    always #5 clk = ~clk;

    function [31:0] next_random;
        input [31:0] value;
        begin
            next_random = {value[30:0], value[31] ^ value[21] ^ value[1] ^ value[0]};
        end
    endfunction

    function [31:0] masked_write;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0] byte_enable;
        begin
            masked_write = old_value;
            if (byte_enable[0]) masked_write[7:0] = new_value[7:0];
            if (byte_enable[1]) masked_write[15:8] = new_value[15:8];
            if (byte_enable[2]) masked_write[23:16] = new_value[23:16];
            if (byte_enable[3]) masked_write[31:24] = new_value[31:24];
        end
    endfunction

    task drive_and_check;
        input [2:0] addr0;
        input valid0;
        input write0;
        input [3:0] mask0;
        input [31:0] data0;
        input [2:0] addr1;
        input valid1;
        input write1;
        input [3:0] mask1;
        input [31:0] data1;
        begin
            @(negedge clk);
            t0_addr = {27'd0, addr0, 2'b00};
            t0_valid = valid0;
            t0_we = write0;
            t0_mask = mask0;
            t0_data = data0;
            t1_addr = {27'd0, addr1, 2'b00};
            t1_valid = valid1;
            t1_we = write1;
            t1_mask = mask1;
            t1_data = data1;

            @(posedge clk);
            #1;
            cycle = cycle + 1;
            if (valid0 && !write0 && (!i0_valid || i0_data !== expected[addr0])) begin
                $display("port 0 mismatch at cycle %0d: got valid=%b data=%h expected=%h",
                         cycle, i0_valid, i0_data, expected[addr0]);
                errors = errors + 1;
            end
            if (valid1 && !write1 && (!i1_valid || i1_data !== expected[addr1])) begin
                $display("port 1 mismatch at cycle %0d: got valid=%b data=%h expected=%h",
                         cycle, i1_valid, i1_data, expected[addr1]);
                errors = errors + 1;
            end
            $fdisplay(trace, "%0d,%b,%b,%h,%b,%h,%b,%b,%h,%b,%h",
                      cycle, valid0, write0, t0_addr, i0_valid, i0_data,
                      valid1, write1, t1_addr, i1_valid, i1_data);
            if (valid0 && write0)
                expected[addr0] = masked_write(expected[addr0], data0, mask0);
            if (valid1 && write1)
                expected[addr1] = masked_write(expected[addr1], data1, mask1);
        end
    endtask

    initial begin
        if (!$value$plusargs("TRACE=%s", trace_path))
            trace_path = "scalar_memory_xilinx.csv";
        trace = $fopen(trace_path, "w");
        if (!trace) $fatal(1, "cannot open trace file");
        $fdisplay(trace, "cycle,t0_valid,t0_we,t0_addr,i0_valid,i0_data,t1_valid,t1_we,t1_addr,i1_valid,i1_data");

        errors = 0;
        cycle = 0;
        random_state = 32'h1;
        t0_valid = 0;
        t0_we = 0;
        t0_mask = 0;
        t0_addr = 0;
        t0_data = 0;
        t1_valid = 0;
        t1_we = 0;
        t1_mask = 0;
        t1_addr = 0;
        t1_data = 0;
        for (index = 0; index < DEPTH; index = index + 1)
            expected[index] = 0;

        // Initialize every location using concurrent, non-colliding writes.
        for (index = 0; index < 4; index = index + 1)
            drive_and_check(index, 1, 1, 4'hf, 32'h1020_3040 + index,
                            index + 4, 1, 1, 4'hf, 32'h5060_7080 + index);

        // Directed byte enables, read latency, idle cycles, and dual-port reads.
        drive_and_check(3'd2, 1, 1, 4'b0101, 32'haabb_ccdd,
                        3'd5, 1, 1, 4'b1010, 32'h1122_3344);
        drive_and_check(3'd2, 1, 0, 4'h0, 32'h0,
                        3'd5, 1, 0, 4'h0, 32'h0);
        drive_and_check(3'd0, 0, 0, 4'h0, 32'h0,
                        3'd0, 0, 0, 4'h0, 32'h0);

        // Deterministic fuzzing excludes undefined same-address write collisions.
        for (index = 0; index < 400; index = index + 1) begin
            random_state = next_random(random_state);
            fuzz_addr0 = random_state[2:0];
            fuzz_we0 = random_state[3];
            fuzz_mask0 = random_state[7:4];
            fuzz_data0 = random_state;
            random_state = next_random(random_state);
            fuzz_addr1 = random_state[2:0];
            fuzz_we1 = random_state[3];
            fuzz_mask1 = random_state[7:4];
            fuzz_data1 = random_state;
            if (fuzz_addr0 == fuzz_addr1 && (fuzz_we0 || fuzz_we1))
                fuzz_addr1 = fuzz_addr1 ^ 3'b001;
            drive_and_check(fuzz_addr0, 1, fuzz_we0, fuzz_mask0, fuzz_data0,
                            fuzz_addr1, 1, fuzz_we1, fuzz_mask1, fuzz_data1);
        end

        $fclose(trace);
        if (errors != 0) $fatal(1, "scalar_memory_xilinx had %0d errors", errors);
        $display("PASS: scalar_memory_xilinx directed and fuzz tests");
        $finish;
    end
endmodule
