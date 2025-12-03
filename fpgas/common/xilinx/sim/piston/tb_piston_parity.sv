`timescale 1ns/1ps

module tb_piston_parity;
    localparam int WRITES_PER_DMA = 32;
    localparam int READS_PER_DMA = 128;
    localparam int RESET_READS_PER_DMA = 8;

    logic clk = 0;
    logic reset_n = 0;
    logic [48:0] in_data [0:3];
    logic [3:0] in_valid = 0;
    wire [3:0] in_ready;
    wire [31:0] out_data [0:3];
    wire [3:0] out_valid;
    logic [3:0] out_ready = 0;

    int write_index [0:3];
    int reset_read_index [0:3];
    int read_index [0:3];
    logic [31:0] expected_q [0:3][$];
    logic [31:0] lfsr = 32'h36a9_7c51;
    int completed;
    int cycle;
    int fd;

    piston_test_top dut (
        .clk(clk),
        .reset_n(reset_n),
        .in0(in_data[0]),
        .in1(in_data[1]),
        .in2(in_data[2]),
        .in3(in_data[3]),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .out0(out_data[0]),
        .out1(out_data[1]),
        .out2(out_data[2]),
        .out3(out_data[3]),
        .out_valid(out_valid),
        .out_ready(out_ready)
    );

    always #5 clk = ~clk;

    function automatic logic [31:0] next_lfsr();
        logic [31:0] x;
        x = lfsr;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        lfsr = x;
        return x;
    endfunction

    function automatic logic [15:0] write_addr(input int owner, input int index);
        logic [11:0] row;
        logic [3:0] bank;
        row = owner * WRITES_PER_DMA + index;
        bank = (index * 5 + owner * 3) & 15;
        return {row, bank};
    endfunction

    function automatic logic [31:0] write_data(input int owner, input int index);
        return 32'he000_0000 | (owner << 16) | index;
    endfunction

    function automatic logic [15:0] read_addr(input int dma, input int index);
        int owner;
        int write_slot;
        owner = (index * 3 + dma) & 3;
        write_slot = (index * 7 + dma * 11) % WRITES_PER_DMA;
        return write_addr(owner, write_slot);
    endfunction

    function automatic logic [31:0] read_data(input int dma, input int index);
        int owner;
        int write_slot;
        owner = (index * 3 + dma) & 3;
        write_slot = (index * 7 + dma * 11) % WRITES_PER_DMA;
        return write_data(owner, write_slot);
    endfunction

    task automatic check_outputs();
        for (int dma = 0; dma < 4; dma++) begin
            if (out_valid[dma]) begin
                if (expected_q[dma].size() == 0)
                    $fatal(1, "dma%0d unexpected response at cycle %0d",
                           dma, cycle);
                if (out_data[dma] !== expected_q[dma][0])
                    $fatal(1, "dma%0d mismatch expected=%08x got=%08x cycle=%0d",
                           dma, expected_q[dma][0], out_data[dma], cycle);
            end
        end
    endtask

    task automatic clear_expected();
        for (int dma = 0; dma < 4; dma++)
            expected_q[dma].delete();
    endtask

    task automatic log_cycle();
        $fdisplay(fd, "%0d,%0d,%0h,%0h,%0h,%0h,%0h,%0h,%0h,%0h,%0h,%0h,%0h,%0h",
                  cycle, reset_n, in_valid, in_ready,
                  in_data[0], in_data[1], in_data[2], in_data[3],
                  out_ready, out_valid, out_data[0], out_data[1],
                  out_data[2], out_data[3]);
    endtask

    initial begin
        string trace_path;
        logic [31:0] random_bits;
        logic [3:0] input_fire;
        logic [3:0] output_fire;
        bit all_done;

        if (!$value$plusargs("TRACE=%s", trace_path))
            trace_path = "trace.csv";
        fd = $fopen(trace_path, "w");
        $fdisplay(fd, "cycle,resetn,in_valid,in_ready,in0,in1,in2,in3,out_ready,out_valid,out0,out1,out2,out3");

        for (int dma = 0; dma < 4; dma++)
            in_data[dma] = 0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        reset_n = 1;

        all_done = 0;
        while (!all_done) begin
            random_bits = next_lfsr();
            for (int dma = 0; dma < 4; dma++) begin
                if (!in_valid[dma] && write_index[dma] < WRITES_PER_DMA
                    && random_bits[dma]) begin
                    in_data[dma] = {
                        1'b1,
                        write_addr(dma, write_index[dma]),
                        write_data(dma, write_index[dma])
                    };
                    in_valid[dma] = 1'b1;
                end
            end
            #1;
            input_fire = in_valid & in_ready;
            @(posedge clk);
            #1;
            for (int dma = 0; dma < 4; dma++) begin
                if (input_fire[dma]) begin
                    write_index[dma]++;
                    in_valid[dma] = 1'b0;
                end
            end
            all_done = 1;
            for (int dma = 0; dma < 4; dma++)
                if (write_index[dma] != WRITES_PER_DMA)
                    all_done = 0;
        end

        in_valid = 0;
        repeat (100) @(posedge clk);

        all_done = 0;
        while (!all_done) begin
            for (int dma = 0; dma < 4; dma++) begin
                if (!in_valid[dma]
                    && reset_read_index[dma] < RESET_READS_PER_DMA) begin
                    in_data[dma] = {
                        1'b0,
                        read_addr(dma, reset_read_index[dma]),
                        32'b0
                    };
                    in_valid[dma] = 1'b1;
                end
            end
            out_ready = 0;
            #1;
            input_fire = in_valid & in_ready;
            @(posedge clk);
            #1;
            for (int dma = 0; dma < 4; dma++) begin
                if (input_fire[dma]) begin
                    reset_read_index[dma]++;
                    in_valid[dma] = 1'b0;
                end
            end
            all_done = 1;
            for (int dma = 0; dma < 4; dma++)
                if (reset_read_index[dma] != RESET_READS_PER_DMA)
                    all_done = 0;
        end

        repeat (30) @(posedge clk);
        if (out_valid == 0)
            $fatal(1, "reset test failed to queue responses");
        @(negedge clk);
        reset_n = 0;
        in_valid = 0;
        repeat (5) @(posedge clk);
        clear_expected();
        @(negedge clk);
        reset_n = 1;
        repeat (5) @(posedge clk);
        if (out_valid != 0)
            $fatal(1, "reset did not discard piston responses");

        cycle = 0;
        while (completed < 4 * READS_PER_DMA) begin
            random_bits = next_lfsr();
            for (int dma = 0; dma < 4; dma++) begin
                if (!in_valid[dma] && read_index[dma] < READS_PER_DMA
                    && random_bits[dma]) begin
                    in_data[dma] = {
                        1'b0,
                        read_addr(dma, read_index[dma]),
                        32'b0
                    };
                    in_valid[dma] = 1'b1;
                end
            end
            out_ready = random_bits[7:4];
            #1;
            check_outputs();
            input_fire = in_valid & in_ready;
            output_fire = out_valid & out_ready;
            @(posedge clk);
            #1;
            cycle++;

            for (int dma = 0; dma < 4; dma++) begin
                if (output_fire[dma]) begin
                    void'(expected_q[dma].pop_front());
                    completed++;
                end
                if (input_fire[dma]) begin
                    expected_q[dma].push_back(read_data(dma, read_index[dma]));
                    read_index[dma]++;
                    in_valid[dma] = 1'b0;
                end
            end
            check_outputs();
            log_cycle();
            if (cycle > 30000)
                $fatal(1, "read phase timeout completed=%0d", completed);
        end

        $fclose(fd);
        $display("PASS: piston preserved 512 ordered VMEM reads through its stalled external DMA interfaces");
        $finish;
    end

    initial begin
        #800000;
        $fatal(1, "global timeout");
    end
endmodule
