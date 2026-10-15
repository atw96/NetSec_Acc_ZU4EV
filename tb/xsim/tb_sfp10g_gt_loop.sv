// GT serial loop: sfp10g_wrap TX pins tied to RX pins.
// Refclk matches the wizard example (125.7621951 MHz). Pass requires
// block lock and FCS-good frames (bad stays 0 while RX tracks TX).
`timescale 1ps / 1ps

module tb_sfp10g_gt_loop;
    reg freerun = 1'b0;
    reg axi = 1'b0;
    reg refclk_p = 1'b0;
    always #10000 freerun = ~freerun;
    always #5000  axi = ~axi;
    always #3976  refclk_p = ~refclk_p;
    wire refclk_n = ~refclk_p;

    reg rst_n = 1'b0;
    wire [1:0] txn, txp;
    wire lock0, lock1, rxst0, rxst1, hber0, hber1;
    wire tx_done, rx_done;
    wire p_tx0, p_rx0, p_bad0, p_tx1, p_rx1, p_bad1;
    integer tx0 = 0, rx0 = 0, bad0 = 0, tx1 = 0, rx1 = 0, bad1 = 0;

    sfp10g_wrap dut (
        .freerun_clk(freerun),
        .axi_clk(axi),
        .rst_n(rst_n),
        .tx_enable(1'b1),
        .gap_cycles(16'd32),
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
        .mgtrefclk_p(refclk_p),
        .mgtrefclk_n(refclk_n),
        .gthrxn_in(txn),
        .gthrxp_in(txp),
        .gthtxn_out(txn),
        .gthtxp_out(txp),
        .sfp_tx_dis(),
        .sfp1_los(1'b0),
        .sfp2_los(1'b0),
        .gt_tx_done(tx_done),
        .gt_rx_done(rx_done),
        .block_lock0(lock0),
        .block_lock1(lock1),
        .rx_status0(rxst0),
        .rx_status1(rxst1),
        .high_ber0(hber0),
        .high_ber1(hber1),
        .pulse_tx0_axi(p_tx0),
        .pulse_rx0_axi(p_rx0),
        .pulse_bad0_axi(p_bad0),
        .pulse_tx1_axi(p_tx1),
        .pulse_rx1_axi(p_rx1),
        .pulse_bad1_axi(p_bad1)
    );

    always @(posedge axi) begin
        if (p_tx0)  tx0  <= tx0 + 1;
        if (p_rx0)  rx0  <= rx0 + 1;
        if (p_bad0) bad0 <= bad0 + 1;
        if (p_tx1)  tx1  <= tx1 + 1;
        if (p_rx1)  rx1  <= rx1 + 1;
        if (p_bad1) bad1 <= bad1 + 1;
    end

    integer k;
    initial begin
        rst_n = 1'b0;
        repeat (40) @(posedge freerun);
        rst_n = 1'b1;
        for (k = 0; k < 20; k = k + 1) begin
            repeat (5000) @(posedge freerun);
            $display("GTLOOP t=%0t txdone=%0b rxdone=%0b lock=%0b%0b st=%0b%0b hber=%0b%0b TX0=%0d RX0=%0d BAD0=%0d TX1=%0d RX1=%0d BAD1=%0d",
                     $time, tx_done, rx_done, lock1, lock0, rxst1, rxst0, hber1, hber0,
                     tx0, rx0, bad0, tx1, rx1, bad1);
        end
        if (lock0 && lock1 && bad0 == 0 && bad1 == 0 && rx0 > 4 && rx1 > 4)
            $display("PASS: tb_sfp10g_gt_loop");
        else
            $display("FAIL: tb_sfp10g_gt_loop");
        $finish;
    end
endmodule
