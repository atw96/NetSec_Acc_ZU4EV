// TB-3: INLINE GET -> DPI/MIRROR on DP_A, LOOP bypass
`timescale 1ns / 1ps

module tb_netsec10g_inline;
    logic clk = 0, rst_n = 0;
    always #4 clk = ~clk;

    logic [7:0] gen_d, rx0_d, tx1_d, tx0_d;
    logic       gen_v, gen_r, gen_l;
    logic       rx0_v, rx0_r, rx0_l;
    logic       tx1_v, tx1_r, tx1_l, tx0_v, tx0_r, tx0_l;
    logic [1:0] act0, act1;
    logic       p_rx0, p_dpi0, p_mir0, p_fwd0;

    pkt_gen_bram u_gen (
        .clk(clk), .rst_n(rst_n), .start(start),
        .m_tdata(gen_d), .m_tvalid(gen_v), .m_tready(gen_r),
        .m_tlast(gen_l), .busy()
    );
    logic start;

    assign rx0_d = gen_d;
    assign rx0_v = gen_v;
    assign rx0_l = gen_l;
    assign gen_r = rx0_r;
    assign tx1_r = 1'b1;
    assign tx0_r = 1'b1;

    netsec10g_switch #(.FRAME_DEPTH(2048)) u_sw (
        .clk(clk), .rst_n(rst_n),
        .mode(2'd1), .dp_en(2'b11),
        .aes_dp0_en(1'b0), .aes_dp1_en(1'b0), .aes_key(128'd0),
        .dpi_pat0(32'h47455420), .dpi_pat1(32'h636d642e),
        .dpi_pat2(32'h53454c45), .dpi_pat3(32'h90909090),
        .rx0_tdata(rx0_d), .rx0_tvalid(rx0_v), .rx0_tready(rx0_r), .rx0_tlast(rx0_l),
        .rx1_tdata(8'd0), .rx1_tvalid(1'b0), .rx1_tready(), .rx1_tlast(1'b0),
        .tx0_tdata(tx0_d), .tx0_tvalid(tx0_v), .tx0_tready(tx0_r), .tx0_tlast(tx0_l),
        .tx1_tdata(tx1_d), .tx1_tvalid(tx1_v), .tx1_tready(tx1_r), .tx1_tlast(tx1_l),
        .last_action0(act0), .last_action1(act1),
        .pulse_rx0(p_rx0), .pulse_tx0(), .pulse_fwd0(p_fwd0),
        .pulse_drop0(), .pulse_mir0(p_mir0), .pulse_dpi0(p_dpi0),
        .pulse_rx1(), .pulse_tx1(), .pulse_fwd1(),
        .pulse_drop1(), .pulse_mir1(), .pulse_dpi1(),
        .pulse_csum0(), .pulse_csum1(),
        .aes_dp0_ct(), .aes_dp0_done(), .aes_dp1_ct(), .aes_dp1_done()
    );

    integer cnt_rx, cnt_dpi, cnt_mir;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_rx <= 0; cnt_dpi <= 0; cnt_mir <= 0;
        end else begin
            if (p_rx0) cnt_rx <= cnt_rx + 1;
            if (p_dpi0) cnt_dpi <= cnt_dpi + 1;
            if (p_mir0) cnt_mir <= cnt_mir + 1;
        end
    end

    initial begin
        start = 0;
        repeat (8) @(posedge clk);
        rst_n = 1;
        repeat (30000) @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        repeat (2000) @(posedge clk);
        $display("INLINE RX=%0d DPI=%0d MIR=%0d", cnt_rx, cnt_dpi, cnt_mir);
        if (cnt_rx >= 1 && cnt_dpi >= 1 && cnt_mir >= 1)
            $display("PASS: tb_netsec10g_inline");
        else
            $display("FAIL: tb_netsec10g_inline");
        $finish;
    end
endmodule
