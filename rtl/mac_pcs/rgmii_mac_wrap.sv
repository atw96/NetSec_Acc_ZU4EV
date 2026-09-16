// rgmii_mac_wrap.sv
// Wrap alexforencich eth_mac_1g_rgmii_fifo for AXU4EVB-P PL RGMII (Bank66).
// MMCM: 200 MHz sys_clk -> 125 MHz gtx_clk + gtx_clk90.
// Logic domain: logic_clk (= gtx_clk) with 8-bit AXI-Stream.
`timescale 1ns / 1ps

module rgmii_mac_wrap #(
    parameter USE_CLK90 = "TRUE"
) (
    input  logic        sys_clk_200m,
    input  logic        sys_rst_n,

    // AXI-Stream TX (logic domain, toward wire)
    input  logic [7:0]  tx_axis_tdata,
    input  logic        tx_axis_tvalid,
    output logic        tx_axis_tready,
    input  logic        tx_axis_tlast,
    input  logic        tx_axis_tuser,

    // AXI-Stream RX (logic domain, from wire)
    output logic [7:0]  rx_axis_tdata,
    output logic        rx_axis_tvalid,
    input  logic        rx_axis_tready,
    output logic        rx_axis_tlast,
    output logic        rx_axis_tuser,

    // RGMII
    input  logic        rgmii_rxc,
    input  logic [3:0]  rgmii_rd,
    input  logic        rgmii_rx_ctl,
    output logic        rgmii_txc,
    output logic [3:0]  rgmii_td,
    output logic        rgmii_tx_ctl,

    // Status / clocks out
    output logic        logic_clk,
    output logic        logic_rst_n,
    output logic        mmcm_locked,
    output logic [1:0]  speed,
    output logic        rx_error_bad_frame,
    output logic        rx_error_bad_fcs,
    output logic        rx_fifo_good_frame,
    output logic        tx_fifo_good_frame,

    // Runtime-loadable RX IDELAY (COUNT, 200 MHz ref). DATAOUT feeds IDDRE1 only.
    input  logic [8:0]  rx_dly_tap,
    input  logic        rx_dly_load
);

    logic gtx_clk_u;
    logic gtx_clk90_u;
    logic gtx_clk;
    logic gtx_clk90;
    logic mmcm_fb;
    logic mmcm_fb_buf;
    logic mmcm_locked_i;
    logic rxc_mmcm_locked;
    logic gtx_rst;
    logic sys_clk_buf;

    BUFG u_bufg_sys (.I(sys_clk_200m), .O(sys_clk_buf));

    // 200 MHz -> 125 MHz (0°) + 125 MHz (90°)
    // VCO = 200 * 5 / 1 = 1000 MHz; CLKOUT = 1000/8 = 125 MHz
    MMCME4_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(5.0),
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(5.000),
        .CLKOUT0_DIVIDE_F(8.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .CLKOUT1_DIVIDE(8),
        .CLKOUT1_DUTY_CYCLE(0.5),
        .CLKOUT1_PHASE(90.0),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.010),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKIN1(sys_clk_buf),
        .CLKFBIN(mmcm_fb_buf),
        .RST(~sys_rst_n),
        .PWRDWN(1'b0),
        .CLKFBOUT(mmcm_fb),
        .CLKFBOUTB(),
        .CLKOUT0(gtx_clk_u),
        .CLKOUT0B(),
        .CLKOUT1(gtx_clk90_u),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .LOCKED(mmcm_locked_i)
    );

    BUFG u_bufg_fb  (.I(mmcm_fb),     .O(mmcm_fb_buf));
    BUFG u_bufg_gtx (.I(gtx_clk_u),   .O(gtx_clk));
    BUFG u_bufg_90  (.I(gtx_clk90_u), .O(gtx_clk90));

    assign mmcm_locked = mmcm_locked_i & rxc_mmcm_locked;
    assign logic_clk   = gtx_clk;

    // Active-high reset for MAC (gtx / logic domain)
    logic [3:0] rst_sync;
    always_ff @(posedge gtx_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rst_sync <= 4'hF;
        end else if (!mmcm_locked_i) begin
            rst_sync <= 4'hF;
        end else begin
            rst_sync <= {rst_sync[2:0], 1'b0};
        end
    end
    assign gtx_rst     = rst_sync[3];
    assign logic_rst_n = ~gtx_rst;

    // IDELAYCTRL + 5× IDELAYE3 on RX data/ctl. Matches factory TEMAC path
    // (IBUF → IDELAYE3 → IDDRE1). rgmii_rxc is not delayed.
    logic [7:0] idly_rst_cnt;
    logic       idly_rst;
    always_ff @(posedge sys_clk_buf or negedge sys_rst_n) begin
        if (!sys_rst_n)
            idly_rst_cnt <= 8'd0;
        else if (idly_rst_cnt != 8'hFF)
            idly_rst_cnt <= idly_rst_cnt + 1'b1;
    end
    assign idly_rst = (idly_rst_cnt < 8'd32);

    (* IODELAY_GROUP = "netsec_rgmii_idly" *)
    IDELAYCTRL #(
        .SIM_DEVICE("ULTRASCALE")
    ) u_idelayctrl (
        .REFCLK(sys_clk_buf),
        .RST(idly_rst),
        .RDY()
    );

    logic [2:0] load_sync;
    always_ff @(posedge gtx_clk or posedge gtx_rst) begin
        if (gtx_rst)
            load_sync <= 3'b000;
        else
            load_sync <= {load_sync[1:0], rx_dly_load};
    end
    wire rx_dly_load_gtx = load_sync[1] & ~load_sync[2];

    logic [8:0] tap_sync0, tap_sync1;
    always_ff @(posedge gtx_clk) begin
        tap_sync0 <= rx_dly_tap;
        tap_sync1 <= tap_sync0;
    end

    logic [4:0] rx_raw, rx_dly;
    assign rx_raw = {rgmii_rx_ctl, rgmii_rd};

    genvar gi;
    generate
        for (gi = 0; gi < 5; gi = gi + 1) begin : g_rx_idly
            (* IODELAY_GROUP = "netsec_rgmii_idly" *)
            IDELAYE3 #(
                .CASCADE("NONE"),
                .DELAY_SRC("IDATAIN"),
                .DELAY_TYPE("VAR_LOAD"),
                .DELAY_FORMAT("COUNT"),
                .DELAY_VALUE(480),  // board winner: 67.5° RXC + tap 480 (window 440–488)
                .REFCLK_FREQUENCY(200.0),
                .UPDATE_MODE("ASYNC"),
                .SIM_DEVICE("ULTRASCALE_PLUS")
            ) u_idly (
                .IDATAIN(rx_raw[gi]),
                .DATAIN(1'b0),
                .DATAOUT(rx_dly[gi]),
                .CLK(gtx_clk),
                .LOAD(rx_dly_load_gtx),
                .CNTVALUEIN(tap_sync1),
                .CE(1'b0),
                .INC(1'b0),
                .EN_VTC(1'b0),
                .RST(gtx_rst),
                .CNTVALUEOUT(),
                .CASC_IN(1'b0),
                .CASC_RETURN(1'b0),
                .CASC_OUT()
            );
        end
    endgenerate

    wire [3:0] rgmii_rd_dly  = rx_dly[3:0];
    wire       rgmii_ctl_dly = rx_dly[4];

    // 67.5° of 8 ns = 1.5 ns (MMCM step is 5.625°). Single IDELAY is
    // ~0–1.25 ns and 90° starts at 2.0 ns; this covers the 1.25–2.0 ns gap.
    logic rxc_in_buf, rxc_fb, rxc_fb_buf, rxc60_u, rxc60;
    BUFG u_bufg_rxc_in (.I(rgmii_rxc), .O(rxc_in_buf));
    MMCME4_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(8.0),
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(8.000),
        .CLKOUT0_DIVIDE_F(8.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .CLKOUT1_DIVIDE(8),
        .CLKOUT1_DUTY_CYCLE(0.5),
        .CLKOUT1_PHASE(67.5),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.010),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm_rxc (
        .CLKIN1(rxc_in_buf),
        .CLKFBIN(rxc_fb_buf),
        .RST(~sys_rst_n),
        .PWRDWN(1'b0),
        .CLKFBOUT(rxc_fb),
        .CLKFBOUTB(),
        .CLKOUT0(),
        .CLKOUT0B(),
        .CLKOUT1(rxc60_u),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .LOCKED(rxc_mmcm_locked)
    );
    BUFG u_bufg_rxc_fb  (.I(rxc_fb),   .O(rxc_fb_buf));
    BUFG u_bufg_rxc60   (.I(rxc60_u),  .O(rxc60));

    eth_mac_1g_rgmii_fifo #(
        .TARGET("XILINX"),
        .IODDR_STYLE("IODDR"),
        .CLOCK_INPUT_STYLE("BUFG"),
        .USE_CLK90(USE_CLK90),
        .ENABLE_PADDING(1),
        .MIN_FRAME_LENGTH(64),
        .TX_FIFO_DEPTH(2048),
        .TX_FRAME_FIFO(1),
        .RX_FIFO_DEPTH(2048),
        .RX_FRAME_FIFO(1)
    ) u_mac (
        .gtx_clk(gtx_clk),
        .gtx_clk90(gtx_clk90),
        .gtx_rst(gtx_rst),
        .logic_clk(gtx_clk),
        .logic_rst(gtx_rst),

        .tx_axis_tdata(tx_axis_tdata),
        .tx_axis_tkeep(1'b1),
        .tx_axis_tvalid(tx_axis_tvalid),
        .tx_axis_tready(tx_axis_tready),
        .tx_axis_tlast(tx_axis_tlast),
        .tx_axis_tuser(tx_axis_tuser),

        .rx_axis_tdata(rx_axis_tdata),
        .rx_axis_tkeep(),
        .rx_axis_tvalid(rx_axis_tvalid),
        .rx_axis_tready(rx_axis_tready),
        .rx_axis_tlast(rx_axis_tlast),
        .rx_axis_tuser(rx_axis_tuser),

        .rgmii_rx_clk(rxc60),
        .rgmii_rxd(rgmii_rd_dly),
        .rgmii_rx_ctl(rgmii_ctl_dly),
        .rgmii_tx_clk(rgmii_txc),
        .rgmii_txd(rgmii_td),
        .rgmii_tx_ctl(rgmii_tx_ctl),

        .tx_error_underflow(),
        .tx_fifo_overflow(),
        .tx_fifo_bad_frame(),
        .tx_fifo_good_frame(tx_fifo_good_frame),
        .rx_error_bad_frame(rx_error_bad_frame),
        .rx_error_bad_fcs(rx_error_bad_fcs),
        .rx_fifo_overflow(),
        .rx_fifo_bad_frame(),
        .rx_fifo_good_frame(rx_fifo_good_frame),
        .speed(speed),

        .cfg_ifg(8'd12),
        .cfg_tx_enable(1'b1),
        .cfg_rx_enable(1'b1)
    );

endmodule
