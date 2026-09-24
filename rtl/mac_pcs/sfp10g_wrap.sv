// sfp10g_wrap.sv — dual SFP+ 10GBASE-R (X0Y4/X0Y5), fiber inter-port loopback
// GT Wizard 64B66B gearbox + eth_mac_phy_10g soft PCS/MAC
`timescale 1ns / 1ps

module sfp10g_pulse_cdc (
    input  logic src_clk,
    input  logic src_rst_n,
    input  logic src_pulse,
    input  logic dst_clk,
    input  logic dst_rst_n,
    output logic dst_pulse
);
    logic tog, meta, sync, sync_d;
    always_ff @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) tog <= 1'b0;
        else if (src_pulse) tog <= ~tog;
    end
    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            meta   <= 1'b0;
            sync   <= 1'b0;
            sync_d <= 1'b0;
        end else begin
            meta   <= tog;
            sync   <= meta;
            sync_d <= sync;
        end
    end
    assign dst_pulse = sync ^ sync_d;
endmodule

module sfp10g_wrap (
    input  logic        freerun_clk,
    input  logic        axi_clk,
    input  logic        rst_n,
    input  logic        tx_enable,
    input  logic        nearend_loopback,

    input  logic        mgtrefclk_p,
    input  logic        mgtrefclk_n,
    input  logic [1:0]  gthrxn_in,
    input  logic [1:0]  gthrxp_in,
    output logic [1:0]  gthtxn_out,
    output logic [1:0]  gthtxp_out,

    output logic        sfp_tx_dis,
    input  logic        sfp1_los,
    input  logic        sfp2_los,

    output logic        gt_tx_done,
    output logic        gt_rx_done,
    output logic        block_lock0,
    output logic        block_lock1,
    output logic        rx_status0,
    output logic        rx_status1,
    output logic        high_ber0,
    output logic        high_ber1,
    output logic        pulse_tx0_axi,
    output logic        pulse_rx0_axi,
    output logic        pulse_bad0_axi,
    output logic        pulse_tx1_axi,
    output logic        pulse_rx1_axi,
    output logic        pulse_bad1_axi
);

    assign sfp_tx_dis = 1'b0;

    logic refclk;
    IBUFDS_GTE4 #(
        .REFCLK_EN_TX_PATH (1'b0),
        .REFCLK_HROW_CK_SEL(2'b00),
        .REFCLK_ICNTL_RX   (2'b00)
    ) u_refclk (
        .I    (mgtrefclk_p),
        .IB   (mgtrefclk_n),
        .CEB  (1'b0),
        .O    (refclk),
        .ODIV2()
    );

    logic        tx_clk_gt, rx_clk_gt;
    logic        tx_clk, rx_clk0, rx_clk1;
    logic        tx_active, rx_active;
    logic        reset_tx_done, reset_rx_done;
    logic [127:0] tx_data, rx_data;
    logic [11:0] tx_hdr, rx_hdr;
    logic [3:0]  rx_dv, rx_hv;
    logic [1:0]  rx_slip;
    logic [1:0]  rx_reset_req;
    logic        rx_dp_reset;

    // 64B66B gearbox: 32 data cycles + 1 pause (64*33 = 66*32)
    logic [6:0] txseq;
    always_ff @(posedge tx_clk_gt) begin
        if (!reset_tx_done)
            txseq <= 7'd0;
        else if (txseq == 7'd32)
            txseq <= 7'd0;
        else
            txseq <= txseq + 7'd1;
    end
    logic tx_pause;
    logic tx_ce_q;
    always_ff @(posedge tx_clk_gt)
        tx_ce_q <= (txseq != 7'd32);
    assign tx_pause = (txseq == 7'd32);

    // Register RX gearbox outputs so BUFGCE (CE sampled on falling edge)
    // clocks the MAC on the cycle that still holds the valid word.
    logic [127:0] rx_data_q;
    logic [11:0]  rx_hdr_q;
    logic         rx_v0_q, rx_v1_q;
    always_ff @(posedge rx_clk_gt) begin
        rx_data_q <= rx_data;
        rx_hdr_q  <= rx_hdr;
        rx_v0_q   <= rx_dv[0] | rx_hv[0];
        rx_v1_q   <= rx_dv[2] | rx_hv[2];
    end

    BUFGCE u_tx_mac_clk  (.I(tx_clk_gt), .CE(tx_ce_q), .O(tx_clk));
    BUFGCE u_rx_mac_clk0 (.I(rx_clk_gt), .CE(rx_v0_q), .O(rx_clk0));
    BUFGCE u_rx_mac_clk1 (.I(rx_clk_gt), .CE(rx_v1_q), .O(rx_clk1));

    logic rst_tx, rst_rx0, rst_rx1;
    logic rst_tx_n, rst_rx0_n, rst_rx1_n;
    u_reset_sync u_rst_tx  (.clk(tx_clk),  .async_rst_n(rst_n & reset_tx_done), .sync_rst_n(rst_tx_n));
    u_reset_sync u_rst_rx0 (.clk(rx_clk0), .async_rst_n(rst_n & reset_rx_done), .sync_rst_n(rst_rx0_n));
    u_reset_sync u_rst_rx1 (.clk(rx_clk1), .async_rst_n(rst_n & reset_rx_done), .sync_rst_n(rst_rx1_n));
    assign rst_tx  = ~rst_tx_n;
    assign rst_rx0 = ~rst_rx0_n;
    assign rst_rx1 = ~rst_rx1_n;

    logic [1:0]  tx_en_meta, tx_en_sync;
    always_ff @(posedge tx_clk or negedge rst_tx_n) begin
        if (!rst_tx_n) begin
            tx_en_meta <= 2'b00;
            tx_en_sync <= 2'b00;
        end else begin
            tx_en_meta <= {tx_enable, tx_enable};
            tx_en_sync <= tx_en_meta;
        end
    end

    logic [63:0] axis_tdata  [1:0];
    logic [7:0]  axis_tkeep  [1:0];
    logic        axis_tvalid [1:0];
    logic        axis_tready [1:0];
    logic        axis_tlast  [1:0];
    logic        axis_tuser  [1:0];
    logic        pulse_tx    [1:0];

    logic [63:0] rx_tdata  [1:0];
    logic        rx_tvalid [1:0];
    logic        rx_tlast  [1:0];
    logic        rx_tuser  [1:0];
    logic        rx_bad_fcs [1:0];
    logic        rx_bad_frm [1:0];
    logic        block[1:0];
    logic        rxstat[1:0];
    logic        hber[1:0];

    pkt_gen_10g #(.PORT_ID(8'h01)) u_gen0 (
        .clk(tx_clk), .rst(rst_tx), .enable(tx_en_sync[0] & tx_active),
        .m_tdata(axis_tdata[0]), .m_tkeep(axis_tkeep[0]),
        .m_tvalid(axis_tvalid[0]), .m_tready(axis_tready[0]),
        .m_tlast(axis_tlast[0]), .m_tuser(axis_tuser[0]),
        .pulse_tx(pulse_tx[0])
    );
    pkt_gen_10g #(.PORT_ID(8'h02)) u_gen1 (
        .clk(tx_clk), .rst(rst_tx), .enable(tx_en_sync[1] & tx_active),
        .m_tdata(axis_tdata[1]), .m_tkeep(axis_tkeep[1]),
        .m_tvalid(axis_tvalid[1]), .m_tready(axis_tready[1]),
        .m_tlast(axis_tlast[1]), .m_tuser(axis_tuser[1]),
        .pulse_tx(pulse_tx[1])
    );

    genvar gi;
    generate
        for (gi = 0; gi < 2; gi++) begin : g_mac
            logic [63:0] s_tx, s_rx;
            logic [1:0]  s_txh, s_rxh;
            logic        slip, rreq;
            logic [1:0]  start_pkt;
            logic        uf, bad_blk;
            logic [6:0]  err_cnt;
            logic [1:0]  rx_sp;
            logic [95:0] unused_ts;
            logic [15:0] unused_tag;
            logic        unused_tsv;

            eth_mac_phy_10g #(
                .DATA_WIDTH(64),
                .PTP_TS_ENABLE(0),
                .BIT_REVERSE(0),
                .SCRAMBLER_DISABLE(0),
                .PRBS31_ENABLE(0),
                .TX_SERDES_PIPELINE(2),
                .RX_SERDES_PIPELINE(2)
            ) u_mac (
                .rx_clk(gi == 0 ? rx_clk0 : rx_clk1),
                .rx_rst(gi == 0 ? rst_rx0 : rst_rx1),
                .tx_clk(tx_clk),
                .tx_rst(rst_tx),
                .tx_axis_tdata(axis_tdata[gi]),
                .tx_axis_tkeep(axis_tkeep[gi]),
                .tx_axis_tvalid(axis_tvalid[gi]),
                .tx_axis_tready(axis_tready[gi]),
                .tx_axis_tlast(axis_tlast[gi]),
                .tx_axis_tuser(axis_tuser[gi]),
                .rx_axis_tdata(rx_tdata[gi]),
                .rx_axis_tkeep(),
                .rx_axis_tvalid(rx_tvalid[gi]),
                .rx_axis_tlast(rx_tlast[gi]),
                .rx_axis_tuser(rx_tuser[gi]),
                .serdes_tx_data(s_tx),
                .serdes_tx_hdr(s_txh),
                .serdes_rx_data(s_rx),
                .serdes_rx_hdr(s_rxh),
                .serdes_rx_bitslip(slip),
                .serdes_rx_reset_req(rreq),
                .tx_ptp_ts(96'd0),
                .rx_ptp_ts(96'd0),
                .tx_axis_ptp_ts(unused_ts),
                .tx_axis_ptp_ts_tag(unused_tag),
                .tx_axis_ptp_ts_valid(unused_tsv),
                .tx_start_packet(start_pkt),
                .tx_error_underflow(uf),
                .rx_start_packet(rx_sp),
                .rx_error_count(err_cnt),
                .rx_error_bad_frame(rx_bad_frm[gi]),
                .rx_error_bad_fcs(rx_bad_fcs[gi]),
                .rx_bad_block(bad_blk),
                .rx_block_lock(block[gi]),
                .rx_high_ber(hber[gi]),
                .rx_status(rxstat[gi]),
                .cfg_ifg(8'd12),
                .cfg_tx_enable(1'b1),
                .cfg_rx_enable(1'b1),
                .cfg_tx_prbs31_enable(1'b0),
                .cfg_rx_prbs31_enable(1'b0)
            );

            assign tx_data[gi*64 +: 64] = s_tx;
            assign tx_hdr[gi*6 +: 6]    = {4'd0, s_txh};
            assign s_rx                 = rx_data_q[gi*64 +: 64];
            assign s_rxh                = rx_hdr_q[gi*6 +: 2];
            assign rx_slip[gi]          = slip;
            assign rx_reset_req[gi]     = rreq;
        end
    endgenerate

    assign block_lock0 = block[0];
    assign block_lock1 = block[1];
    assign rx_status0  = rxstat[0];
    assign rx_status1  = rxstat[1];
    assign high_ber0   = hber[0];
    assign high_ber1   = hber[1];
    assign gt_tx_done  = reset_tx_done;
    assign gt_rx_done  = reset_rx_done;

    logic [7:0] slip_hold;
    always_ff @(posedge freerun_clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_dp_reset <= 1'b0;
            slip_hold   <= 8'd0;
        end else if (|rx_reset_req) begin
            rx_dp_reset <= 1'b1;
            slip_hold   <= 8'd16;
        end else if (slip_hold != 8'd0) begin
            slip_hold   <= slip_hold - 1'b1;
            rx_dp_reset <= 1'b1;
        end else begin
            rx_dp_reset <= 1'b0;
        end
    end

    logic pulse_rx [1:0];
    logic pulse_bad [1:0];
    always_ff @(posedge rx_clk0 or negedge rst_rx0_n) begin
        if (!rst_rx0_n) begin
            pulse_rx[0]  <= 1'b0;
            pulse_bad[0] <= 1'b0;
        end else begin
            pulse_rx[0]  <= rx_tvalid[0] & rx_tlast[0];
            pulse_bad[0] <= rx_bad_fcs[0] | rx_bad_frm[0];
        end
    end
    always_ff @(posedge rx_clk1 or negedge rst_rx1_n) begin
        if (!rst_rx1_n) begin
            pulse_rx[1]  <= 1'b0;
            pulse_bad[1] <= 1'b0;
        end else begin
            pulse_rx[1]  <= rx_tvalid[1] & rx_tlast[1];
            pulse_bad[1] <= rx_bad_fcs[1] | rx_bad_frm[1];
        end
    end

    sfp10g_pulse_cdc u_cdc_tx0 (
        .src_clk(tx_clk), .src_rst_n(rst_tx_n), .src_pulse(pulse_tx[0]),
        .dst_clk(axi_clk), .dst_rst_n(rst_n), .dst_pulse(pulse_tx0_axi));
    sfp10g_pulse_cdc u_cdc_tx1 (
        .src_clk(tx_clk), .src_rst_n(rst_tx_n), .src_pulse(pulse_tx[1]),
        .dst_clk(axi_clk), .dst_rst_n(rst_n), .dst_pulse(pulse_tx1_axi));
    sfp10g_pulse_cdc u_cdc_rx0 (
        .src_clk(rx_clk0), .src_rst_n(rst_rx0_n), .src_pulse(pulse_rx[0]),
        .dst_clk(axi_clk), .dst_rst_n(rst_n), .dst_pulse(pulse_rx0_axi));
    sfp10g_pulse_cdc u_cdc_rx1 (
        .src_clk(rx_clk1), .src_rst_n(rst_rx1_n), .src_pulse(pulse_rx[1]),
        .dst_clk(axi_clk), .dst_rst_n(rst_n), .dst_pulse(pulse_rx1_axi));
    sfp10g_pulse_cdc u_cdc_bd0 (
        .src_clk(rx_clk0), .src_rst_n(rst_rx0_n), .src_pulse(pulse_bad[0]),
        .dst_clk(axi_clk), .dst_rst_n(rst_n), .dst_pulse(pulse_bad0_axi));
    sfp10g_pulse_cdc u_cdc_bd1 (
        .src_clk(rx_clk1), .src_rst_n(rst_rx1_n), .src_pulse(pulse_bad[1]),
        .dst_clk(axi_clk), .dst_rst_n(rst_n), .dst_pulse(pulse_bad1_axi));

    logic _los_keep;
    assign _los_keep = sfp1_los ^ sfp2_los;

    gt_sfp_10g u_gt (
        .gtwiz_userclk_tx_reset_in         (~rst_n),
        .gtwiz_userclk_tx_srcclk_out       (),
        .gtwiz_userclk_tx_usrclk_out       (),
        .gtwiz_userclk_tx_usrclk2_out      (tx_clk_gt),
        .gtwiz_userclk_tx_active_out       (tx_active),
        .gtwiz_userclk_rx_reset_in         (~rst_n),
        .gtwiz_userclk_rx_srcclk_out       (),
        .gtwiz_userclk_rx_usrclk_out       (),
        .gtwiz_userclk_rx_usrclk2_out      (rx_clk_gt),
        .gtwiz_userclk_rx_active_out       (rx_active),
        .gtwiz_reset_clk_freerun_in        (freerun_clk),
        .gtwiz_reset_all_in                (~rst_n),
        .gtwiz_reset_tx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_tx_datapath_in        (1'b0),
        .gtwiz_reset_rx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_rx_datapath_in        (rx_dp_reset),
        .gtwiz_reset_rx_cdr_stable_out     (),
        .gtwiz_reset_tx_done_out           (reset_tx_done),
        .gtwiz_reset_rx_done_out           (reset_rx_done),
        .gtwiz_userdata_tx_in              (tx_data),
        .gtwiz_userdata_rx_out             (rx_data),
        .gtrefclk00_in                     (refclk),
        .qpll0outclk_out                   (),
        .qpll0outrefclk_out                (),
        .gthrxn_in                         (gthrxn_in),
        .gthrxp_in                         (gthrxp_in),
        .gthtxn_out                        (gthtxn_out),
        .gthtxp_out                        (gthtxp_out),
        .loopback_in                       (nearend_loopback ? 6'b010_010 : 6'b000_000),
        .rxgearboxslip_in                  (rx_slip),
        .txheader_in                       (tx_hdr),
        .rxheader_out                      (rx_hdr),
        .txsequence_in                     ({txseq, txseq}),
        .rxdatavalid_out                   (rx_dv),
        .rxheadervalid_out                 (rx_hv),
        .rxstartofseq_out                  (),
        .gtpowergood_out                   (),
        .rxpmaresetdone_out                (),
        .txpmaresetdone_out                ()
    );

endmodule
