// netsec_regs.sv — AXI4-Lite slave @ 0x8005_0000 (64KB window)
`timescale 1ns / 1ps

module netsec_regs (
    input  logic         aclk,
    input  logic         aresetn,

    input  logic [31:0]  s_axi_awaddr,
    input  logic         s_axi_awvalid,
    output logic         s_axi_awready,
    input  logic [31:0]  s_axi_wdata,
    input  logic [3:0]   s_axi_wstrb,
    input  logic         s_axi_wvalid,
    output logic         s_axi_wready,
    output logic [1:0]   s_axi_bresp,
    output logic         s_axi_bvalid,
    input  logic         s_axi_bready,
    input  logic [31:0]  s_axi_araddr,
    input  logic         s_axi_arvalid,
    output logic         s_axi_arready,
    output logic [31:0]  s_axi_rdata,
    output logic [1:0]   s_axi_rresp,
    output logic         s_axi_rvalid,
    input  logic         s_axi_rready,

    output logic         ctrl_enable,
    output logic         soft_reset,
    output logic [2:0]   loopback_mode,
    output logic         pkt_gen_start,
    output logic [127:0] aes_key,
    output logic         aes_start,
    output logic [127:0] aes_plaintext,
    input  logic         aes_done,
    input  logic [127:0] aes_ciphertext,
    output logic         csum_start,
    output logic         csum_data_valid,
    output logic [15:0]  csum_data,
    output logic         csum_last,
    input  logic         csum_valid,
    input  logic [15:0]  csum_result,
    output logic         modexp_start,
    output logic [31:0]  modexp_base,
    output logic [31:0]  modexp_exp,
    output logic [31:0]  modexp_mod,
    input  logic         modexp_done,
    input  logic [31:0]  modexp_result,
    output logic         ctrl_aes_dp_en,
    input  logic         aes_dp_done,
    input  logic [127:0] aes_dp_ciphertext,
    output logic [31:0]  dpi_pat0,
    output logic [31:0]  dpi_pat1,
    output logic [31:0]  dpi_pat2,
    output logic [31:0]  dpi_pat3,

    output logic         mdio_go,
    output logic         mdio_we,
    output logic [4:0]   mdio_phy_addr,
    output logic [4:0]   mdio_reg_addr,
    output logic [15:0]  mdio_wdata,
    input  logic [15:0]  mdio_rdata,
    input  logic         mdio_busy,
    input  logic         mdio_done,

    output logic [8:0]   rgmii_dly_tap,
    output logic         rgmii_dly_load,

    input  logic         datapath_ready,
    input  logic         mmcm_locked,
    input  logic         phy_link,
    input  logic         sfp1_los,
    input  logic         sfp2_los,
    input  logic [15:0]  sfp_status,
    input  logic [1:0]   mac_speed,
    input  logic [1:0]   last_action,

    input  logic         pulse_rx,
    input  logic         pulse_tx,
    input  logic         pulse_forward,
    input  logic         pulse_drop,
    input  logic         pulse_mirror,
    input  logic         pulse_dpi_hit,
    input  logic         pulse_mac_rx_good,
    input  logic         pulse_mac_rx_bad_fcs,
    input  logic         pulse_mac_rx_bad_frame,
    input  logic         pulse_mac_tx_good,
    input  logic         pulse_rgmii_rx_act
);

    // 0x00 CTRL        [0] enable [1] soft_reset [8] pkt_gen_start
    //                  [9] aes_start (W1C) [10] csum_start (W1C) [11] modexp_start (W1C)
    //                  [12] aes_dp_en（电平：FORWARD 帧偏移 42 起 16B 进 AES）
    // 0x04 STATUS      [0] ready [1] mmcm [2] phy_link [3] sfp1_los [4] sfp2_los
    //                  [5] aes_done [6] csum_valid [7] modexp_done [10] aes_dp_done
    //                  [9:8] speed [17:16] last_action
    // 0xB0..0xBC       AES datapath ciphertext (RO)
    // 0x08 LOOPBACK    [2:0] mode
    // 0x10..0x24       datapath counters
    // 0x28 CNT_MAC_RX_GOOD  0x2C CNT_MAC_RX_BAD_FCS
    // 0x64 CNT_MAC_RX_BAD_FRAME  0x68 CNT_MAC_TX_GOOD
    // 0x6C CNT_RGMII_RX_ACT
    // 0x30..0x3C       AES key
    // 0x40..0x4C       DPI patterns
    // 0x70..0x7C       AES plaintext
    // 0x80..0x8C       AES ciphertext (RO)
    // 0x90 CSUM_DATA   [15:0] word  [31] last  (write pulses data_valid)
    // 0x94 CSUM_RESULT [15:0] RFC1071 checksum (RO)
    // 0x98 MODEXP_BASE  0x9C EXP  0xA0 MOD  0xA4 RESULT (RO)
    // 0x50 MDIO_CTRL   [4:0] phy [12:8] reg [16] we [17] go
    // 0x54 MDIO_WDATA  [15:0]
    // 0x58 MDIO_RDATA  [15:0] data [16] busy [17] done_sticky
    // 0x5C RGMII_DLY   [8:0] tap [16] load
    // 0x60 SFP_STATUS  [15:0] GT/PCS status_vector (LOS in stub)

    logic [31:0] reg_ctrl;
    logic [31:0] reg_loopback;
    logic [31:0] cnt_rx, cnt_tx, cnt_fwd, cnt_drop, cnt_mirror, cnt_dpi;
    logic [31:0] cnt_mac_rx_good, cnt_mac_rx_bad_fcs, cnt_mac_rx_bad_frame;
    logic [31:0] cnt_mac_tx_good, cnt_rgmii_rx_act;
    logic [31:0] key_w0, key_w1, key_w2, key_w3;
    logic [31:0] pt_w0, pt_w1, pt_w2, pt_w3;
    logic [31:0] pat0, pat1, pat2, pat3;
    logic        csum_dv_r, csum_last_r;
    logic [15:0] csum_data_r;
    logic        aes_done_sticky, csum_valid_sticky, modexp_done_sticky, aes_dp_done_sticky;
    logic [15:0] csum_result_r;
    logic [31:0] mx_base, mx_exp, mx_mod;
    logic [31:0] reg_mdio_ctrl;
    logic [31:0] reg_mdio_wdata;
    logic [31:0] reg_rgmii_dly;
    logic        mdio_done_sticky;

    assign ctrl_enable    = reg_ctrl[0];
    assign soft_reset     = reg_ctrl[1];
    assign pkt_gen_start  = reg_ctrl[8];
    assign aes_start      = reg_ctrl[9];
    assign csum_start     = reg_ctrl[10];
    assign modexp_start   = reg_ctrl[11];
    assign ctrl_aes_dp_en = reg_ctrl[12];
    assign modexp_base    = mx_base;
    assign modexp_exp     = mx_exp;
    assign modexp_mod     = mx_mod;
    assign loopback_mode  = reg_loopback[2:0];
    assign aes_key        = {key_w3, key_w2, key_w1, key_w0};
    assign aes_plaintext  = {pt_w3, pt_w2, pt_w1, pt_w0};
    assign csum_data_valid = csum_dv_r;
    assign csum_data       = csum_data_r;
    assign csum_last       = csum_last_r;
    assign dpi_pat0 = pat0;
    assign dpi_pat1 = pat1;
    assign dpi_pat2 = pat2;
    assign dpi_pat3 = pat3;

    assign mdio_phy_addr = reg_mdio_ctrl[4:0];
    assign mdio_reg_addr = reg_mdio_ctrl[12:8];
    assign mdio_we       = reg_mdio_ctrl[16];
    assign mdio_go       = reg_mdio_ctrl[17];
    assign mdio_wdata    = reg_mdio_wdata[15:0];
    assign rgmii_dly_tap = reg_rgmii_dly[8:0];
    assign rgmii_dly_load = reg_rgmii_dly[16];

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
            aw_ok <= 1'b0;
            w_ok  <= 1'b0;
            awaddr_r <= '0;
            reg_ctrl <= 32'h1;
            reg_loopback <= 32'h1;
            key_w0 <= '0; key_w1 <= '0; key_w2 <= '0; key_w3 <= '0;
            pt_w0 <= '0; pt_w1 <= '0; pt_w2 <= '0; pt_w3 <= '0;
            csum_dv_r <= 1'b0; csum_last_r <= 1'b0; csum_data_r <= '0;
            mx_base <= '0; mx_exp <= '0; mx_mod <= '0;
            pat0 <= 32'h47455420;
            pat1 <= 32'h636d642e;
            pat2 <= 32'h53454c45;
            pat3 <= 32'h90909090;
            reg_mdio_ctrl  <= 32'h0000_0001; // PHY addr = 1
            reg_mdio_wdata <= '0;
            reg_rgmii_dly  <= '0;
            mdio_done_sticky <= 1'b0;
        end else begin
            if (reg_ctrl[1])      reg_ctrl[1]      <= 1'b0;
            if (reg_ctrl[8])      reg_ctrl[8]      <= 1'b0;
            if (reg_ctrl[9])      reg_ctrl[9]      <= 1'b0;
            if (reg_ctrl[10])     reg_ctrl[10]     <= 1'b0;
            if (reg_ctrl[11])     reg_ctrl[11]     <= 1'b0;
            if (csum_dv_r) begin
                csum_dv_r   <= 1'b0;
                csum_last_r <= 1'b0;
            end
            if (reg_mdio_ctrl[17]) reg_mdio_ctrl[17] <= 1'b0;
            if (reg_rgmii_dly[16]) reg_rgmii_dly[16] <= 1'b0;
            if (mdio_done)        mdio_done_sticky <= 1'b1;

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
                unique case (awaddr_r[7:0])
                    8'h00: reg_ctrl       <= s_axi_wdata;
                    8'h08: reg_loopback   <= s_axi_wdata;
                    8'h30: key_w0         <= s_axi_wdata;
                    8'h34: key_w1         <= s_axi_wdata;
                    8'h38: key_w2         <= s_axi_wdata;
                    8'h3C: key_w3         <= s_axi_wdata;
                    8'h70: pt_w0          <= s_axi_wdata;
                    8'h74: pt_w1          <= s_axi_wdata;
                    8'h78: pt_w2          <= s_axi_wdata;
                    8'h7C: pt_w3          <= s_axi_wdata;
                    8'h90: begin
                        csum_data_r <= s_axi_wdata[15:0];
                        csum_last_r <= s_axi_wdata[31];
                        csum_dv_r   <= 1'b1;
                    end
                    8'h98: mx_base        <= s_axi_wdata;
                    8'h9C: mx_exp         <= s_axi_wdata;
                    8'hA0: mx_mod         <= s_axi_wdata;
                    8'h40: pat0           <= s_axi_wdata;
                    8'h44: pat1           <= s_axi_wdata;
                    8'h48: pat2           <= s_axi_wdata;
                    8'h4C: pat3           <= s_axi_wdata;
                    8'h50: begin
                        reg_mdio_ctrl    <= s_axi_wdata;
                        if (s_axi_wdata[17])
                            mdio_done_sticky <= 1'b0;
                    end
                    8'h54: reg_mdio_wdata <= s_axi_wdata;
                    8'h5C: reg_rgmii_dly  <= s_axi_wdata;
                    default: ;
                endcase
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
                aw_ok <= 1'b0;
                w_ok  <= 1'b0;
            end else if (b_hs) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn || soft_reset) begin
            cnt_rx <= '0; cnt_tx <= '0; cnt_fwd <= '0;
            cnt_drop <= '0; cnt_mirror <= '0; cnt_dpi <= '0;
            cnt_mac_rx_good <= '0; cnt_mac_rx_bad_fcs <= '0;
            cnt_mac_rx_bad_frame <= '0; cnt_mac_tx_good <= '0;
            cnt_rgmii_rx_act <= '0;
            aes_done_sticky <= 1'b0;
            csum_valid_sticky <= 1'b0;
            modexp_done_sticky <= 1'b0;
            aes_dp_done_sticky <= 1'b0;
            csum_result_r <= '0;
        end else begin
            if (pulse_rx)      cnt_rx      <= cnt_rx + 1'b1;
            if (pulse_tx)      cnt_tx      <= cnt_tx + 1'b1;
            if (pulse_forward) cnt_fwd     <= cnt_fwd + 1'b1;
            if (pulse_drop)    cnt_drop    <= cnt_drop + 1'b1;
            if (pulse_mirror)  cnt_mirror  <= cnt_mirror + 1'b1;
            if (pulse_dpi_hit) cnt_dpi     <= cnt_dpi + 1'b1;
            if (pulse_mac_rx_good)      cnt_mac_rx_good      <= cnt_mac_rx_good + 1'b1;
            if (pulse_mac_rx_bad_fcs)   cnt_mac_rx_bad_fcs   <= cnt_mac_rx_bad_fcs + 1'b1;
            if (pulse_mac_rx_bad_frame) cnt_mac_rx_bad_frame <= cnt_mac_rx_bad_frame + 1'b1;
            if (pulse_mac_tx_good)      cnt_mac_tx_good      <= cnt_mac_tx_good + 1'b1;
            if (pulse_rgmii_rx_act)     cnt_rgmii_rx_act     <= cnt_rgmii_rx_act + 1'b1;
            if (aes_start)
                aes_done_sticky <= 1'b0;
            else if (aes_done)
                aes_done_sticky <= 1'b1;
            if (csum_start)
                csum_valid_sticky <= 1'b0;
            else if (csum_valid) begin
                csum_valid_sticky <= 1'b1;
                csum_result_r     <= csum_result;
            end
            if (modexp_start)
                modexp_done_sticky <= 1'b0;
            else if (modexp_done)
                modexp_done_sticky <= 1'b1;
            if (aes_dp_done)
                aes_dp_done_sticky <= 1'b1;
        end
    end

    logic [31:0] status_word;
    assign status_word = {
        14'd0, last_action, 5'd0, aes_dp_done_sticky, mac_speed,
        modexp_done_sticky, csum_valid_sticky, aes_done_sticky,
        sfp2_los, sfp1_los, phy_link, mmcm_locked, datapath_ready
    };

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= '0;
            s_axi_rresp   <= 2'b00;
        end else begin
            if (!s_axi_arready && !s_axi_rvalid)
                s_axi_arready <= 1'b1;
            else
                s_axi_arready <= 1'b0;

            if (s_axi_arvalid && s_axi_arready) begin
                unique case (s_axi_araddr[7:0])
                    8'h00: s_axi_rdata <= reg_ctrl;
                    8'h04: s_axi_rdata <= status_word;
                    8'h08: s_axi_rdata <= reg_loopback;
                    8'h10: s_axi_rdata <= cnt_rx;
                    8'h14: s_axi_rdata <= cnt_tx;
                    8'h18: s_axi_rdata <= cnt_fwd;
                    8'h1C: s_axi_rdata <= cnt_drop;
                    8'h20: s_axi_rdata <= cnt_mirror;
                    8'h24: s_axi_rdata <= cnt_dpi;
                    8'h28: s_axi_rdata <= cnt_mac_rx_good;
                    8'h2C: s_axi_rdata <= cnt_mac_rx_bad_fcs;
                    8'h30: s_axi_rdata <= key_w0;
                    8'h34: s_axi_rdata <= key_w1;
                    8'h38: s_axi_rdata <= key_w2;
                    8'h3C: s_axi_rdata <= key_w3;
                    8'h40: s_axi_rdata <= pat0;
                    8'h44: s_axi_rdata <= pat1;
                    8'h48: s_axi_rdata <= pat2;
                    8'h4C: s_axi_rdata <= pat3;
                    8'h50: s_axi_rdata <= reg_mdio_ctrl;
                    8'h54: s_axi_rdata <= reg_mdio_wdata;
                    8'h58: s_axi_rdata <= {14'd0, mdio_done_sticky, mdio_busy, mdio_rdata};
                    8'h5C: s_axi_rdata <= reg_rgmii_dly;
                    8'h60: s_axi_rdata <= {16'd0, sfp_status};
                    8'h64: s_axi_rdata <= cnt_mac_rx_bad_frame;
                    8'h68: s_axi_rdata <= cnt_mac_tx_good;
                    8'h6C: s_axi_rdata <= cnt_rgmii_rx_act;
                    8'h70: s_axi_rdata <= pt_w0;
                    8'h74: s_axi_rdata <= pt_w1;
                    8'h78: s_axi_rdata <= pt_w2;
                    8'h7C: s_axi_rdata <= pt_w3;
                    8'h80: s_axi_rdata <= aes_ciphertext[31:0];
                    8'h84: s_axi_rdata <= aes_ciphertext[63:32];
                    8'h88: s_axi_rdata <= aes_ciphertext[95:64];
                    8'h8C: s_axi_rdata <= aes_ciphertext[127:96];
                    8'h90: s_axi_rdata <= {csum_last_r, 15'd0, csum_data_r};
                    8'h94: s_axi_rdata <= {16'd0, csum_result_r};
                    8'h98: s_axi_rdata <= mx_base;
                    8'h9C: s_axi_rdata <= mx_exp;
                    8'hA0: s_axi_rdata <= mx_mod;
                    8'hA4: s_axi_rdata <= modexp_result;
                    8'hB0: s_axi_rdata <= aes_dp_ciphertext[31:0];
                    8'hB4: s_axi_rdata <= aes_dp_ciphertext[63:32];
                    8'hB8: s_axi_rdata <= aes_dp_ciphertext[95:64];
                    8'hBC: s_axi_rdata <= aes_dp_ciphertext[127:96];
                    default: s_axi_rdata <= 32'hDEAD_BEEF;
                endcase
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
