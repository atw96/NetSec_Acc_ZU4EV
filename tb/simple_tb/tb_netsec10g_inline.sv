// 64-bit switch: BIST does not inspect, INLINE crosses inj frames, LOOP returns port 0.
`timescale 1ns / 1ps

module tb_netsec10g_inline;
    logic clk = 0, rst_n = 0;
    always #3.2 clk = ~clk;

    logic [1:0] mode, dp_en;
    logic inj_start;
    logic [511:0] pats;
    logic [63:0] rx0_d, rx1_d, tx0_d, tx1_d;
    logic [7:0]  rx0_k, rx1_k, tx0_k, tx1_k;
    logic rx0_v, rx0_r, rx0_l, rx0_u;
    logic rx1_v, rx1_r, rx1_l, rx1_u;
    logic tx0_v, tx0_r, tx0_l, tx0_u;
    logic tx1_v, tx1_r, tx1_l, tx1_u;
    logic [1:0] last0, last1;
    logic p_rx0, p_tx0, p_fwd0, p_drop0, p_mir0, p_dpi0;
    logic p_rx1, p_tx1, p_fwd1, p_drop1, p_mir1, p_dpi1;
    logic p_csum0, p_csum1, p_ovf0, p_ovf1, p_flow0, p_flow1;
    logic [15:0] p_phit0, p_phit1;
    logic [127:0] ct0, ct1;
    logic done0, done1, fold0, fold1;

    netsec10g_switch64 #(
        .HASH_BITS(8), .ROM_PATTERNS(4), .AES_LANES(1), .FIFO_BYTES(4096), .DLY(20)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .mode(mode), .dp_en(dp_en),
        .aes0_en(1'b0), .aes1_en(1'b0), .aes_key(128'd0),
        .pats(pats), .inj_start(inj_start),
        .rx0_tdata(rx0_d), .rx0_tkeep(rx0_k), .rx0_tvalid(rx0_v),
        .rx0_tready(rx0_r), .rx0_tlast(rx0_l), .rx0_tuser(rx0_u),
        .rx1_tdata(rx1_d), .rx1_tkeep(rx1_k), .rx1_tvalid(rx1_v),
        .rx1_tready(rx1_r), .rx1_tlast(rx1_l), .rx1_tuser(rx1_u),
        .tx0_tdata(tx0_d), .tx0_tkeep(tx0_k), .tx0_tvalid(tx0_v),
        .tx0_tready(tx0_r), .tx0_tlast(tx0_l), .tx0_tuser(tx0_u),
        .tx1_tdata(tx1_d), .tx1_tkeep(tx1_k), .tx1_tvalid(tx1_v),
        .tx1_tready(tx1_r), .tx1_tlast(tx1_l), .tx1_tuser(tx1_u),
        .last_action0(last0), .last_action1(last1),
        .pulse_rx0(p_rx0), .pulse_tx0(p_tx0), .pulse_fwd0(p_fwd0),
        .pulse_drop0(p_drop0), .pulse_mir0(p_mir0), .pulse_dpi0(p_dpi0),
        .pulse_rx1(p_rx1), .pulse_tx1(p_tx1), .pulse_fwd1(p_fwd1),
        .pulse_drop1(p_drop1), .pulse_mir1(p_mir1), .pulse_dpi1(p_dpi1),
        .pulse_csum0(p_csum0), .pulse_csum1(p_csum1),
        .pulse_ovf0(p_ovf0), .pulse_ovf1(p_ovf1),
        .pulse_flow0(p_flow0), .pulse_flow1(p_flow1),
        .pulse_phit0(p_phit0), .pulse_phit1(p_phit1),
        .aes0_ct(ct0), .aes1_ct(ct1), .aes0_done(done0), .aes1_done(done1),
        .aes0_fold(fold0), .aes1_fold(fold1)
    );

    int n_rx, n_fwd, n_mir, n_dpi, n_tx0, n_tx1;
    always @(posedge clk) begin
        if (!rst_n) begin
            n_rx <= 0; n_fwd <= 0; n_mir <= 0; n_dpi <= 0; n_tx0 <= 0; n_tx1 <= 0;
        end else begin
            if (p_rx0)  n_rx  <= n_rx + 1;
            if (p_fwd0) n_fwd <= n_fwd + 1;
            if (p_mir0) n_mir <= n_mir + 1;
            if (p_dpi0) n_dpi <= n_dpi + 1;
            if (tx0_v && tx0_r && tx0_l) n_tx0 <= n_tx0 + 1;
            if (tx1_v && tx1_r && tx1_l) n_tx1 <= n_tx1 + 1;
        end
    end

    task automatic pulse_inj;
        begin
            @(posedge clk);
            inj_start <= 1'b1;
            @(posedge clk);
            inj_start <= 1'b0;
        end
    endtask

    int errors, i, snap_tx0, snap_rx;
    initial begin
        errors = 0;
        mode = 2'd0; dp_en = 2'b11; inj_start = 0;
        pats = 512'd0;
        pats[31:0] = 32'h47455420;
        rx0_v = 0; rx0_d = 0; rx0_k = 0; rx0_l = 0; rx0_u = 0;
        rx1_v = 0; rx1_d = 0; rx1_k = 0; rx1_l = 0; rx1_u = 0;
        tx0_r = 1; tx1_r = 1;
        repeat (8) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);

        pulse_inj();
        repeat (400) @(posedge clk);
        if (n_rx != 0) begin
            $display("FAIL: BIST inspected %0d frames", n_rx);
            errors = errors + 1;
        end else $display("PASS: BIST does not feed the datapath");

        mode = 2'd1;
        repeat (4) @(posedge clk);
        pulse_inj();
        begin : wait_inl
            int t;
            t = 0;
            while (n_rx < 2 && t < 8000) begin
                @(posedge clk);
                t = t + 1;
            end
        end
        repeat (80) @(posedge clk);
        if (n_rx >= 2 && n_dpi >= 1 && n_mir >= 1 && n_fwd >= 1 && n_tx1 >= 1)
            $display("PASS: INLINE inj rx=%0d dpi=%0d mir=%0d fwd=%0d tx1=%0d", n_rx, n_dpi, n_mir, n_fwd, n_tx1);
        else begin
            $display("FAIL: INLINE rx=%0d dpi=%0d mir=%0d fwd=%0d tx1=%0d", n_rx, n_dpi, n_mir, n_fwd, n_tx1);
            errors = errors + 1;
        end

        snap_tx0 = n_tx0;
        snap_rx  = n_rx;
        mode = 2'd2;
        repeat (4) @(posedge clk);
        for (i = 0; i < 8; i = i + 1) begin
            rx0_v <= 1'b1;
            rx0_d <= {56'd0, i[7:0]};
            rx0_k <= 8'hFF;
            rx0_l <= (i == 7);
            rx0_u <= 1'b0;
            @(posedge clk);
            while (!rx0_r) @(posedge clk);
        end
        rx0_v <= 1'b0;
        rx0_l <= 1'b0;
        begin : wait_loop
            int t;
            t = 0;
            while (n_tx0 <= snap_tx0 && t < 4000) begin
                @(posedge clk);
                t = t + 1;
            end
        end
        repeat (20) @(posedge clk);
        if (n_tx0 > snap_tx0 && n_rx > snap_rx)
            $display("PASS: LOOP returned a frame tx0=%0d rx=%0d", n_tx0, n_rx);
        else begin
            $display("FAIL: LOOP tx0=%0d (was %0d) rx=%0d (was %0d)", n_tx0, snap_tx0, n_rx, snap_rx);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS: tb_netsec10g_inline");
        else             $display("FAIL: tb_netsec10g_inline errors=%0d", errors);
        $finish;
    end
endmodule
