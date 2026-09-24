// sfp10g_regs.sv — AXI4-Lite @ 0x8005_0000 for the 10G fiber loopback image
`timescale 1ns / 1ps

module sfp10g_regs (
    input  logic        aclk,
    input  logic        aresetn,

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
    input  logic        s_axi_rready,

    output logic        tx_enable,
    output logic        soft_reset,

    input  logic        por_ok,
    input  logic        gt_tx_done,
    input  logic        gt_rx_done,
    input  logic        sfp1_los,
    input  logic        sfp2_los,
    input  logic        block_lock0,
    input  logic        block_lock1,
    input  logic        rx_status0,
    input  logic        rx_status1,
    input  logic        high_ber0,
    input  logic        high_ber1,

    input  logic        pulse_tx0,
    input  logic        pulse_rx0,
    input  logic        pulse_bad0,
    input  logic        pulse_tx1,
    input  logic        pulse_rx1,
    input  logic        pulse_bad1
);

    logic [31:0] reg_ctrl;
    logic [31:0] cnt_tx0, cnt_rx0, cnt_bad0;
    logic [31:0] cnt_tx1, cnt_rx1, cnt_bad1;

    assign tx_enable  = reg_ctrl[0];
    assign soft_reset = reg_ctrl[1];

    logic aw_hs, w_hs, b_hs;
    logic [31:0] awaddr_r;
    logic        aw_ok, w_ok;

    assign aw_hs = s_axi_awvalid && s_axi_awready;
    assign w_hs  = s_axi_wvalid  && s_axi_wready;
    assign b_hs  = s_axi_bvalid  && s_axi_bready;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            aw_ok         <= 1'b0;
            w_ok          <= 1'b0;
            awaddr_r      <= '0;
            reg_ctrl      <= 32'h1;
        end else begin
            if (reg_ctrl[1])
                reg_ctrl[1] <= 1'b0;

            if (!s_axi_awready && !aw_ok)
                s_axi_awready <= 1'b1;
            else
                s_axi_awready <= 1'b0;

            if (aw_hs) begin
                awaddr_r <= s_axi_awaddr;
                aw_ok    <= 1'b1;
            end

            if (!s_axi_wready && !w_ok)
                s_axi_wready <= 1'b1;
            else
                s_axi_wready <= 1'b0;

            if (w_hs)
                w_ok <= 1'b1;

            if (aw_ok && w_ok && !s_axi_bvalid) begin
                if (awaddr_r[7:0] == 8'h00)
                    reg_ctrl <= s_axi_wdata;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
                aw_ok        <= 1'b0;
                w_ok         <= 1'b0;
            end else if (b_hs) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    logic        ar_hs, r_hs;
    logic [31:0] araddr_r;
    logic        ar_ok;

    assign ar_hs = s_axi_arvalid && s_axi_arready;
    assign r_hs  = s_axi_rvalid  && s_axi_rready;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= '0;
            ar_ok         <= 1'b0;
            araddr_r      <= '0;
        end else begin
            if (!s_axi_arready && !ar_ok)
                s_axi_arready <= 1'b1;
            else
                s_axi_arready <= 1'b0;

            if (ar_hs) begin
                araddr_r <= s_axi_araddr;
                ar_ok    <= 1'b1;
            end

            if (ar_ok && !s_axi_rvalid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;
                unique case (araddr_r[7:0])
                    8'h00: s_axi_rdata <= reg_ctrl;
                    8'h04: s_axi_rdata <= {18'd0, high_ber1, high_ber0,
                                           rx_status1, rx_status0,
                                           block_lock1, block_lock0, 3'd0,
                                           sfp2_los, sfp1_los, gt_rx_done,
                                           gt_tx_done, por_ok};
                    8'h10: s_axi_rdata <= cnt_tx0;
                    8'h14: s_axi_rdata <= cnt_rx0;
                    8'h18: s_axi_rdata <= cnt_bad0;
                    8'h20: s_axi_rdata <= cnt_tx1;
                    8'h24: s_axi_rdata <= cnt_rx1;
                    8'h28: s_axi_rdata <= cnt_bad1;
                    8'h60: s_axi_rdata <= {16'd0, 2'd0, high_ber1, high_ber0,
                                           rx_status1, rx_status0,
                                           block_lock1, block_lock0,
                                           sfp2_los, sfp1_los, 6'd1};
                    default: s_axi_rdata <= 32'hDEAD_10C0;
                endcase
                ar_ok <= 1'b0;
            end else if (r_hs) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn || soft_reset) begin
            cnt_tx0  <= '0;
            cnt_rx0  <= '0;
            cnt_bad0 <= '0;
            cnt_tx1  <= '0;
            cnt_rx1  <= '0;
            cnt_bad1 <= '0;
        end else begin
            if (pulse_tx0)  cnt_tx0  <= cnt_tx0  + 1'b1;
            if (pulse_rx0)  cnt_rx0  <= cnt_rx0  + 1'b1;
            if (pulse_bad0) cnt_bad0 <= cnt_bad0 + 1'b1;
            if (pulse_tx1)  cnt_tx1  <= cnt_tx1  + 1'b1;
            if (pulse_rx1)  cnt_rx1  <= cnt_rx1  + 1'b1;
            if (pulse_bad1) cnt_bad1 <= cnt_bad1 + 1'b1;
        end
    end

endmodule
