`timescale 1ns/1ps

module tb_vmem_dat_6_5;
    localparam int WRITES_PER_DMA = 32;
    localparam int READS_PER_DMA = 128;
    localparam int RESET_READS_PER_DMA = 8;

    logic clk = 0;
    logic reset_n = 0;
    logic [48:0] t_idma [0:3];
    logic [3:0] idma_valid = 0;
    wire [3:0] idma_ready;
    wire [31:0] i_odma [0:3];
    wire [3:0] odma_valid;
    logic [3:0] odma_ready = 0;
    logic [511:0] t_ivs_dat = 0;
    logic [195:0] t_ka_dat = 0;
    logic tvs_valid = 0;
    wire tvs_ready;
    wire [511:0] i_ovs_dat;
    wire ivs_valid;
    logic ivs_ready = 1;
    wire [3:0] k_ctrl;

    int write_index [0:3];
    int reset_read_index [0:3];
    int read_index [0:3];
    logic [31:0] expected_q [0:3][$];
    logic [31:0] lfsr = 32'h6d5a_1f37;
    int completed;
    int cycle;

    vmem_dat_6_5_1_1 dut (
        .t_idma_0_dat(t_idma[0]),
        .t_idma_1_dat(t_idma[1]),
        .t_idma_2_dat(t_idma[2]),
        .t_idma_3_dat(t_idma[3]),
        .idma_valid(idma_valid),
        .idma_ready(idma_ready),
        .i_odma_0_dat(i_odma[0]),
        .i_odma_1_dat(i_odma[1]),
        .i_odma_2_dat(i_odma[2]),
        .i_odma_3_dat(i_odma[3]),
        .odma_valid(odma_valid),
        .odma_ready(odma_ready),
        .t_ivs_dat(t_ivs_dat),
        .t_ka_dat(t_ka_dat),
        .tvs_valid(tvs_valid),
        .tvs_ready(tvs_ready),
        .i_ovs_dat(i_ovs_dat),
        .ivs_valid(ivs_valid),
        .ivs_ready(ivs_ready),
        .k_ctrl(k_ctrl),
        .clk(clk),
        .reset_n(reset_n)
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
        return 32'hc000_0000 | (owner << 16) | index;
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
            if (odma_valid[dma]) begin
                if (expected_q[dma].size() == 0)
                    $fatal(1, "dma%0d produced an unexpected response at cycle %0d",
                           dma, cycle);
                if (i_odma[dma] !== expected_q[dma][0])
                    $fatal(1, "dma%0d response mismatch expected=%08x got=%08x cycle=%0d",
                           dma, expected_q[dma][0], i_odma[dma], cycle);
            end
        end
    endtask

    task automatic clear_expected();
        for (int dma = 0; dma < 4; dma++)
            expected_q[dma].delete();
    endtask

    task automatic vector_write_read_check();
        logic [511:0] expected_vector;
        begin
            @(negedge clk);
            for (int slice = 0; slice < 16; slice++) begin
                t_ka_dat[slice*12 +: 12] = 12'h300 + slice;
                t_ivs_dat[slice*32 +: 32] = 32'hd000_0000 | slice;
            end
            t_ka_dat[195:192] = 4'h0;
            tvs_valid = 1'b1;
            do @(posedge clk); while (!tvs_ready);
            @(negedge clk);
            tvs_valid = 1'b0;

            repeat (20) @(posedge clk);
            @(negedge clk);
            t_ka_dat[195:192] = 4'h8;
            tvs_valid = 1'b1;
            do @(posedge clk); while (!tvs_ready);
            @(negedge clk);
            tvs_valid = 1'b0;
            ivs_ready = 1'b0;

            while (!ivs_valid) @(negedge clk);
            for (int slice = 0; slice < 16; slice++)
                expected_vector[slice*32 +: 32] = 32'hd000_0000 | slice;
            if (i_ovs_dat !== expected_vector)
                $fatal(1, "vector read mismatch");
            repeat (4) begin
                @(negedge clk);
                if (!ivs_valid || i_ovs_dat !== expected_vector)
                    $fatal(1, "vector response changed under backpressure");
            end
            ivs_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            ivs_ready = 1'b0;
            if (ivs_valid)
                $fatal(1, "vector response did not retire");
            ivs_ready = 1'b1;
        end
    endtask

    initial begin
        logic [31:0] random_bits;
        logic [3:0] input_fire;
        logic [3:0] output_fire;
        bit all_done;

        for (int dma = 0; dma < 4; dma++)
            t_idma[dma] = 0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        reset_n = 1;

        all_done = 0;
        while (!all_done) begin
            random_bits = next_lfsr();
            for (int dma = 0; dma < 4; dma++) begin
                if (!idma_valid[dma] && write_index[dma] < WRITES_PER_DMA
                    && random_bits[dma]) begin
                    t_idma[dma] = {
                        1'b1,
                        write_addr(dma, write_index[dma]),
                        write_data(dma, write_index[dma])
                    };
                    idma_valid[dma] = 1'b1;
                end
            end
            #1;
            input_fire = idma_valid & idma_ready;
            @(posedge clk);
            #1;
            cycle++;
            for (int dma = 0; dma < 4; dma++) begin
                if (input_fire[dma]) begin
                    write_index[dma]++;
                    idma_valid[dma] = 1'b0;
                end
            end
            all_done = 1;
            for (int dma = 0; dma < 4; dma++)
                if (write_index[dma] != WRITES_PER_DMA)
                    all_done = 0;
            if (cycle > 10000)
                $fatal(1, "write phase timeout");
        end

        idma_valid = 0;
        repeat (80) @(posedge clk);
        vector_write_read_check();

        all_done = 0;
        while (!all_done) begin
            random_bits = next_lfsr();
            for (int dma = 0; dma < 4; dma++) begin
                if (!idma_valid[dma]
                    && reset_read_index[dma] < RESET_READS_PER_DMA) begin
                    t_idma[dma] = {
                        1'b0,
                        read_addr(dma, reset_read_index[dma]),
                        32'b0
                    };
                    idma_valid[dma] = 1'b1;
                end
            end
            odma_ready = 0;
            #1;
            input_fire = idma_valid & idma_ready;
            @(posedge clk);
            #1;
            cycle++;
            for (int dma = 0; dma < 4; dma++) begin
                if (input_fire[dma]) begin
                    reset_read_index[dma]++;
                    idma_valid[dma] = 1'b0;
                end
            end
            all_done = 1;
            for (int dma = 0; dma < 4; dma++)
                if (reset_read_index[dma] != RESET_READS_PER_DMA)
                    all_done = 0;
        end

        repeat (20) @(posedge clk);
        if (odma_valid == 0)
            $fatal(1, "reset test failed to queue in-flight responses");
        @(negedge clk);
        reset_n = 0;
        idma_valid = 0;
        repeat (4) @(posedge clk);
        clear_expected();
        @(negedge clk);
        reset_n = 1;
        repeat (4) @(posedge clk);
        if (odma_valid != 0)
            $fatal(1, "reset did not discard queued responses");

        while (completed < 4 * READS_PER_DMA) begin
            random_bits = next_lfsr();
            for (int dma = 0; dma < 4; dma++) begin
                if (!idma_valid[dma] && read_index[dma] < READS_PER_DMA
                    && random_bits[dma]) begin
                    t_idma[dma] = {
                        1'b0,
                        read_addr(dma, read_index[dma]),
                        32'b0
                    };
                    idma_valid[dma] = 1'b1;
                end
            end
            odma_ready = random_bits[7:4];
            #1;
            check_outputs();
            input_fire = idma_valid & idma_ready;
            output_fire = odma_valid & odma_ready;
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
                    idma_valid[dma] = 1'b0;
                end
            end
            check_outputs();
            if (cycle > 30000)
                $fatal(1, "read phase timeout completed=%0d", completed);
        end

        idma_valid = 0;
        odma_ready = 4'hf;
        repeat (8) @(posedge clk);
        for (int dma = 0; dma < 4; dma++) begin
            if (expected_q[dma].size() != 0 || odma_valid[dma])
                $fatal(1, "dma%0d did not drain", dma);
        end

        $display("PASS: vmem_dat_6_5_1_1 preserved 512 ordered reads across four stalled DMA ports and reset in flight");
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "global timeout");
    end
endmodule
