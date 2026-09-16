// gt_prbs_wrap.sv — L4 near-end PMA PRBS (factory gt_test path, 1 lane)
// ENABLE=0: stub. ENABLE=1: gt_sfp_prbs (scripts/create_gt_prbs.tcl)
`timescale 1ns / 1ps

module gt_prbs_wrap #(
    parameter bit ENABLE = 1'b0
) (
    input  logic        freerun_clk,
    input  logic        rst_n,
    input  logic        nearend_loopback,

    input  logic        mgtrefclk_p,
    input  logic        mgtrefclk_n,
    input  logic        gthrxn_in,
    input  logic        gthrxp_in,
    output logic        gthtxn_out,
    output logic        gthtxp_out,

    output logic        sfp_tx_dis,
    input  logic        sfp1_los,
    input  logic        sfp2_los,

    output logic        prbs_match,
    output logic        link_status,
    output logic [15:0] status_vector
);

    assign sfp_tx_dis = 1'b0;

    generate
        if (!ENABLE) begin : g_stub
            assign gthtxn_out    = 1'b0;
            assign gthtxp_out    = 1'b0;
            assign prbs_match    = 1'b0;
            assign link_status   = 1'b0;
            assign status_vector = {13'd0, nearend_loopback, sfp2_los, sfp1_los};
            logic _u;
            assign _u = freerun_clk ^ rst_n ^ mgtrefclk_p ^ mgtrefclk_n ^
                        gthrxn_in ^ gthrxp_in;
        end else begin : g_gt
            logic        refclk1;
            logic        tx_clk, rx_clk;
            logic        tx_active, rx_active;
            logic        reset_tx_done, reset_rx_done;
            logic [15:0] tx_data, rx_data;
            logic [15:0] prbs;
            logic [15:0] match_cnt;
            logic        match_q;
            logic [15:0] rx_state;
            logic        rx_synced;

            IBUFDS_GTE4 #(
                .REFCLK_EN_TX_PATH (1'b0),
                .REFCLK_HROW_CK_SEL(2'b00),
                .REFCLK_ICNTL_RX   (2'b00)
            ) u_refclk (
                .I    (mgtrefclk_p),
                .IB   (mgtrefclk_n),
                .CEB  (1'b0),
                .O    (refclk1),
                .ODIV2()
            );

            assign tx_data = prbs;

            always_ff @(posedge tx_clk or negedge rst_n) begin
                if (!rst_n)
                    prbs <= 16'hACE1;
                else if (tx_active)
                    prbs <= {prbs[14:0], prbs[15] ^ prbs[13] ^ prbs[12] ^ prbs[10]};
            end

            always_ff @(posedge rx_clk or negedge rst_n) begin
                if (!rst_n) begin
                    match_cnt <= '0;
                    match_q   <= 1'b0;
                    rx_state  <= 16'h0;
                    rx_synced <= 1'b0;
                end else if (rx_active && reset_rx_done) begin
                    if (!rx_synced) begin
                        rx_state  <= rx_data;
                        rx_synced <= 1'b1;
                        match_cnt <= '0;
                    end else begin
                        if (rx_data == {rx_state[14:0],
                                        rx_state[15] ^ rx_state[13] ^ rx_state[12] ^ rx_state[10]})
                            match_cnt <= (match_cnt == 16'hffff) ? match_cnt : match_cnt + 1'b1;
                        else
                            match_cnt <= '0;
                        rx_state <= rx_data;
                    end
                    match_q <= (match_cnt > 16'd256);
                end
            end

            assign prbs_match  = match_q;
            assign link_status = reset_tx_done & reset_rx_done & tx_active & rx_active;
            assign status_vector = {8'd0, match_q, link_status, reset_rx_done,
                                    reset_tx_done, rx_active, tx_active,
                                    nearend_loopback, 1'b1};

            gt_sfp_prbs u_gt (
                .gtwiz_userclk_tx_reset_in         (~rst_n),
                .gtwiz_userclk_tx_srcclk_out       (),
                .gtwiz_userclk_tx_usrclk_out       (),
                .gtwiz_userclk_tx_usrclk2_out      (tx_clk),
                .gtwiz_userclk_tx_active_out       (tx_active),
                .gtwiz_userclk_rx_reset_in         (~rst_n),
                .gtwiz_userclk_rx_srcclk_out       (),
                .gtwiz_userclk_rx_usrclk_out       (),
                .gtwiz_userclk_rx_usrclk2_out      (rx_clk),
                .gtwiz_userclk_rx_active_out       (rx_active),
                .gtwiz_reset_clk_freerun_in        (freerun_clk),
                .gtwiz_reset_all_in                (~rst_n),
                .gtwiz_reset_tx_pll_and_datapath_in(1'b0),
                .gtwiz_reset_tx_datapath_in        (1'b0),
                .gtwiz_reset_rx_pll_and_datapath_in(1'b0),
                .gtwiz_reset_rx_datapath_in        (1'b0),
                .gtwiz_reset_rx_cdr_stable_out     (),
                .gtwiz_reset_tx_done_out           (reset_tx_done),
                .gtwiz_reset_rx_done_out           (reset_rx_done),
                .gtwiz_userdata_tx_in              (tx_data),
                .gtwiz_userdata_rx_out             (rx_data),
                .gtrefclk01_in                     (refclk1),
                .qpll1outclk_out                   (),
                .qpll1outrefclk_out                (),
                .gthrxn_in                         (gthrxn_in),
                .gthrxp_in                         (gthrxp_in),
                .gthtxn_out                        (gthtxn_out),
                .gthtxp_out                        (gthtxp_out),
                .loopback_in                       (nearend_loopback ? 3'b010 : 3'b000),
                .gtpowergood_out                   (),
                .rxpmaresetdone_out                (),
                .txpmaresetdone_out                ()
            );
        end
    endgenerate

endmodule
