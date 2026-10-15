// tb_dp64.sv — back-to-back forward, DPI mirror, AES ciphertext, checksum pulse
`timescale 1ns / 1ps

module tb_dp64;
    logic clk = 0, rst_n = 0;
    always #3.2 clk = ~clk;

    logic [63:0] s_tdata, m_tdata;
    logic [7:0]  s_tkeep, m_tkeep;
    logic        s_tvalid, s_tready, s_tlast, s_tuser;
    logic        m_tvalid, m_tready, m_tlast, m_tuser;
    logic [511:0] pats;
    logic        aes_en, aes_done, fold, csum, dpi, mir, fwd;
    logic [127:0] aes_ct, aes_key;
    logic [15:0] phit;
    logic [1:0]  act;

    netsec_dp64 #(
        .HASH_BITS(8),
        .ROM_PATTERNS(4),
        .AES_PIPE(1),
        .AES_LANES(2),
        .FIFO_BYTES(8192),
        .DLY(20)
    ) dut (
        .clk(clk), .rst_n(rst_n), .enable(1'b1),
        .s_tdata(s_tdata), .s_tkeep(s_tkeep), .s_tvalid(s_tvalid),
        .s_tready(s_tready), .s_tlast(s_tlast), .s_tuser(s_tuser),
        .m_tdata(m_tdata), .m_tkeep(m_tkeep), .m_tvalid(m_tvalid),
        .m_tready(m_tready), .m_tlast(m_tlast), .m_tuser(m_tuser),
        .pats(pats), .aes_en(aes_en), .aes_key(aes_key),
        .aes_ct(aes_ct), .aes_done(aes_done), .aes_fold_pulse(fold),
        .last_action(act),
        .stat_rx(), .stat_tx(), .stat_fwd(fwd), .stat_drop(),
        .stat_mir(mir), .stat_dpi(dpi), .stat_csum(csum), .stat_ovf(),
        .stat_flow(), .stat_phit(phit)
    );

    integer n_tx, n_fwd, n_mir, n_dpi, n_csum, n_aes;
    always @(posedge clk) begin
        if (!rst_n) begin
            n_tx <= 0; n_fwd <= 0; n_mir <= 0; n_dpi <= 0; n_csum <= 0; n_aes <= 0;
        end else begin
            if (m_tvalid && m_tready && m_tlast) n_tx <= n_tx + 1;
            if (fwd)  n_fwd  <= n_fwd + 1;
            if (mir)  n_mir  <= n_mir + 1;
            if (dpi)  n_dpi  <= n_dpi + 1;
            if (csum) n_csum <= n_csum + 1;
            if (aes_done) n_aes <= n_aes + 1;
        end
    end

    task automatic beat(input [63:0] d, input [7:0] k, input last);
        @(negedge clk);
        s_tvalid <= 1'b1;
        s_tdata  <= d;
        s_tkeep  <= k;
        s_tlast  <= last;
        s_tuser  <= 1'b0;
        @(posedge clk);
        while (!s_tready) @(posedge clk);
    endtask

    task automatic idle;
        @(negedge clk);
        s_tvalid <= 1'b0;
        s_tlast  <= 1'b0;
    endtask

    task automatic frame_plain(input [7:0] id);
        beat(64'h0002_ffff_ffff_ffff, 8'hff, 0);
        beat(64'h0045_0008_0100_0000, 8'hff, 0);
        beat(64'h0640_0040_0100_2800, 8'hff, 0);
        beat({8'ha8, 8'hc0, 8'h02, id, 8'ha8, 8'hc0, 8'h00, 8'h00}, 8'hff, 0);
        beat(64'h0000_5000_d204_6401, 8'hff, 0);
        beat(64'h0100_0000_0000_0000, 8'hff, 0);
        beat(64'h0000_0000_0000_0000, 8'hff, 0);
        beat(64'h0000_0000_0000_0000, 8'hff, 1);
    endtask

    task automatic frame_get;
        beat(64'h0002_ffff_ffff_ffff, 8'hff, 0);
        beat(64'h0045_0008_0200_0000, 8'hff, 0);
        beat(64'h0640_0040_0200_2c00, 8'hff, 0);
        beat(64'ha8c0_0500_000a_0000, 8'hff, 0);
        beat(64'h0000_5000_d204_6401, 8'hff, 0);
        beat(64'h0250_0000_0000_0100, 8'hff, 0);
        beat(64'h4547_0000_0000_0020, 8'hff, 0);
        beat(64'h0000_0000_002f_2054, 8'hff, 1);
    endtask

    task automatic frame_aes;
        beat(64'h0002_ffff_ffff_ffff, 8'hff, 0);
        beat(64'h0045_0008_0100_0000, 8'hff, 0);
        beat(64'h0640_0040_0100_2800, 8'hff, 0);
        beat(64'ha8c0_0201_a8c0_0000, 8'hff, 0);
        beat(64'h0000_5000_d204_6401, 8'hff, 0);
        beat(64'h5544_3322_1100_0100, 8'hff, 0);
        beat(64'hddcc_bbaa_9988_7766, 8'hff, 0);
        beat(64'h0000_0000_0000_ffee, 8'h0f, 1);
    endtask

    integer i, tx0, fail;
    initial begin
        fail = 0;
        m_tready = 1'b1;
        s_tvalid = 1'b0;
        s_tlast = 1'b0;
        s_tuser = 1'b0;
        s_tkeep = 8'hff;
        s_tdata = '0;
        aes_en = 1'b0;
        aes_key = 128'h000102030405060708090a0b0c0d0e0f;
        pats = '0;
        pats[31:0] = 32'h47455420;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);

        for (i = 0; i < 1000; i = i + 1)
            frame_plain(i[7:0]);
        idle();
        repeat (80) @(posedge clk);
        if (n_tx != 1000 || n_fwd != 1000 || n_mir != 0) begin
            $display("FAIL: plain tx=%0d fwd=%0d mir=%0d", n_tx, n_fwd, n_mir);
            fail = 1;
        end else
            $display("PASS: 1000 back-to-back frames forwarded");

        tx0 = n_tx;
        frame_get();
        idle();
        repeat (80) @(posedge clk);
        if (n_dpi < 1 || n_mir < 1 || n_tx != tx0) begin
            $display("FAIL: GET dpi=%0d mir=%0d tx %0d->%0d", n_dpi, n_mir, tx0, n_tx);
            fail = 1;
        end else
            $display("PASS: GET mirrored and dropped dpi=%0d mir=%0d", n_dpi, n_mir);

        aes_en = 1'b1;
        frame_aes();
        idle();
        aes_en = 1'b0;
        repeat (40) @(posedge clk);
        if (n_aes < 1 || aes_ct !== 128'h69c4e0d86a7b0430d8cdb78070b4c55a) begin
            $display("FAIL: AES n=%0d ct=%h", n_aes, aes_ct);
            fail = 1;
        end else
            $display("PASS: AES FIPS ciphertext");

        if (n_csum < 1) begin
            $display("FAIL: expected checksum errors, csum=%0d", n_csum);
            fail = 1;
        end else
            $display("PASS: checksum errors counted (%0d)", n_csum);

        if (fail) $display("FAIL: tb_dp64");
        else      $display("PASS: tb_dp64");
        $finish;
    end

    initial begin
        repeat (400000) @(posedge clk);
        $display("FAIL: tb_dp64 timeout tx=%0d fwd=%0d", n_tx, n_fwd);
        $finish;
    end
endmodule
