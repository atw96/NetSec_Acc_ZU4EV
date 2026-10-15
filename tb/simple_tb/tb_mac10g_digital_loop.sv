// TB-4: eth_mac_phy_10g TX AXIS -> RX AXIS via serdes loop (same clock).
// Strict: AXIS handshake, 8-beat frames, FCS-good, payload match after lock.
`timescale 1ns / 1ps

module tb_mac10g_digital_loop;
    logic clk = 0, rst = 1;
    always #3.2 clk = ~clk;

    logic [63:0] tx_d, rx_d, s_tx, s_rx;
    logic [7:0]  tx_k, rx_k;
    logic [1:0]  s_txh, s_rxh;
    logic        tx_v, tx_r, tx_l, tx_u;
    logic        rx_v, rx_l, rx_u;
    logic        slip, rreq, uf, bad_blk, lock, hber, rxst;
    logic [1:0]  tsp, rsp;
    logic [6:0]  errc;
    logic        bad_f, bad_c;
    logic [95:0] ts;
    logic [15:0] tag;
    logic        tsv;

    integer sent, got, bad, errors, proto, beats;
    integer locked_cycles;
    logic   tx_v_d, tx_r_d, tx_l_d;
    logic [63:0] tx_d_d;
    logic [63:0] q_d [0:255];
    integer q_w, q_r;
    integer cmp_bad;

    pkt_gen_10g #(.PORT_ID(8'h11)) u_gen (
        .clk(clk), .rst(rst), .enable(~rst), .gap_cycles(16'd32),
        .m_tdata(tx_d), .m_tkeep(tx_k), .m_tvalid(tx_v), .m_tready(tx_r),
        .m_tlast(tx_l), .m_tuser(tx_u), .pulse_tx()
    );

    always_ff @(posedge clk) begin
        s_rx  <= s_tx;
        s_rxh <= s_txh;
    end

    eth_mac_phy_10g #(
        .DATA_WIDTH(64),
        .PTP_TS_ENABLE(0),
        .BIT_REVERSE(0),
        .SCRAMBLER_DISABLE(0),
        .PRBS31_ENABLE(0)
    ) u_mac (
        .rx_clk(clk), .rx_rst(rst), .tx_clk(clk), .tx_rst(rst),
        .tx_axis_tdata(tx_d), .tx_axis_tkeep(tx_k), .tx_axis_tvalid(tx_v),
        .tx_axis_tready(tx_r), .tx_axis_tlast(tx_l), .tx_axis_tuser(tx_u),
        .rx_axis_tdata(rx_d), .rx_axis_tkeep(rx_k), .rx_axis_tvalid(rx_v),
        .rx_axis_tlast(rx_l), .rx_axis_tuser(rx_u),
        .serdes_tx_data(s_tx), .serdes_tx_hdr(s_txh),
        .serdes_rx_data(s_rx), .serdes_rx_hdr(s_rxh),
        .serdes_rx_bitslip(slip), .serdes_rx_reset_req(rreq),
        .tx_ptp_ts(96'd0), .rx_ptp_ts(96'd0),
        .tx_axis_ptp_ts(ts), .tx_axis_ptp_ts_tag(tag), .tx_axis_ptp_ts_valid(tsv),
        .tx_start_packet(tsp), .tx_error_underflow(uf),
        .rx_start_packet(rsp), .rx_error_count(errc),
        .rx_error_bad_frame(bad_f), .rx_error_bad_fcs(bad_c),
        .rx_bad_block(bad_blk), .rx_block_lock(lock),
        .rx_high_ber(hber), .rx_status(rxst),
        .cfg_ifg(8'd12), .cfg_tx_enable(1'b1), .cfg_rx_enable(1'b1),
        .cfg_tx_prbs31_enable(1'b0), .cfg_rx_prbs31_enable(1'b0)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            sent <= 0; got <= 0; bad <= 0; proto <= 0; beats <= 0;
            locked_cycles <= 0; cmp_bad <= 0;
            tx_v_d <= 0; tx_r_d <= 0; tx_l_d <= 0; tx_d_d <= '0;
            q_w <= 0; q_r <= 0;
        end else begin
            tx_v_d <= tx_v;
            tx_r_d <= tx_r;
            tx_l_d <= tx_l;
            tx_d_d <= tx_d;
            if (lock) locked_cycles <= locked_cycles + 1;
            else      locked_cycles <= 0;

            // tvalid must stay high, and data/tlast stable, until tready.
            if (tx_v_d && !tx_r_d) begin
                if (!tx_v || tx_d !== tx_d_d || tx_l !== tx_l_d)
                    proto <= proto + 1;
            end
            if (tx_v && tx_r) begin
                q_d[q_w[7:0]] <= tx_d;
                q_w <= q_w + 1;
                if (tx_l) begin
                    if (beats != 7) proto <= proto + 1;
                    beats <= 0;
                    if (locked_cycles > 64) sent <= sent + 1;
                end else begin
                    beats <= beats + 1;
                end
            end
            // Pop every RX beat so the queue stays aligned through lock.
            // Score FCS and payload only after lock has been stable.
            if (rx_v) begin
                if (q_r >= q_w || rx_d !== q_d[q_r[7:0]]) begin
                    if (locked_cycles > 64) cmp_bad <= cmp_bad + 1;
                end else if (locked_cycles > 64 && rx_u) begin
                    cmp_bad <= cmp_bad + 1;
                end
                if (q_r < q_w) q_r <= q_r + 1;
            end
            if (locked_cycles > 64) begin
                if (bad_f || bad_c) bad <= bad + 1;
                if (rx_v && rx_l)   got <= got + 1;
            end
        end
    end

    initial begin
        errors = 0;
        repeat (8) @(posedge clk);
        rst = 0;
        repeat (40000) @(posedge clk);
        $display("MAC10G digital loop sent=%0d got=%0d bad=%0d proto=%0d cmp=%0d lock=%0d",
                 sent, got, bad, proto, cmp_bad, lock);
        if (lock && bad == 0 && proto == 0 && cmp_bad == 0 && sent > 4 && got + 1 >= sent)
            $display("PASS: tb_mac10g_digital_loop");
        else begin
            $display("FAIL: tb_mac10g_digital_loop");
            errors = 1;
        end
        $finish;
    end
endmodule
