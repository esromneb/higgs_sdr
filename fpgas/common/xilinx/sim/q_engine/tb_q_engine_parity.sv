`timescale 1ns/1ps

module tb_q_engine_parity;
    localparam int TRANSFERS = 64;

    logic clk = 0;
    logic srst = 1;
    logic [31:0] in_data = 0;
    logic in_last = 0;
    logic in_valid = 0;
    wire in_ready;
    wire [31:0] out_data;
    wire out_last;
    wire out_valid;
    logic out_ready = 0;
    wire [21:0] gpio;

    logic [31:0] lfsr = 32'h8c27_4a19;
    logic [31:0] expected_q[$];
    int sent;
    int received;
    int cycle;
    int fd;

    q_engine_test_top dut (.*);

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

    function automatic logic [31:0] payload(input int index);
        return 32'h5100_0000 | index;
    endfunction

    initial begin
        string trace_path;
        logic [31:0] random_bits;
        bit input_fire;
        bit output_fire;

        if (!$value$plusargs("TRACE=%s", trace_path))
            trace_path = "trace.csv";
        fd = $fopen(trace_path, "w");
        $fdisplay(fd, "cycle,in_valid,in_ready,in_data,in_last,out_ready,out_valid,out_data,out_last");

        repeat (8) @(posedge clk);
        @(negedge clk);
        srst = 0;

        while (received < TRANSFERS) begin
            random_bits = next_lfsr();
            if (!in_valid && sent < TRANSFERS && random_bits[0]) begin
                in_data = payload(sent);
                in_last = sent == TRANSFERS - 1;
                in_valid = 1;
            end
            out_ready = random_bits[1];

            #1;
            if (out_valid) begin
                if (expected_q.size() == 0)
                    $fatal(1, "unexpected q_engine output cycle=%0d", cycle);
                if (out_data !== expected_q[0])
                    $fatal(1, "q_engine data mismatch expected=%08x got=%08x cycle=%0d",
                           expected_q[0], out_data, cycle);
                if (out_last !== (received == TRANSFERS - 1))
                    $fatal(1, "q_engine last mismatch cycle=%0d", cycle);
            end
            input_fire = in_valid && in_ready;
            output_fire = out_valid && out_ready;

            $fdisplay(fd, "%0d,%0d,%0d,%08x,%0d,%0d,%0d,%08x,%0d",
                      cycle, in_valid, in_ready, in_data, in_last,
                      out_ready, out_valid, out_valid ? out_data : 0,
                      out_valid ? out_last : 0);
            @(posedge clk);
            #1;
            cycle++;

            if (output_fire) begin
                void'(expected_q.pop_front());
                received++;
            end
            if (input_fire) begin
                expected_q.push_back(in_data);
                sent++;
                in_valid = 0;
            end

            if (cycle > 30000)
                $fatal(1, "q_engine timeout sent=%0d received=%0d", sent, received);
        end

        if (sent != TRANSFERS || expected_q.size() != 0)
            $fatal(1, "q_engine scoreboard did not drain");
        $fclose(fd);
        $display("PASS: q_engine firmware DMA loopback preserved 64 stalled stream transactions");
        $finish;
    end
endmodule
