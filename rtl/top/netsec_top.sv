// netsec_top.sv — PL-self-hosted top: axi_clk from BUFGCE_DIV, local POR
`timescale 1ns / 1ps

module netsec_top #(
    parameter bit NETSEC_ENABLE_SFP   = 1'b0,
    parameter bit NETSEC_ENABLE_ILA   = 1'b1,
    parameter     RGMII_TX_USE_CLK90  = "TRUE"
) (
    input  logic        sys_clk_clk_p,
    input  logic        sys_clk_clk_n,

    input  logic        rgmii_rxc,
    input  logic [3:0]  rgmii_rd,
    input  logic        rgmii_rx_ctl,
    output logic        rgmii_txc,
    output logic [3:0]  rgmii_td,
    output logic        rgmii_tx_ctl,
    output logic        mdio_mdc,
    inout  wire         mdio_mdio,
    output logic        phy_reset_n,

    output logic        pl_led,
    input  logic        pl_key_n,
    output logic        pl_uart_tx,
    input  logic        pl_uart_rx,

    input  logic        mgtrefclk_p,
    input  logic        mgtrefclk_n,
    output logic        sfp_tx_dis,
    input  logic        sfp1_los,
    input  logic        sfp2_los,

`ifdef NETSEC_SFP_PORTS
    input  logic        gthrxn_in,
    input  logic        gthrxp_in,
    output logic        gthtxn_out,
    output logic        gthtxp_out,
