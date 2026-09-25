// system_top.sv — wraps PS+JTAG-AXI BD + netsec_top
`timescale 1ns / 1ps

module system_top #(
    parameter bit NETSEC_ENABLE_SFP    = 1'b0,
    parameter bit NETSEC_ENABLE_SFP10G = 1'b1,
    parameter bit NETSEC_ENABLE_ILA    = 1'b1,
    parameter     RGMII_TX_USE_CLK90   = "TRUE"
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
    input  logic        sfp2_los

`ifdef NETSEC_SFP_PORTS
    ,
    input  logic [1:0]  gthrxn_in,
    input  logic [1:0]  gthrxp_in,
    output logic [1:0]  gthtxn_out,
    output logic [1:0]  gthtxp_out
`endif
);

    logic        axi_clk;
    logic        axi_aresetn;

    logic [39:0] M_AXI_awaddr;
    logic [2:0]  M_AXI_awprot;
    logic        M_AXI_awvalid;
    logic        M_AXI_awready;
    logic [31:0] M_AXI_wdata;
    logic [3:0]  M_AXI_wstrb;
    logic        M_AXI_wvalid;
    logic        M_AXI_wready;
    logic [1:0]  M_AXI_bresp;
    logic        M_AXI_bvalid;
    logic        M_AXI_bready;
    logic [39:0] M_AXI_araddr;
    logic [2:0]  M_AXI_arprot;
    logic        M_AXI_arvalid;
    logic        M_AXI_arready;
    logic [31:0] M_AXI_rdata;
    logic [1:0]  M_AXI_rresp;
    logic        M_AXI_rvalid;
    logic        M_AXI_rready;

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

    netsec_top #(
        .NETSEC_ENABLE_SFP(NETSEC_ENABLE_SFP),
        .NETSEC_ENABLE_SFP10G(NETSEC_ENABLE_SFP10G),
        .NETSEC_ENABLE_ILA(NETSEC_ENABLE_ILA),
        .RGMII_TX_USE_CLK90(RGMII_TX_USE_CLK90)
    ) u_netsec (
        .sys_clk_clk_p(sys_clk_clk_p),
        .sys_clk_clk_n(sys_clk_clk_n),
        .rgmii_rxc(rgmii_rxc),
        .rgmii_rd(rgmii_rd),
        .rgmii_rx_ctl(rgmii_rx_ctl),
        .rgmii_txc(rgmii_txc),
        .rgmii_td(rgmii_td),
        .rgmii_tx_ctl(rgmii_tx_ctl),
        .mdio_mdc(mdio_mdc),
        .mdio_mdio(mdio_mdio),
        .phy_reset_n(phy_reset_n),
        .pl_led(pl_led),
        .pl_key_n(pl_key_n),
        .pl_uart_tx(pl_uart_tx),
        .pl_uart_rx(pl_uart_rx),
        .mgtrefclk_p(mgtrefclk_p),
        .mgtrefclk_n(mgtrefclk_n),
        .sfp_tx_dis(sfp_tx_dis),
        .sfp1_los(sfp1_los),
        .sfp2_los(sfp2_los),
`ifdef NETSEC_SFP_PORTS
        .gthrxn_in(gthrxn_in),
        .gthrxp_in(gthrxp_in),
        .gthtxn_out(gthtxn_out),
        .gthtxp_out(gthtxp_out),
`endif
        .axi_clk(axi_clk),
        .axi_aresetn(axi_aresetn),
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
        .s_axi_rready(M_AXI_rready)
    );

endmodule
