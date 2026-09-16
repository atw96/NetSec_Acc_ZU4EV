// system_top_sfp.sv — L4-only image: GT Wizard PRBS near-end (factory gt_test path)
`timescale 1ns / 1ps

module system_top_sfp (
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
    input  logic        pl_key_n,
    output logic        pl_led,
    output logic        pl_uart_tx,
    input  logic        pl_uart_rx,
    input  logic        mgtrefclk_p,
    input  logic        mgtrefclk_n,
    input  logic        gthrxn_in,
    input  logic        gthrxp_in,
    output logic        gthtxn_out,
    output logic        gthtxp_out,
    output logic        sfp_tx_dis,
    input  logic        sfp1_los,
    input  logic        sfp2_los
);

    logic sys_clk_200m;
    IBUFDS #(
        .DIFF_TERM("FALSE"),
        .IBUF_LOW_PWR("TRUE"),
        .IOSTANDARD("DIFF_SSTL12")
    ) u_ibuf (
        .I(sys_clk_clk_p), .IB(sys_clk_clk_n), .O(sys_clk_200m)
    );

    // GT Wizard 1.25G: freerun must be <= 78.125 MHz
    logic clk_50m;
    BUFGCE_DIV #(.BUFGCE_DIVIDE(4)) u_div (
        .I(sys_clk_200m), .CE(1'b1), .CLR(1'b0), .O(clk_50m)
    );

    logic [7:0] por;
    logic rst_n;
    always_ff @(posedge clk_50m) begin
        if (!pl_key_n)
            por <= 8'd0;
        else if (por != 8'hFF)
            por <= por + 1'b1;
    end
    assign rst_n = (por == 8'hFF);

    logic prbs_match, link_status;
    logic [15:0] status_vector;
`ifdef SFP_OPTICAL
    localparam bit NEAR_END_PMA = 1'b0;
`else
    localparam bit NEAR_END_PMA = 1'b1;
`endif

    gt_prbs_wrap #(.ENABLE(1'b1)) u_gt (
        .freerun_clk(clk_50m),
        .rst_n(rst_n),
        .nearend_loopback(NEAR_END_PMA),
        .mgtrefclk_p(mgtrefclk_p),
        .mgtrefclk_n(mgtrefclk_n),
        .gthrxn_in(gthrxn_in),
        .gthrxp_in(gthrxp_in),
        .gthtxn_out(gthtxn_out),
        .gthtxp_out(gthtxp_out),
        .sfp_tx_dis(sfp_tx_dis),
        .sfp1_los(sfp1_los),
        .sfp2_los(sfp2_los),
        .prbs_match(prbs_match),
        .link_status(link_status),
        .status_vector(status_vector)
    );

    logic [24:0] hb;
    always_ff @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) hb <= '0;
        else        hb <= hb + 1'b1;
    end
    logic link_meta, link_sync, match_meta, match_sync;
    always_ff @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            link_meta  <= 1'b0;
            link_sync  <= 1'b0;
            match_meta <= 1'b0;
            match_sync <= 1'b0;
        end else begin
            link_meta  <= link_status;
            link_sync  <= link_meta;
            match_meta <= prbs_match;
            match_sync <= match_meta;
        end
    end
    assign pl_led     = link_sync ? match_sync : hb[24];
    assign pl_uart_tx = 1'b1;

    assign rgmii_txc    = 1'b0;
    assign rgmii_td     = 4'd0;
    assign rgmii_tx_ctl = 1'b0;
    assign mdio_mdc     = 1'b0;
    assign phy_reset_n  = 1'b0;
    logic _u;
    assign _u = pl_uart_rx ^ |status_vector;

endmodule
