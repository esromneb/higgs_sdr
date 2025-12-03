`timescale 1ns/1ps

module tb_memory_slice_1_1;
    reg clk = 1'b0;
    reg reset_n = 1'b0;

    reg [11:0] t0_addr = 0;
    reg [31:0] t0_data = 0;
    reg t0_we = 0;
    reg t0_valid = 0;
    wire t0_ready;
    wire [11:0] i0_addr;
    wire [31:0] i0_data;
    wire i0_valid;
    reg i0_ready = 0;

    reg [13:0] t1_addr = 0;
    reg [31:0] t1_data = 0;
    reg t1_we = 0;
    reg t1_valid = 0;
    wire t1_ready;
    wire [13:0] i1_addr;
    wire [31:0] i1_data;
    wire i1_valid;
    reg i1_ready = 0;

    memory_slice_1_1 #(.DEPTH(4096)) dut (
        .clk(clk),
        .reset_n(reset_n),
        .t0_addr(t0_addr),
        .t0_data(t0_data),
        .t0_we(t0_we),
        .t0_valid(t0_valid),
        .t0_ready(t0_ready),
        .i0_addr(i0_addr),
        .i0_data(i0_data),
        .i0_valid(i0_valid),
        .i0_ready(i0_ready),
        .t1_addr(t1_addr),
        .t1_data(t1_data),
        .t1_we(t1_we),
        .t1_valid(t1_valid),
        .t1_ready(t1_ready),
        .i1_addr(i1_addr),
        .i1_data(i1_data),
        .i1_valid(i1_valid),
        .i1_ready(i1_ready)
    );

    always #5 clk = ~clk;

    task automatic send0(
        input [11:0] addr,
        input [31:0] data,
        input bit we
    );
        begin
            @(negedge clk);
            t0_addr = addr;
            t0_data = data;
            t0_we = we;
            t0_valid = 1'b1;
            do @(posedge clk); while (!t0_ready);
            @(negedge clk);
            t0_valid = 1'b0;
        end
    endtask

    task automatic send1(
        input [13:0] addr,
        input [31:0] data,
        input bit we
    );
        begin
            @(negedge clk);
            t1_addr = addr;
            t1_data = data;
            t1_we = we;
            t1_valid = 1'b1;
            do @(posedge clk); while (!t1_ready);
            @(negedge clk);
            t1_valid = 1'b0;
        end
    endtask

    task automatic expect0(
        input [11:0] addr,
        input [31:0] data,
        input integer stall_cycles
    );
        integer n;
        begin
            i0_ready = 1'b0;
            while (!i0_valid) @(negedge clk);
            if (i0_addr !== addr || i0_data !== data)
                $fatal(1, "port 0 mismatch addr=%h/%h data=%h/%h",
                       i0_addr, addr, i0_data, data);
            for (n = 0; n < stall_cycles; n = n + 1) begin
                @(negedge clk);
                if (!i0_valid || i0_addr !== addr || i0_data !== data)
                    $fatal(1, "port 0 response changed under backpressure");
            end
            i0_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            i0_ready = 1'b0;
        end
    endtask

    task automatic expect1(
        input [13:0] addr,
        input [31:0] data,
        input integer stall_cycles
    );
        integer n;
        begin
            i1_ready = 1'b0;
            while (!i1_valid) @(negedge clk);
            if (i1_addr !== addr || i1_data !== data)
                $fatal(1, "port 1 mismatch addr=%h/%h data=%h/%h",
                       i1_addr, addr, i1_data, data);
            for (n = 0; n < stall_cycles; n = n + 1) begin
                @(negedge clk);
                if (!i1_valid || i1_addr !== addr || i1_data !== data)
                    $fatal(1, "port 1 response changed under backpressure");
            end
            i1_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            i1_ready = 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset_n = 1'b1;

        send0(12'h021, 32'h1020_3040, 1'b1);
        send1(14'h1055, 32'h5566_7788, 1'b1);
        send0(12'h0a4, 32'hdead_beef, 1'b1);
        send1(14'h2b6c, 32'hc001_cafe, 1'b1);

        fork
            send0(12'h021, 32'b0, 1'b0);
            send1(14'h1055, 32'b0, 1'b0);
        join
        fork
            expect0(12'h021, 32'h1020_3040, 3);
            expect1(14'h1055, 32'h5566_7788, 5);
        join

        fork
            begin
                send0(12'h0a4, 32'b0, 1'b0);
                expect0(12'h0a4, 32'hdead_beef, 0);
            end
            begin
                send1(14'h2b6c, 32'b0, 1'b0);
                expect1(14'h2b6c, 32'hc001_cafe, 2);
            end
        join

        $display("PASS: memory_slice_1_1 preserved data, tags, and responses under backpressure");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "timeout");
    end
endmodule
