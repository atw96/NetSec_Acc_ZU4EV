// system_top_sfp10g.sv — independent 10G dual-SFP fiber loopback image
// Does not replace system_top / system_top_rxdly. jtag_axi @ 0x80050000.
`timescale 1ns / 1ps

module system_top_sfp10g (
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
    input  logic [1:0]  gthrxn_in,
    input  logic [1:0]  gthrxp_in,
    output logic [1:0]  gthtxn_out,
    output logic [1:0]  gthtxp_out,
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

    logic axi_clk;
    logic clk_50m;
    BUFGCE_DIV #(.BUFGCE_DIVIDE(2)) u_axi_div (
        .I(sys_clk_200m), .CE(1'b1), .CLR(1'b0), .O(axi_clk)
    );
    BUFGCE_DIV #(.BUFGCE_DIVIDE(4)) u_div50 (
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

    logic axi_aresetn;
    u_reset_sync u_axi_rst (.clk(axi_clk), .async_rst_n(rst_n), .sync_rst_n(axi_aresetn));

    logic [39:0] M_AXI_awaddr;
    logic [2:0]  M_AXI_awprot;
    logic        M_AXI_awvalid, M_AXI_awready;
    logic [31:0] M_AXI_wdata;
    logic [3:0]  M_AXI_wstrb;
    logic        M_AXI_wvalid, M_AXI_wready;
    logic [1:0]  M_AXI_bresp;
    logic        M_AXI_bvalid, M_AXI_bready;
    logic [39:0] M_AXI_araddr;
    logic [2:0]  M_AXI_arprot;
    logic        M_AXI_arvalid, M_AXI_arready;
    logic [31:0] M_AXI_rdata;
    logic [1:0]  M_AXI_rresp;
    logic        M_AXI_rvalid, M_AXI_rready;

    design_1_wrapper bd_i (
        .axi_clk_in(axi_clk),
        .axi_aresetn_in(axi_aresetn),
        .M_AXI_awaddr(M_AXI_awaddr),
        .M_AXI_awprot(M_AXI_awprot),
        .M_AXI_awvalid(M_AXI_awvalid),
        .M_AXI_awready(M_AXI_awready),
        .M_AXI_wdata(M_AXI_wdata),
        .M_AXI_wstrb(M_AXI_wstrb),
        .M_AXI_wvalid(M_AXI_wvalid),
        .M_AXI_wready(M_AXI_wready),
        .M_AXI_bresp(M_AXI_bresp),
        .M_AXI_bvalid(M_AXI_bvalid),
        .M_AXI_bready(M_AXI_bready),
        .M_AXI_araddr(M_AXI_araddr),
        .M_AXI_arprot(M_AXI_arprot),
        .M_AXI_arvalid(M_AXI_arvalid),
        .M_AXI_arready(M_AXI_arready),
        .M_AXI_rdata(M_AXI_rdata),
        .M_AXI_rresp(M_AXI_rresp),
        .M_AXI_rvalid(M_AXI_rvalid),
        .M_AXI_rready(M_AXI_rready)
    );

    logic tx_enable, soft_reset;
    logic gt_tx_done, gt_rx_done;
    logic block_lock0, block_lock1, rx_status0, rx_status1, high_ber0, high_ber1;
    logic p_tx0, p_rx0, p_bad0, p_tx1, p_rx1, p_bad1;
    logic los1_m, los1_s, los2_m, los2_s;
    logic lock0_m, lock0_s, lock1_m, lock1_s;
    logic st0_m, st0_s, st1_m, st1_s;
    logic hb0_m, hb0_s, hb1_m, hb1_s;
    logic txd_m, txd_s, rxd_m, rxd_s;

    always_ff @(posedge axi_clk or negedge axi_aresetn) begin
        if (!axi_aresetn) begin
            {los1_m, los1_s, los2_m, los2_s} <= '0;
            {lock0_m, lock0_s, lock1_m, lock1_s} <= '0;
            {st0_m, st0_s, st1_m, st1_s} <= '0;
            {hb0_m, hb0_s, hb1_m, hb1_s} <= '0;
            {txd_m, txd_s, rxd_m, rxd_s} <= '0;
        end else begin
            {los1_s, los1_m} <= {los1_m, sfp1_los};
            {los2_s, los2_m} <= {los2_m, sfp2_los};
            {lock0_s, lock0_m} <= {lock0_m, block_lock0};
            {lock1_s, lock1_m} <= {lock1_m, block_lock1};
            {st0_s, st0_m} <= {st0_m, rx_status0};
            {st1_s, st1_m} <= {st1_m, rx_status1};
            {hb0_s, hb0_m} <= {hb0_m, high_ber0};
            {hb1_s, hb1_m} <= {hb1_m, high_ber1};
            {txd_s, txd_m} <= {txd_m, gt_tx_done};
            {rxd_s, rxd_m} <= {rxd_m, gt_rx_done};
        end
    end

    sfp10g_regs u_regs (
        .aclk(axi_clk),
        .aresetn(axi_aresetn),
        .s_axi_awaddr(M_AXI_awaddr[31:0]),
        .s_axi_awvalid(M_AXI_awvalid),
        .s_axi_awready(M_AXI_awready),
        .s_axi_wdata(M_AXI_wdata),
        .s_axi_wstrb(M_AXI_wstrb),
        .s_axi_wvalid(M_AXI_wvalid),
        .s_axi_wready(M_AXI_wready),
        .s_axi_bresp(M_AXI_bresp),
        .s_axi_bvalid(M_AXI_bvalid),
        .s_axi_bready(M_AXI_bready),
        .s_axi_araddr(M_AXI_araddr[31:0]),
        .s_axi_arvalid(M_AXI_arvalid),
        .s_axi_arready(M_AXI_arready),
        .s_axi_rdata(M_AXI_rdata),
        .s_axi_rresp(M_AXI_rresp),
        .s_axi_rvalid(M_AXI_rvalid),
        .s_axi_rready(M_AXI_rready),
        .tx_enable(tx_enable),
        .soft_reset(soft_reset),
        .por_ok(rst_n),
        .gt_tx_done(txd_s),
        .gt_rx_done(rxd_s),
        .sfp1_los(los1_s),
        .sfp2_los(los2_s),
        .block_lock0(lock0_s),
        .block_lock1(lock1_s),
        .rx_status0(st0_s),
        .rx_status1(st1_s),
        .high_ber0(hb0_s),
        .high_ber1(hb1_s),
        .pulse_tx0(p_tx0),
        .pulse_rx0(p_rx0),
        .pulse_bad0(p_bad0),
        .pulse_tx1(p_tx1),
        .pulse_rx1(p_rx1),
        .pulse_bad1(p_bad1)
    );

    logic rst_n_gt;
    assign rst_n_gt = rst_n & ~soft_reset;

    sfp10g_wrap u_sfp (
        .freerun_clk(clk_50m),
        .axi_clk(axi_clk),
        .rst_n(rst_n_gt),
        .tx_enable(tx_enable),
        .nearend_loopback(1'b0),
        .tx_src(2'b00),
        .tx_clk(), .rx_clk0(), .rx_clk1(),
        .rst_tx_n(), .rst_rx0_n(), .rst_rx1_n(),
        .tx0_axis_tdata(64'd0), .tx0_axis_tkeep(8'd0), .tx0_axis_tvalid(1'b0),
        .tx0_axis_tready(), .tx0_axis_tlast(1'b0), .tx0_axis_tuser(1'b0),
        .rx0_axis_tdata(), .rx0_axis_tkeep(), .rx0_axis_tvalid(),
        .rx0_axis_tready(1'b1), .rx0_axis_tlast(), .rx0_axis_tuser(),
        .tx1_axis_tdata(64'd0), .tx1_axis_tkeep(8'd0), .tx1_axis_tvalid(1'b0),
        .tx1_axis_tready(), .tx1_axis_tlast(1'b0), .tx1_axis_tuser(1'b0),
        .rx1_axis_tdata(), .rx1_axis_tkeep(), .rx1_axis_tvalid(),
        .rx1_axis_tready(1'b1), .rx1_axis_tlast(), .rx1_axis_tuser(),
        .mgtrefclk_p(mgtrefclk_p),
        .mgtrefclk_n(mgtrefclk_n),
        .gthrxn_in(gthrxn_in),
        .gthrxp_in(gthrxp_in),
        .gthtxn_out(gthtxn_out),
        .gthtxp_out(gthtxp_out),
        .sfp_tx_dis(sfp_tx_dis),
        .sfp1_los(sfp1_los),
        .sfp2_los(sfp2_los),
        .gt_tx_done(gt_tx_done),
        .gt_rx_done(gt_rx_done),
        .block_lock0(block_lock0),
        .block_lock1(block_lock1),
        .rx_status0(rx_status0),
        .rx_status1(rx_status1),
        .high_ber0(high_ber0),
        .high_ber1(high_ber1),
        .pulse_tx0_axi(p_tx0),
        .pulse_rx0_axi(p_rx0),
        .pulse_bad0_axi(p_bad0),
        .pulse_tx1_axi(p_tx1),
        .pulse_rx1_axi(p_rx1),
        .pulse_bad1_axi(p_bad1)
    );

    logic [24:0] hb;
    always_ff @(posedge axi_clk or negedge axi_aresetn) begin
        if (!axi_aresetn) hb <= '0;
        else              hb <= hb + 1'b1;
    end
    assign pl_led     = (lock0_s & lock1_s) ? 1'b1 : hb[24];
    assign pl_uart_tx = 1'b1;

    assign rgmii_txc    = 1'b0;
    assign rgmii_td     = 4'd0;
    assign rgmii_tx_ctl = 1'b0;
    assign mdio_mdc     = 1'b0;
    assign phy_reset_n  = 1'b0;
    logic _u;
    assign _u = pl_uart_rx ^ rgmii_rxc ^ |rgmii_rd ^ rgmii_rx_ctl ^ |M_AXI_awprot ^ |M_AXI_arprot;

endmodule