`endif

    // AXI clock/reset generated here, fed back into BD / JTAG-AXI
    output logic        axi_clk,
    output logic        axi_aresetn,

    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready
);

    // ------------------------------------------------------------
    // 200 MHz differential oscillator
    // ------------------------------------------------------------
    logic sys_clk_200m;
    IBUFDS #(
        .DIFF_TERM("FALSE"),
        .IBUF_LOW_PWR("TRUE"),
        .IOSTANDARD("DIFF_SSTL12")
    ) u_ibuf_sys (
        .I (sys_clk_clk_p),
        .IB(sys_clk_clk_n),
        .O (sys_clk_200m)
    );

    // 100 MHz AXI / debug / MDIO clock — independent of PS and of MMCM
    BUFGCE_DIV #(
        .BUFGCE_DIVIDE(2),
        .IS_CE_INVERTED(1'b0),
        .IS_CLR_INVERTED(1'b0),
        .IS_I_INVERTED(1'b0)
    ) u_axi_div (
        .I  (sys_clk_200m),
        .CE (1'b1),
        .CLR(1'b0),
        .O  (axi_clk)
    );

    logic [7:0] por_cnt;
    logic       axi_por_n;
    always_ff @(posedge axi_clk) begin
        if (!pl_key_n)
            por_cnt <= 8'd0;
        else if (por_cnt != 8'hFF)
            por_cnt <= por_cnt + 1'b1;
    end
    assign axi_por_n  = (por_cnt == 8'hFF);
    assign axi_aresetn = axi_por_n;

    logic sys_rst_n;
    assign sys_rst_n = axi_por_n;

    // ------------------------------------------------------------
    // Register file (axi_clk / local POR)
    // ------------------------------------------------------------
    logic         ctrl_enable, soft_reset, pkt_gen_start;
    logic [2:0]   loopback_mode;
    logic [127:0] aes_key, aes_pt, aes_ct;
    logic         aes_start, aes_done;
    logic         csum_start, csum_dv, csum_last, csum_valid;
    logic [15:0]  csum_data, csum_res;
    logic         mx_start, mx_done;
    logic [31:0]  mx_base, mx_exp, mx_mod, mx_res;
    logic         aes_dp_en, aes_dp_en_l, aes_dp_done, aes_dp_done_a;
    logic [127:0] aes_dp_ct, aes_dp_ct_a, aes_key_l;
    logic [31:0]  dpi_pat0, dpi_pat1, dpi_pat2, dpi_pat3;
    logic         mmcm_locked;
    logic [1:0]   mac_speed, last_action;
    logic         pulse_rx, pulse_tx, pulse_fwd, pulse_drop, pulse_mir, pulse_dpi;
    logic         pulse_rx_a, pulse_tx_a, pulse_fwd_a, pulse_drop_a, pulse_mir_a, pulse_dpi_a;
    logic         pulse_mac_good_a, pulse_mac_fcs_a, pulse_mac_bad_a, pulse_mac_txg_a;
    logic         pulse_rgmii_act_a;
    logic         mdio_go, mdio_we, mdio_busy, mdio_done;
    logic [4:0]   mdio_phy_addr, mdio_reg_addr;
    logic [15:0]  mdio_wdata, mdio_rdata;
    logic [8:0]   rgmii_dly_tap;
    logic         rgmii_dly_load;
    logic         phy_link;
    logic [15:0]  sfp_status_vector;
    logic         sfp_link_status;

    netsec_regs u_regs (
        .aclk(axi_clk), .aresetn(axi_por_n),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .ctrl_enable(ctrl_enable), .soft_reset(soft_reset), .loopback_mode(loopback_mode),
        .pkt_gen_start(pkt_gen_start), .aes_key(aes_key),
        .aes_start(aes_start), .aes_plaintext(aes_pt),
        .aes_done(aes_done), .aes_ciphertext(aes_ct),
        .csum_start(csum_start), .csum_data_valid(csum_dv),
        .csum_data(csum_data), .csum_last(csum_last),
        .csum_valid(csum_valid), .csum_result(csum_res),
        .modexp_start(mx_start), .modexp_base(mx_base),
        .modexp_exp(mx_exp), .modexp_mod(mx_mod),
        .modexp_done(mx_done), .modexp_result(mx_res),
        .ctrl_aes_dp_en(aes_dp_en),
        .aes_dp_done(aes_dp_done_a), .aes_dp_ciphertext(aes_dp_ct_a),
        .dpi_pat0(dpi_pat0), .dpi_pat1(dpi_pat1), .dpi_pat2(dpi_pat2), .dpi_pat3(dpi_pat3),
        .mdio_go(mdio_go), .mdio_we(mdio_we),
        .mdio_phy_addr(mdio_phy_addr), .mdio_reg_addr(mdio_reg_addr),
        .mdio_wdata(mdio_wdata), .mdio_rdata(mdio_rdata),
        .mdio_busy(mdio_busy), .mdio_done(mdio_done),
        .rgmii_dly_tap(rgmii_dly_tap), .rgmii_dly_load(rgmii_dly_load),
        .datapath_ready(mmcm_locked), .mmcm_locked(mmcm_locked), .phy_link(phy_link),
        .sfp1_los(sfp1_los), .sfp2_los(sfp2_los), .sfp_status(sfp_status_vector),
        .mac_speed(mac_speed), .last_action(last_action),
        .pulse_rx(pulse_rx_a), .pulse_tx(pulse_tx_a), .pulse_forward(pulse_fwd_a),
        .pulse_drop(pulse_drop_a), .pulse_mirror(pulse_mir_a), .pulse_dpi_hit(pulse_dpi_a),
        .pulse_mac_rx_good(pulse_mac_good_a), .pulse_mac_rx_bad_fcs(pulse_mac_fcs_a),
        .pulse_mac_rx_bad_frame(pulse_mac_bad_a), .pulse_mac_tx_good(pulse_mac_txg_a),
        .pulse_rgmii_rx_act(pulse_rgmii_act_a)
    );

    // ------------------------------------------------------------
    // RGMII MAC + 125 MHz logic clock
    // ------------------------------------------------------------
    logic logic_clk, logic_rst_n, rst_n_logic;
    logic [7:0] mac_tx_tdata, mac_rx_tdata;
    logic       mac_tx_tvalid, mac_tx_tready, mac_tx_tlast, mac_tx_tuser;
    logic       mac_rx_tvalid, mac_rx_tready, mac_rx_tlast, mac_rx_tuser;
    logic       mac_rx_bad_frame, mac_rx_bad_fcs, mac_rx_good, mac_tx_good;

    logic [8:0] rgmii_dly_tap_l;
    logic       rgmii_dly_load_l;

    rgmii_mac_wrap #(.USE_CLK90(RGMII_TX_USE_CLK90)) u_mac (
        .sys_clk_200m(sys_clk_200m), .sys_rst_n(sys_rst_n),
        .tx_axis_tdata(mac_tx_tdata), .tx_axis_tvalid(mac_tx_tvalid),
        .tx_axis_tready(mac_tx_tready), .tx_axis_tlast(mac_tx_tlast), .tx_axis_tuser(mac_tx_tuser),
        .rx_axis_tdata(mac_rx_tdata), .rx_axis_tvalid(mac_rx_tvalid),
        .rx_axis_tready(mac_rx_tready), .rx_axis_tlast(mac_rx_tlast), .rx_axis_tuser(mac_rx_tuser),
        .rgmii_rxc(rgmii_rxc), .rgmii_rd(rgmii_rd), .rgmii_rx_ctl(rgmii_rx_ctl),
        .rgmii_txc(rgmii_txc), .rgmii_td(rgmii_td), .rgmii_tx_ctl(rgmii_tx_ctl),
        .logic_clk(logic_clk), .logic_rst_n(logic_rst_n), .mmcm_locked(mmcm_locked),
        .speed(mac_speed), .rx_error_bad_frame(mac_rx_bad_frame), .rx_error_bad_fcs(mac_rx_bad_fcs),
        .rx_fifo_good_frame(mac_rx_good), .tx_fifo_good_frame(mac_tx_good),
        .rx_dly_tap(rgmii_dly_tap_l), .rx_dly_load(rgmii_dly_load_l)
    );

    logic soft_reset_l, ctrl_enable_l;
    logic [2:0] loopback_mode_l;
    logic [31:0] dpi_pat0_l, dpi_pat1_l, dpi_pat2_l, dpi_pat3_l;

    netsec_level_cdc #(.WIDTH(1))  u_cdc_sr  (.src_clk(axi_clk), .src_level(soft_reset),   .dst_clk(logic_clk), .dst_rst_n(logic_rst_n), .dst_level(soft_reset_l));
    netsec_level_cdc #(.WIDTH(1))  u_cdc_en  (.src_clk(axi_clk), .src_level(ctrl_enable),  .dst_clk(logic_clk), .dst_rst_n(logic_rst_n), .dst_level(ctrl_enable_l));
    netsec_level_cdc #(.WIDTH(3))  u_cdc_lb  (.src_clk(axi_clk), .src_level(loopback_mode),.dst_clk(logic_clk), .dst_rst_n(logic_rst_n), .dst_level(loopback_mode_l));
    netsec_level_cdc #(.WIDTH(32)) u_cdc_p0  (.src_clk(axi_clk), .src_level(dpi_pat0),     .dst_clk(logic_clk), .dst_rst_n(logic_rst_n), .dst_level(dpi_pat0_l));
    netsec_level_cdc #(.WIDTH(32)) u_cdc_p1  (.src_clk(axi_clk), .src_level(dpi_pat1),     .dst_clk(logic_clk), .dst_rst_n(logic_rst_n), .dst_level(dpi_pat1_l));
    netsec_level_cdc #(.WIDTH(32)) u_cdc_p2  (.src_clk(axi_clk), .src_level(dpi_pat2),     .dst_clk(logic_clk), .dst_rst_n(logic_rst_n), .dst_level(dpi_pat2_l));
    netsec_level_cdc #(.WIDTH(32)) u_cdc_p3  (.src_clk(axi_clk), .src_level(dpi_pat3),     .dst_clk(logic_clk), .dst_rst_n(logic_rst_n), .dst_level(dpi_pat3_l));
    netsec_level_cdc #(.WIDTH(1))  u_cdc_aesdp (.src_clk(axi_clk), .src_level(aes_dp_en), .dst_clk(logic_clk), .dst_rst_n(logic_rst_n), .dst_level(aes_dp_en_l));
    netsec_level_cdc #(.WIDTH(128)) u_cdc_akey (.src_clk(axi_clk), .src_level(aes_key), .dst_clk(logic_clk), .dst_rst_n(logic_rst_n), .dst_level(aes_key_l));
    netsec_level_cdc #(.WIDTH(128)) u_cdc_adpct (.src_clk(logic_clk), .src_level(aes_dp_ct), .dst_clk(axi_clk), .dst_rst_n(axi_por_n), .dst_level(aes_dp_ct_a));
    netsec_pulse_cdc u_cdc_adp (.src_clk(logic_clk), .src_rst_n(rst_n_logic), .src_pulse(aes_dp_done),
        .dst_clk(axi_clk), .dst_rst_n(axi_por_n), .dst_pulse(aes_dp_done_a));

    assign rst_n_logic = logic_rst_n & ~soft_reset_l;

    netsec_pulse_cdc u_cdc_rx  (.src_clk(logic_clk), .src_rst_n(rst_n_logic), .src_pulse(pulse_rx),
        .dst_clk(axi_clk), .dst_rst_n(axi_por_n), .dst_pulse(pulse_rx_a));
    netsec_pulse_cdc u_cdc_tx  (.src_clk(logic_clk), .src_rst_n(rst_n_logic), .src_pulse(pulse_tx),
        .dst_clk(axi_clk), .dst_rst_n(axi_por_n), .dst_pulse(pulse_tx_a));
    netsec_pulse_cdc u_cdc_fwd (.src_clk(logic_clk), .src_rst_n(rst_n_logic), .src_pulse(pulse_fwd),
        .dst_clk(axi_clk), .dst_rst_n(axi_por_n), .dst_pulse(pulse_fwd_a));
    netsec_pulse_cdc u_cdc_drp (.src_clk(logic_clk), .src_rst_n(rst_n_logic), .src_pulse(pulse_drop),
        .dst_clk(axi_clk), .dst_rst_n(axi_por_n), .dst_pulse(pulse_drop_a));
    netsec_pulse_cdc u_cdc_mir (.src_clk(logic_clk), .src_rst_n(rst_n_logic), .src_pulse(pulse_mir),
        .dst_clk(axi_clk), .dst_rst_n(axi_por_n), .dst_pulse(pulse_mir_a));
    netsec_pulse_cdc u_cdc_dpi (.src_clk(logic_clk), .src_rst_n(rst_n_logic), .src_pulse(pulse_dpi),
        .dst_clk(axi_clk), .dst_rst_n(axi_por_n), .dst_pulse(pulse_dpi_a));
    netsec_level_cdc #(.WIDTH(9)) u_cdc_tap (
        .src_clk(axi_clk), .src_level(rgmii_dly_tap),
        .dst_clk(logic_clk), .dst_rst_n(logic_rst_n), .dst_level(rgmii_dly_tap_l));
    netsec_pulse_cdc u_cdc_ld (
        .src_clk(axi_clk), .src_rst_n(axi_por_n), .src_pulse(rgmii_dly_load),
        .dst_clk(logic_clk), .dst_rst_n(logic_rst_n), .dst_pulse(rgmii_dly_load_l));
    netsec_pulse_cdc u_cdc_mg  (.src_clk(logic_clk), .src_rst_n(rst_n_logic), .src_pulse(mac_rx_good),
        .dst_clk(axi_clk), .dst_rst_n(axi_por_n), .dst_pulse(pulse_mac_good_a));
    netsec_pulse_cdc u_cdc_fcs (.src_clk(logic_clk), .src_rst_n(rst_n_logic), .src_pulse(mac_rx_bad_fcs),
        .dst_clk(axi_clk), .dst_rst_n(axi_por_n), .dst_pulse(pulse_mac_fcs_a));
    netsec_pulse_cdc u_cdc_bad (.src_clk(logic_clk), .src_rst_n(rst_n_logic), .src_pulse(mac_rx_bad_frame),
        .dst_clk(axi_clk), .dst_rst_n(axi_por_n), .dst_pulse(pulse_mac_bad_a));
    netsec_pulse_cdc u_cdc_txg (.src_clk(logic_clk), .src_rst_n(rst_n_logic), .src_pulse(mac_tx_good),
        .dst_clk(axi_clk), .dst_rst_n(axi_por_n), .dst_pulse(pulse_mac_txg_a));

    // 0x6C: RXC alive. Cannot tap RXD/CTL (IDELAY IDATAIN exclusive,
    // DATAOUT cannot enter fabric). A free-running /256 on rgmii_rxc
    // stays 0 if the PHY clock is absent.
    logic rxc_rst_n, rgmii_act_pulse;
    logic [1:0] rxc_rst_sync;
    logic [7:0] rxc_div;
    always_ff @(posedge rgmii_rxc or negedge axi_por_n) begin
        if (!axi_por_n)
            rxc_rst_sync <= 2'b00;
        else
            rxc_rst_sync <= {rxc_rst_sync[0], 1'b1};
    end
    assign rxc_rst_n = rxc_rst_sync[1];
    always_ff @(posedge rgmii_rxc or negedge rxc_rst_n) begin
        if (!rxc_rst_n) begin
            rxc_div <= 8'd0;
            rgmii_act_pulse <= 1'b0;
        end else begin
            rxc_div <= rxc_div + 1'b1;
            rgmii_act_pulse <= (rxc_div == 8'hFF);
        end
    end
    netsec_pulse_cdc u_cdc_act (
        .src_clk(rgmii_rxc), .src_rst_n(rxc_rst_n), .src_pulse(rgmii_act_pulse),
        .dst_clk(axi_clk), .dst_rst_n(axi_por_n), .dst_pulse(pulse_rgmii_act_a));

    // PHY reset release (~8.4 ms @ 125 MHz)
    logic [23:0] phy_rst_cnt;
    always_ff @(posedge logic_clk or negedge logic_rst_n) begin
        if (!logic_rst_n) begin
            phy_rst_cnt <= '0;
            phy_reset_n <= 1'b0;
        end else begin
            if (phy_rst_cnt != {24{1'b1}})
                phy_rst_cnt <= phy_rst_cnt + 1'b1;
            phy_reset_n <= (phy_rst_cnt > 24'h10_0000);
        end
    end

    // ------------------------------------------------------------
    // MDIO master + BMSR poll for phy_link
    // ------------------------------------------------------------
    logic        mdio_o, mdio_t, mdio_i;
    logic        mdio_start, mdio_we_i, mdio_done_i;
    logic [4:0]  mdio_phy_i, mdio_reg_i;
    logic [15:0] mdio_wd_i, mdio_rd_i;
    logic        mdio_busy_i;

    IOBUF u_mdio_iobuf (
        .I(mdio_o), .O(mdio_i), .T(mdio_t), .IO(mdio_mdio)
    );

    mdio_master u_mdio (
        .clk(axi_clk), .rst_n(axi_por_n),
        .start(mdio_start), .we(mdio_we_i),
        .phy_addr(mdio_phy_i), .reg_addr(mdio_reg_i),
        .wdata(mdio_wd_i), .rdata(mdio_rd_i),
        .busy(mdio_busy_i), .done(mdio_done_i),
        .mdc(mdio_mdc), .mdio_o(mdio_o), .mdio_t(mdio_t), .mdio_i(mdio_i)
    );

    logic [15:0] mdio_host_rdata;
    assign mdio_busy = mdio_busy_i;
    assign mdio_done = mdio_done_i;
    assign mdio_rdata = mdio_host_rdata;

    // Host-triggered access has priority; otherwise poll BMSR(0x01) bit 2
    logic [19:0] poll_cnt;
    logic        poll_req;
    logic        host_pend;
    logic        last_was_poll;

    always_ff @(posedge axi_clk or negedge axi_por_n) begin
        if (!axi_por_n) begin
            poll_cnt        <= '0;
            poll_req        <= 1'b0;
            host_pend       <= 1'b0;
            last_was_poll   <= 1'b0;
            phy_link        <= 1'b0;
            mdio_start      <= 1'b0;
            mdio_we_i       <= 1'b0;
            mdio_phy_i      <= 5'd1;
            mdio_reg_i      <= 5'd1;
            mdio_wd_i       <= '0;
            mdio_host_rdata <= '0;
        end else begin
            mdio_start <= 1'b0;
            if (mdio_go)
                host_pend <= 1'b1;
            if (poll_cnt == 20'd1_000_000) begin // ~10 ms
                poll_cnt <= '0;
                poll_req <= 1'b1;
            end else begin
                poll_cnt <= poll_cnt + 1'b1;
            end

            if (!mdio_busy_i && !mdio_start) begin
                if (host_pend) begin
                    mdio_start    <= 1'b1;
                    mdio_we_i     <= mdio_we;
                    mdio_phy_i    <= mdio_phy_addr;
                    mdio_reg_i    <= mdio_reg_addr;
                    mdio_wd_i     <= mdio_wdata;
                    host_pend     <= 1'b0;
                    last_was_poll <= 1'b0;
                end else if (poll_req) begin
                    mdio_start    <= 1'b1;
                    mdio_we_i     <= 1'b0;
                    mdio_phy_i    <= 5'd1;
                    mdio_reg_i    <= 5'd1; // BMSR
                    mdio_wd_i     <= '0;
                    poll_req      <= 1'b0;
                    last_was_poll <= 1'b1;
                end
            end

            if (mdio_done_i && last_was_poll)
                phy_link <= mdio_rd_i[2];
            if (mdio_done_i && !last_was_poll)
                mdio_host_rdata <= mdio_rd_i;
        end
    end

    // ------------------------------------------------------------
    // L0 packet generator
    // ------------------------------------------------------------
    logic [7:0] gen_tdata;
    logic       gen_tvalid, gen_tready, gen_tlast;
    logic       start_pulse;

    // W1P on axi_clk is 1 cycle @ 100 MHz — 2FF into 125 MHz can drop it.
    netsec_pulse_cdc u_cdc_start (
        .src_clk(axi_clk), .src_rst_n(axi_por_n), .src_pulse(pkt_gen_start),
        .dst_clk(logic_clk), .dst_rst_n(logic_rst_n), .dst_pulse(start_pulse)
    );

    pkt_gen_bram u_gen (
        .clk(logic_clk), .rst_n(rst_n_logic), .start(start_pulse),
        .m_tdata(gen_tdata), .m_tvalid(gen_tvalid), .m_tready(gen_tready),
        .m_tlast(gen_tlast), .busy()
    );

    // ------------------------------------------------------------
    // Datapath
    // ------------------------------------------------------------
    logic [7:0] dp_s_tdata, dp_m_tdata;
    logic       dp_s_tvalid, dp_s_tready, dp_s_tlast;
    logic       dp_m_tvalid, dp_m_tready, dp_m_tlast;

    netsec_datapath #(.FRAME_DEPTH(2048)) u_dp (
        .clk(logic_clk), .rst_n(rst_n_logic), .enable(ctrl_enable_l),
        .s_tdata(dp_s_tdata), .s_tvalid(dp_s_tvalid), .s_tready(dp_s_tready), .s_tlast(dp_s_tlast),
        .m_tdata(dp_m_tdata), .m_tvalid(dp_m_tvalid), .m_tready(dp_m_tready), .m_tlast(dp_m_tlast),
        .mirror_pulse(), .last_action(last_action),
        .stat_rx_frame(pulse_rx), .stat_tx_frame(pulse_tx),
        .stat_forward(pulse_fwd), .stat_drop(pulse_drop),
        .stat_mirror(pulse_mir), .stat_dpi_hit(pulse_dpi),
        .flow_update_valid(), .flow_update_state(),
        .dpi_pat0(dpi_pat0_l), .dpi_pat1(dpi_pat1_l),
        .dpi_pat2(dpi_pat2_l), .dpi_pat3(dpi_pat3_l),
        .aes_dp_en(aes_dp_en_l), .aes_key(aes_key_l),
        .aes_dp_ct(aes_dp_ct), .aes_dp_done(aes_dp_done)
    );

    // ------------------------------------------------------------
    // L1 AXIS loop FIFO
    // ------------------------------------------------------------
    logic [8:0] l1_wdata, l1_rdata;
    logic       l1_wr, l1_rd, l1_full, l1_empty;

    u_sync_fifo #(.DATA_WIDTH(9), .DEPTH(512)) u_l1_fifo (
        .clk(logic_clk), .rst_n(rst_n_logic),
        .wr_en(l1_wr), .wr_data(l1_wdata), .full(l1_full),
        .rd_en(l1_rd), .rd_data(l1_rdata), .empty(l1_empty)
    );

    logic l0_mode, l1_mode, wire_mode;
    assign l0_mode   = (loopback_mode_l == 3'd1);
    assign l1_mode   = (loopback_mode_l == 3'd2);
    assign wire_mode = (loopback_mode_l == 3'd0) || (loopback_mode_l == 3'd3) || (loopback_mode_l == 3'd4);

    always_comb begin
        dp_s_tdata    = 8'h00;
        dp_s_tvalid   = 1'b0;
        dp_s_tlast    = 1'b0;
        gen_tready    = 1'b0;
        mac_rx_tready = 1'b1;
        mac_tx_tdata  = dp_m_tdata;
        mac_tx_tvalid = 1'b0;
        mac_tx_tlast  = dp_m_tlast;
        mac_tx_tuser  = 1'b0;
        dp_m_tready   = 1'b1;
        l1_wr         = 1'b0;
        l1_wdata      = 9'd0;
        l1_rd         = 1'b0;

        if (l0_mode) begin
            dp_s_tdata  = gen_tdata;
            dp_s_tvalid = gen_tvalid;
            dp_s_tlast  = gen_tlast;
            gen_tready  = dp_s_tready;
            dp_m_tready = 1'b1;
        end else if (l1_mode) begin
            // pkt_gen -> datapath; datapath TX -> L1 FIFO (drained); no RGMII TX
            dp_s_tdata  = gen_tdata;
            dp_s_tvalid = gen_tvalid;
            dp_s_tlast  = gen_tlast;
            gen_tready  = dp_s_tready;
            l1_wr       = dp_m_tvalid && !l1_full;
            l1_wdata    = {dp_m_tlast, dp_m_tdata};
            dp_m_tready = !l1_full;
            l1_rd       = !l1_empty;
            mac_tx_tvalid = 1'b0;
        end else begin
            // Wire / PHY / SFP: pkt_gen has priority so L2 can inject without a PC
            if (gen_tvalid) begin
                dp_s_tdata    = gen_tdata;
                dp_s_tvalid   = gen_tvalid;
                dp_s_tlast    = gen_tlast;
                gen_tready    = dp_s_tready;
                mac_rx_tready = 1'b1;
            end else begin
                dp_s_tdata    = mac_rx_tdata;
                dp_s_tvalid   = mac_rx_tvalid;
                dp_s_tlast    = mac_rx_tlast;
                mac_rx_tready = dp_s_tready;
                gen_tready    = 1'b1;
            end
            mac_tx_tvalid = dp_m_tvalid;
            dp_m_tready   = mac_tx_tready;
        end
    end

    // ------------------------------------------------------------
    // SFP / GT: stub unless NETSEC_ENABLE_SFP (then near-end PMA PRBS)
    // ------------------------------------------------------------
    logic gthrxn_i, gthrxp_i, gthtxn_o, gthtxp_o;
`ifdef NETSEC_SFP_PORTS
    assign gthrxn_i   = gthrxn_in;
    assign gthrxp_i   = gthrxp_in;
    assign gthtxn_out = gthtxn_o;
    assign gthtxp_out = gthtxp_o;
