// TB-5: 0x100 block vs 0x00-0xDC no crosstalk
`timescale 1ns / 1ps

module tb_ns10g_regs;
    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    logic [31:0] awaddr, wdata, araddr, rdata;
    logic        awvalid, awready, wvalid, wready, bvalid, bready;
    logic        arvalid, arready, rvalid, rready;
    logic [3:0]  wstrb;
    logic [1:0]  bresp, rresp;
    logic [1:0]  mode, dpen;

    assign wstrb = 4'hF;
    assign bready = 1;
    assign rready = 1;

    netsec_regs u_r (
        .aclk(clk), .aresetn(rst_n),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .ctrl_enable(), .soft_reset(), .loopback_mode(), .pkt_gen_start(),
        .aes_key(), .aes_start(), .aes_plaintext(), .aes_done(1'b0), .aes_ciphertext(128'd0),
        .csum_start(), .csum_data_valid(), .csum_data(), .csum_last(),
        .csum_valid(1'b0), .csum_result(16'd0),
        .modexp_start(), .modexp_base(), .modexp_exp(), .modexp_mod(),
        .modexp_done(1'b0), .modexp_result(32'd0),
        .ctrl_aes_dp_en(), .aes_dp_done(1'b0), .aes_dp_ciphertext(128'd0),
        .dpi_pat0(), .dpi_pat1(), .dpi_pat2(), .dpi_pat3(),
        .mdio_go(), .mdio_we(), .mdio_phy_addr(), .mdio_reg_addr(), .mdio_wdata(),
        .mdio_rdata(16'd0), .mdio_busy(1'b0), .mdio_done(1'b0),
        .rgmii_dly_tap(), .rgmii_dly_load(),
        .datapath_ready(1'b1), .mmcm_locked(1'b1), .phy_link(1'b1),
        .sfp1_los(1'b0), .sfp2_los(1'b0), .sfp_status(16'd1),
        .sfp10g_tx_enable(), .sfp10g_tx_done(1'b1), .sfp10g_rx_done(1'b1),
        .sfp10g_lock0(1'b1), .sfp10g_lock1(1'b1),
        .sfp10g_rxst0(1'b1), .sfp10g_rxst1(1'b1),
        .sfp10g_hber0(1'b0), .sfp10g_hber1(1'b0),
        .pulse_sfp10g_tx0(1'b0), .pulse_sfp10g_rx0(1'b0), .pulse_sfp10g_bad0(1'b0),
        .pulse_sfp10g_tx1(1'b0), .pulse_sfp10g_rx1(1'b0), .pulse_sfp10g_bad1(1'b0),
        .ns10g_mode(mode), .ns10g_dp_en(dpen), .ns10g_aes0_en(), .ns10g_aes1_en(),
        .ns10g_inj(),
        .ns10g_last0(2'b11), .ns10g_last1(2'b01),
        .pulse_ns10g_rx0(1'b0), .pulse_ns10g_tx0(1'b0), .pulse_ns10g_fwd0(1'b0),
        .pulse_ns10g_drop0(1'b0), .pulse_ns10g_mir0(1'b0), .pulse_ns10g_dpi0(1'b0),
        .pulse_ns10g_rx1(1'b0), .pulse_ns10g_tx1(1'b0), .pulse_ns10g_fwd1(1'b0),
        .pulse_ns10g_drop1(1'b0), .pulse_ns10g_mir1(1'b0), .pulse_ns10g_dpi1(1'b0),
        .pulse_ns10g_badrx0(1'b0), .pulse_ns10g_badrx1(1'b0),
        .pulse_ns10g_ovf0(1'b0), .pulse_ns10g_ovf1(1'b0),
        .pulse_ns10g_csum0(1'b0), .pulse_ns10g_csum1(1'b0),
        .ns10g_aes0_done(1'b0), .ns10g_aes1_done(1'b0),
        .ns10g_aes0_ct(128'hA), .ns10g_aes1_ct(128'hB),
        .mac_speed(2'b10), .last_action(2'b00),
        .pulse_rx(1'b0), .pulse_tx(1'b0), .pulse_forward(1'b0),
        .pulse_drop(1'b0), .pulse_mirror(1'b0), .pulse_dpi_hit(1'b0),
        .pulse_mac_rx_good(1'b0), .pulse_mac_rx_bad_fcs(1'b0),
        .pulse_mac_rx_bad_frame(1'b0), .pulse_mac_tx_good(1'b0),
        .pulse_rgmii_rx_act(1'b0)
    );

    task wr;
        input [31:0] a, d;
        integer t;
        begin
            awaddr = a; wdata = d;
            awvalid = 1; wvalid = 1;
            t = 0;
            while (!(awready && wready) && t < 20) begin
                @(posedge clk);
                t = t + 1;
            end
            @(posedge clk);
            awvalid = 0; wvalid = 0;
            t = 0;
            while (!bvalid && t < 20) begin
                @(posedge clk);
                t = t + 1;
            end
            @(posedge clk);
        end
    endtask

    task rd;
        input  [31:0] a;
        output [31:0] d;
        integer t;
        begin
            araddr = a; arvalid = 1;
            t = 0;
            while (!arready && t < 20) begin
                @(posedge clk);
                t = t + 1;
            end
            @(posedge clk);
            arvalid = 0;
            t = 0;
            while (!rvalid && t < 20) begin
                @(posedge clk);
                t = t + 1;
            end
            d = rdata;
            @(posedge clk);
        end
    endtask

    integer errors;
    logic [31:0] v, v0;
    initial begin
        errors = 0;
        awvalid = 0; wvalid = 0; arvalid = 0; awaddr = 0; wdata = 0; araddr = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (8) @(posedge clk);
        rd(32'h00, v0);
        if (v0[0] != 1'b1) errors++;
        rd(32'h100, v);
        if (v[3:0] != 4'hC) errors++;
        rd(32'hC0, v);
        if (v == 32'hDEAD_BEEF) errors++;
        rd(32'h104, v);
        if (v[1:0] != 2'b11) errors++;
        rd(32'h170, v);
        if (v != 32'hB) errors++;
        wr(32'h100, 32'h5);
        rd(32'h100, v);
        $display("NS10G_CTRL after wr %08x mode=%0d", v, mode);
        if (errors == 0)
            $display("PASS: tb_ns10g_regs");
        else
            $display("FAIL: tb_ns10g_regs errors=%0d", errors);
        $finish;
    end
endmodule
