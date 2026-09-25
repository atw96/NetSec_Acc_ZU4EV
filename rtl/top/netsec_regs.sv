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
    output logic         sfp10g_tx_enable,
    input  logic         sfp10g_tx_done,
    input  logic         sfp10g_rx_done,
    input  logic         sfp10g_lock0,
    input  logic         sfp10g_lock1,
    input  logic         sfp10g_rxst0,
    input  logic         sfp10g_rxst1,
    input  logic         sfp10g_hber0,
    input  logic         sfp10g_hber1,
    input  logic         pulse_sfp10g_tx0,
    input  logic         pulse_sfp10g_rx0,
    input  logic         pulse_sfp10g_bad0,
    input  logic         pulse_sfp10g_tx1,
    input  logic         pulse_sfp10g_rx1,
    input  logic         pulse_sfp10g_bad1,
    output logic [1:0]   ns10g_mode,
    output logic [1:0]   ns10g_dp_en,
    output logic         ns10g_aes0_en,
    output logic         ns10g_aes1_en,
    output logic         ns10g_inj,
    input  logic [1:0]   ns10g_last0,
    input  logic [1:0]   ns10g_last1,
    input  logic         pulse_ns10g_rx0,
    input  logic         pulse_ns10g_tx0,
    input  logic         pulse_ns10g_fwd0,
    input  logic         pulse_ns10g_drop0,
    input  logic         pulse_ns10g_mir0,
    input  logic         pulse_ns10g_dpi0,
    input  logic         pulse_ns10g_rx1,
    input  logic         pulse_ns10g_tx1,
    input  logic         pulse_ns10g_fwd1,
    input  logic         pulse_ns10g_drop1,
    input  logic         pulse_ns10g_mir1,
    input  logic         pulse_ns10g_dpi1,
    input  logic         pulse_ns10g_badrx0,
    input  logic         pulse_ns10g_badrx1,
    input  logic         pulse_ns10g_ovf0,
    input  logic         pulse_ns10g_ovf1,
    input  logic         pulse_ns10g_csum0,
    input  logic         pulse_ns10g_csum1,
    input  logic         ns10g_aes0_done,
    input  logic         ns10g_aes1_done,
    input  logic [127:0] ns10g_aes0_ct,
    input  logic [127:0] ns10g_aes1_ct,
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
    // 0x100 NS10G_CTRL [1:0] mode 0=BIST 1=INLINE 2=LOOP 3=DISABLE
    //                  [3:2] dp_en1/0  [6] inj (W1C，片上 GET 注帧，L5c 无仪表)
    //                  [9:8] aes_dp1/0
    // 0x104 NS10G_ST   [1:0]/[3:2] last_action  [8]/[9] aes done  [16]/[17] csum sticky
    // 0x108–0x11C port0 RX/TX/FWD/DROP/MIR/DPI
    // 0x120–0x134 port1 same
    // 0x140/144 BADRX  0x148/14C OVF  0x150/154 CSUM
    // 0x158–0x16C AES0 CT  0x170–0x17C AES1 CT
    // 0xDC SFP10G_CTRL [0] tx_enable (default 1; separate from 0x00 so L0–L3 writes stay intact)
    // 0xC0 SFP10G_ST   same bits as standalone 0x04
    // 0xC4/C8/CC       CNT_TX0 / RX0 / BAD0
    // 0xD0/D4/D8       CNT_TX1 / RX1 / BAD1
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
    // 0x60 SFP_STATUS  [15:0] GT/PCS or 10G lock/LOS vector

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
    logic [31:0] reg_sfp10g_ctrl;
    logic [31:0] cnt_sfp10g_tx0, cnt_sfp10g_rx0, cnt_sfp10g_bad0;
    logic [31:0] cnt_sfp10g_tx1, cnt_sfp10g_rx1, cnt_sfp10g_bad1;
    logic [31:0] reg_ns10g_ctrl;
    logic [31:0] cnt_n0_rx, cnt_n0_tx, cnt_n0_fwd, cnt_n0_drop, cnt_n0_mir, cnt_n0_dpi;
    logic [31:0] cnt_n1_rx, cnt_n1_tx, cnt_n1_fwd, cnt_n1_drop, cnt_n1_mir, cnt_n1_dpi;
    logic [31:0] cnt_n0_badrx, cnt_n1_badrx, cnt_n0_ovf, cnt_n1_ovf, cnt_n0_csum, cnt_n1_csum;
    logic        ns10g_aes0_sticky, ns10g_aes1_sticky, ns10g_csum0_sticky, ns10g_csum1_sticky;

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
    assign sfp10g_tx_enable = reg_sfp10g_ctrl[0];
    assign ns10g_mode    = reg_ns10g_ctrl[1:0];
    assign ns10g_dp_en   = reg_ns10g_ctrl[3:2];
    assign ns10g_aes0_en = reg_ns10g_ctrl[8];
    assign ns10g_aes1_en = reg_ns10g_ctrl[9];
    assign ns10g_inj     = reg_ns10g_ctrl[6];

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
            reg_sfp10g_ctrl <= 32'h1;
            reg_ns10g_ctrl  <= 32'hC; // BIST, both dp_en=1
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
            if (reg_ns10g_ctrl[6]) reg_ns10g_ctrl[6] <= 1'b0;
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
                unique case (awaddr_r[8:0])
                    9'h000: reg_ctrl       <= s_axi_wdata;
                    9'h008: reg_loopback   <= s_axi_wdata;
                    9'h030: key_w0         <= s_axi_wdata;
                    9'h034: key_w1         <= s_axi_wdata;
                    9'h038: key_w2         <= s_axi_wdata;
                    9'h03C: key_w3         <= s_axi_wdata;
                    9'h070: pt_w0          <= s_axi_wdata;
                    9'h074: pt_w1          <= s_axi_wdata;
                    9'h078: pt_w2          <= s_axi_wdata;
                    9'h07C: pt_w3          <= s_axi_wdata;
                    9'h090: begin
                        csum_data_r <= s_axi_wdata[15:0];
                        csum_last_r <= s_axi_wdata[31];
                        csum_dv_r   <= 1'b1;
                    end
                    9'h098: mx_base        <= s_axi_wdata;
                    9'h09C: mx_exp         <= s_axi_wdata;
                    9'h0A0: mx_mod         <= s_axi_wdata;
                    9'h040: pat0           <= s_axi_wdata;
                    9'h044: pat1           <= s_axi_wdata;
                    9'h048: pat2           <= s_axi_wdata;
                    9'h04C: pat3           <= s_axi_wdata;
                    9'h050: begin
                        reg_mdio_ctrl    <= s_axi_wdata;
                        if (s_axi_wdata[17])
                            mdio_done_sticky <= 1'b0;
                    end
                    9'h054: reg_mdio_wdata <= s_axi_wdata;
                    9'h05C: reg_rgmii_dly  <= s_axi_wdata;
                    9'h0DC: reg_sfp10g_ctrl <= s_axi_wdata;
                    9'h100: reg_ns10g_ctrl  <= s_axi_wdata;
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
            cnt_sfp10g_tx0 <= '0; cnt_sfp10g_rx0 <= '0; cnt_sfp10g_bad0 <= '0;
            cnt_sfp10g_tx1 <= '0; cnt_sfp10g_rx1 <= '0; cnt_sfp10g_bad1 <= '0;
            cnt_n0_rx <= '0; cnt_n0_tx <= '0; cnt_n0_fwd <= '0;
            cnt_n0_drop <= '0; cnt_n0_mir <= '0; cnt_n0_dpi <= '0;
            cnt_n1_rx <= '0; cnt_n1_tx <= '0; cnt_n1_fwd <= '0;
            cnt_n1_drop <= '0; cnt_n1_mir <= '0; cnt_n1_dpi <= '0;
            cnt_n0_badrx <= '0; cnt_n1_badrx <= '0;
            cnt_n0_ovf <= '0; cnt_n1_ovf <= '0;
            cnt_n0_csum <= '0; cnt_n1_csum <= '0;
            ns10g_aes0_sticky <= 1'b0; ns10g_aes1_sticky <= 1'b0;
            ns10g_csum0_sticky <= 1'b0; ns10g_csum1_sticky <= 1'b0;
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
            if (pulse_sfp10g_tx0)  cnt_sfp10g_tx0  <= cnt_sfp10g_tx0  + 1'b1;
            if (pulse_sfp10g_rx0)  cnt_sfp10g_rx0  <= cnt_sfp10g_rx0  + 1'b1;
            if (pulse_sfp10g_bad0) cnt_sfp10g_bad0 <= cnt_sfp10g_bad0 + 1'b1;
            if (pulse_sfp10g_tx1)  cnt_sfp10g_tx1  <= cnt_sfp10g_tx1  + 1'b1;
            if (pulse_sfp10g_rx1)  cnt_sfp10g_rx1  <= cnt_sfp10g_rx1  + 1'b1;
            if (pulse_sfp10g_bad1) cnt_sfp10g_bad1 <= cnt_sfp10g_bad1 + 1'b1;
            if (pulse_ns10g_rx0)   cnt_n0_rx   <= cnt_n0_rx   + 1'b1;
            if (pulse_ns10g_tx0)   cnt_n0_tx   <= cnt_n0_tx   + 1'b1;
            if (pulse_ns10g_fwd0)  cnt_n0_fwd  <= cnt_n0_fwd  + 1'b1;
            if (pulse_ns10g_drop0) cnt_n0_drop <= cnt_n0_drop + 1'b1;
            if (pulse_ns10g_mir0)  cnt_n0_mir  <= cnt_n0_mir  + 1'b1;
            if (pulse_ns10g_dpi0)  cnt_n0_dpi  <= cnt_n0_dpi  + 1'b1;
            if (pulse_ns10g_rx1)   cnt_n1_rx   <= cnt_n1_rx   + 1'b1;
            if (pulse_ns10g_tx1)   cnt_n1_tx   <= cnt_n1_tx   + 1'b1;
            if (pulse_ns10g_fwd1)  cnt_n1_fwd  <= cnt_n1_fwd  + 1'b1;
            if (pulse_ns10g_drop1) cnt_n1_drop <= cnt_n1_drop + 1'b1;
            if (pulse_ns10g_mir1)  cnt_n1_mir  <= cnt_n1_mir  + 1'b1;
            if (pulse_ns10g_dpi1)  cnt_n1_dpi  <= cnt_n1_dpi  + 1'b1;
            if (pulse_ns10g_badrx0) cnt_n0_badrx <= cnt_n0_badrx + 1'b1;
            if (pulse_ns10g_badrx1) cnt_n1_badrx <= cnt_n1_badrx + 1'b1;
            if (pulse_ns10g_ovf0)   cnt_n0_ovf   <= cnt_n0_ovf   + 1'b1;
            if (pulse_ns10g_ovf1)   cnt_n1_ovf   <= cnt_n1_ovf   + 1'b1;
            if (pulse_ns10g_csum0) begin
                cnt_n0_csum <= cnt_n0_csum + 1'b1;
                ns10g_csum0_sticky <= 1'b1;
            end
            if (pulse_ns10g_csum1) begin
                cnt_n1_csum <= cnt_n1_csum + 1'b1;
                ns10g_csum1_sticky <= 1'b1;
            end
            if (ns10g_aes0_done) ns10g_aes0_sticky <= 1'b1;
            if (ns10g_aes1_done) ns10g_aes1_sticky <= 1'b1;
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

    logic [31:0] sfp10g_status_word;
    assign sfp10g_status_word = {18'd0, sfp10g_hber1, sfp10g_hber0,
                                 sfp10g_rxst1, sfp10g_rxst0,
                                 sfp10g_lock1, sfp10g_lock0, 3'd0,
                                 sfp2_los, sfp1_los, sfp10g_rx_done,
                                 sfp10g_tx_done, 1'b1};

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
                unique case (s_axi_araddr[8:0])
                    9'h000: s_axi_rdata <= reg_ctrl;
                    9'h004: s_axi_rdata <= status_word;
                    9'h008: s_axi_rdata <= reg_loopback;
                    9'h010: s_axi_rdata <= cnt_rx;
                    9'h014: s_axi_rdata <= cnt_tx;
                    9'h018: s_axi_rdata <= cnt_fwd;
                    9'h01C: s_axi_rdata <= cnt_drop;
                    9'h020: s_axi_rdata <= cnt_mirror;
                    9'h024: s_axi_rdata <= cnt_dpi;
                    9'h028: s_axi_rdata <= cnt_mac_rx_good;
                    9'h02C: s_axi_rdata <= cnt_mac_rx_bad_fcs;
                    9'h030: s_axi_rdata <= key_w0;
                    9'h034: s_axi_rdata <= key_w1;
                    9'h038: s_axi_rdata <= key_w2;
                    9'h03C: s_axi_rdata <= key_w3;
                    9'h040: s_axi_rdata <= pat0;
                    9'h044: s_axi_rdata <= pat1;
                    9'h048: s_axi_rdata <= pat2;
                    9'h04C: s_axi_rdata <= pat3;
                    9'h050: s_axi_rdata <= reg_mdio_ctrl;
                    9'h054: s_axi_rdata <= reg_mdio_wdata;
                    9'h058: s_axi_rdata <= {14'd0, mdio_done_sticky, mdio_busy, mdio_rdata};
                    9'h05C: s_axi_rdata <= reg_rgmii_dly;
                    9'h060: s_axi_rdata <= {16'd0, sfp_status};
                    9'h064: s_axi_rdata <= cnt_mac_rx_bad_frame;
                    9'h068: s_axi_rdata <= cnt_mac_tx_good;
                    9'h06C: s_axi_rdata <= cnt_rgmii_rx_act;
                    9'h070: s_axi_rdata <= pt_w0;
                    9'h074: s_axi_rdata <= pt_w1;
                    9'h078: s_axi_rdata <= pt_w2;
                    9'h07C: s_axi_rdata <= pt_w3;
                    9'h080: s_axi_rdata <= aes_ciphertext[31:0];
                    9'h084: s_axi_rdata <= aes_ciphertext[63:32];
                    9'h088: s_axi_rdata <= aes_ciphertext[95:64];
                    9'h08C: s_axi_rdata <= aes_ciphertext[127:96];
                    9'h090: s_axi_rdata <= {csum_last_r, 15'd0, csum_data_r};
                    9'h094: s_axi_rdata <= {16'd0, csum_result_r};
                    9'h098: s_axi_rdata <= mx_base;
                    9'h09C: s_axi_rdata <= mx_exp;
                    9'h0A0: s_axi_rdata <= mx_mod;
                    9'h0A4: s_axi_rdata <= modexp_result;
                    9'h0B0: s_axi_rdata <= aes_dp_ciphertext[31:0];
                    9'h0B4: s_axi_rdata <= aes_dp_ciphertext[63:32];
                    9'h0B8: s_axi_rdata <= aes_dp_ciphertext[95:64];
                    9'h0BC: s_axi_rdata <= aes_dp_ciphertext[127:96];
                    9'h0C0: s_axi_rdata <= sfp10g_status_word;
                    9'h0C4: s_axi_rdata <= cnt_sfp10g_tx0;
                    9'h0C8: s_axi_rdata <= cnt_sfp10g_rx0;
                    9'h0CC: s_axi_rdata <= cnt_sfp10g_bad0;
                    9'h0D0: s_axi_rdata <= cnt_sfp10g_tx1;
                    9'h0D4: s_axi_rdata <= cnt_sfp10g_rx1;
                    9'h0D8: s_axi_rdata <= cnt_sfp10g_bad1;
                    9'h0DC: s_axi_rdata <= reg_sfp10g_ctrl;
                    9'h100: s_axi_rdata <= reg_ns10g_ctrl;
                    9'h104: s_axi_rdata <= {14'd0, ns10g_csum1_sticky, ns10g_csum0_sticky,
                                           6'd0, ns10g_aes1_sticky, ns10g_aes0_sticky,
                                           ns10g_last1, ns10g_last0};
                    9'h108: s_axi_rdata <= cnt_n0_rx;
                    9'h10C: s_axi_rdata <= cnt_n0_tx;
                    9'h110: s_axi_rdata <= cnt_n0_fwd;
                    9'h114: s_axi_rdata <= cnt_n0_drop;
                    9'h118: s_axi_rdata <= cnt_n0_mir;
                    9'h11C: s_axi_rdata <= cnt_n0_dpi;
                    9'h120: s_axi_rdata <= cnt_n1_rx;
                    9'h124: s_axi_rdata <= cnt_n1_tx;
                    9'h128: s_axi_rdata <= cnt_n1_fwd;
                    9'h12C: s_axi_rdata <= cnt_n1_drop;
                    9'h130: s_axi_rdata <= cnt_n1_mir;
                    9'h134: s_axi_rdata <= cnt_n1_dpi;
                    9'h140: s_axi_rdata <= cnt_n0_badrx;
                    9'h144: s_axi_rdata <= cnt_n1_badrx;
                    9'h148: s_axi_rdata <= cnt_n0_ovf;
                    9'h14C: s_axi_rdata <= cnt_n1_ovf;
                    9'h150: s_axi_rdata <= cnt_n0_csum;
                    9'h154: s_axi_rdata <= cnt_n1_csum;
                    9'h158: s_axi_rdata <= ns10g_aes0_ct[31:0];
                    9'h15C: s_axi_rdata <= ns10g_aes0_ct[63:32];
                    9'h160: s_axi_rdata <= ns10g_aes0_ct[95:64];
                    9'h164: s_axi_rdata <= ns10g_aes0_ct[127:96];
                    9'h168: s_axi_rdata <= 32'd0;
                    9'h16C: s_axi_rdata <= 32'd0;
                    9'h170: s_axi_rdata <= ns10g_aes1_ct[31:0];
                    9'h174: s_axi_rdata <= ns10g_aes1_ct[63:32];
                    9'h178: s_axi_rdata <= ns10g_aes1_ct[95:64];
                    9'h17C: s_axi_rdata <= ns10g_aes1_ct[127:96];
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