`else
    assign gthrxn_i = 1'b0;
    assign gthrxp_i = 1'b0;
`endif

    generate
        if (NETSEC_ENABLE_SFP) begin : g_gt
            gt_prbs_wrap #(.ENABLE(1'b1)) u_gt (
                .freerun_clk(axi_clk),
                .rst_n(axi_por_n),
                .nearend_loopback(loopback_mode_l == 3'd4),
                .mgtrefclk_p(mgtrefclk_p),
                .mgtrefclk_n(mgtrefclk_n),
                .gthrxn_in(gthrxn_i),
                .gthrxp_in(gthrxp_i),
                .gthtxn_out(gthtxn_o),
                .gthtxp_out(gthtxp_o),
                .sfp_tx_dis(sfp_tx_dis),
                .sfp1_los(sfp1_los),
                .sfp2_los(sfp2_los),
                .prbs_match(),
                .link_status(sfp_link_status),
                .status_vector(sfp_status_vector)
            );
        end else begin : g_sfp_stub
            sfp_pcs_wrap #(.ENABLE(1'b0)) u_sfp (
                .freerun_clk(logic_clk),
                .rst_n(rst_n_logic),
                .gt_loopback_en(loopback_mode_l == 3'd4),
                .mgtrefclk_p(mgtrefclk_p),
                .mgtrefclk_n(mgtrefclk_n),
                .gthrxn_in(gthrxn_i),
                .gthrxp_in(gthrxp_i),
                .gthtxn_out(gthtxn_o),
                .gthtxp_out(gthtxp_o),
                .sfp_tx_dis(sfp_tx_dis),
                .sfp1_los(sfp1_los),
                .sfp2_los(sfp2_los),
                .sfp_link_status(sfp_link_status),
                .sfp_status_vector(sfp_status_vector)
            );
        end
    endgenerate

    // ------------------------------------------------------------
    // Heartbeat LED + UART TX idle
    // ------------------------------------------------------------
    logic [24:0] hb;
    always_ff @(posedge axi_clk or negedge axi_por_n) begin
        if (!axi_por_n) hb <= '0;
        else            hb <= hb + 1'b1;
    end
    assign pl_led     = hb[24]; // ~1.5 Hz @ 100 MHz — visible even if MMCM unlocked
    assign pl_uart_tx = 1'b1;

    // ------------------------------------------------------------
    // ILA
    // ------------------------------------------------------------
    generate
        if (NETSEC_ENABLE_ILA) begin : g_ila
            logic [10:0] probe_s, probe_m, probe_rx, probe_tx;
            logic [15:0] probe_st;
            assign probe_s  = {dp_s_tlast, dp_s_tready, dp_s_tvalid, dp_s_tdata};
            assign probe_m  = {dp_m_tlast, dp_m_tready, dp_m_tvalid, dp_m_tdata};
            assign probe_rx = {mac_rx_tlast, mac_rx_tready, mac_rx_tvalid, mac_rx_tdata};
            assign probe_tx = {mac_tx_tlast, mac_tx_tready, mac_tx_tvalid, mac_tx_tdata};
            assign probe_st = {l1_empty, l1_full, pulse_dpi, pulse_mir, pulse_drop,
                               pulse_fwd, pulse_tx, pulse_rx, last_action, loopback_mode_l, 3'b000};

            ila_logic u_ila_logic (
                .clk   (logic_clk),
                .probe0(probe_s),
                .probe1(probe_m),
                .probe2(probe_rx),
                .probe3(probe_tx),
                .probe4(probe_st)
            );

            ila_rgmii u_ila_rgmii (
                .clk   (rgmii_rxc),
                .probe0(5'b0)
            );
        end
    endgenerate

    u_aes128_core u_aes (
        .clk(axi_clk), .rst_n(axi_por_n),
        .start(aes_start), .key(aes_key), .plaintext(aes_pt),
        .done(aes_done), .ciphertext(aes_ct)
    );

    u_checksum_rfc1071 u_csum (
        .clk(axi_clk), .rst_n(axi_por_n),
        .start(csum_start), .data_valid(csum_dv),
        .data(csum_data), .data_last(csum_last),
        .checksum_valid(csum_valid), .checksum(csum_res)
    );

    u_modexp_demo #(.WIDTH(32)) u_modexp (
        .clk(axi_clk), .rst_n(axi_por_n),
        .start(mx_start), .base_in(mx_base), .exp_in(mx_exp), .mod_in(mx_mod),
        .done(mx_done), .result(mx_res)
    );

    logic _unused;
    assign _unused = pl_uart_rx | wire_mode | sfp_link_status;

endmodule
