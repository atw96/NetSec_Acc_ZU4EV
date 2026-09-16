// L0: pkt_gen -> datapath (FWFT frame FIFO). Expect 2 RX, 1 FWD, 1 DROP, 1 DPI.
`timescale 1ns / 1ps

module tb_l0_loopback;
    logic clk = 0, rst_n = 0, start = 0;
    always #4 clk = ~clk;

    logic [7:0] gen_tdata, dp_m_tdata;
    logic       gen_tvalid, gen_tready, gen_tlast;
    logic       dp_m_tvalid, dp_m_tready, dp_m_tlast;
    logic [1:0] last_action;
    logic       pulse_rx, pulse_tx, pulse_fwd, pulse_drop, pulse_mir, pulse_dpi;

    integer cnt_rx, cnt_tx, cnt_fwd, cnt_drop, cnt_mir, cnt_dpi;

    pkt_gen_bram u_gen (
        .clk(clk), .rst_n(rst_n), .start(start),
        .m_tdata(gen_tdata), .m_tvalid(gen_tvalid), .m_tready(gen_tready),
        .m_tlast(gen_tlast), .busy()
    );

    netsec_datapath u_dp (
        .clk(clk), .rst_n(rst_n), .enable(1'b1),
        .s_tdata(gen_tdata), .s_tvalid(gen_tvalid), .s_tready(gen_tready), .s_tlast(gen_tlast),
        .m_tdata(dp_m_tdata), .m_tvalid(dp_m_tvalid), .m_tready(dp_m_tready), .m_tlast(dp_m_tlast),
        .mirror_pulse(), .last_action(last_action),
        .stat_rx_frame(pulse_rx), .stat_tx_frame(pulse_tx),
        .stat_forward(pulse_fwd), .stat_drop(pulse_drop),
        .stat_mirror(pulse_mir), .stat_dpi_hit(pulse_dpi),
        .flow_update_valid(), .flow_update_state(),
        .dpi_pat0(32'h47455420), .dpi_pat1(32'h636d642e),
        .dpi_pat2(32'h53454c45), .dpi_pat3(32'h90909090),
        .aes_dp_en(1'b0), .aes_key(128'h0), .aes_dp_ct(), .aes_dp_done()
    );

    assign dp_m_tready = 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_rx <= 0; cnt_tx <= 0; cnt_fwd <= 0; cnt_drop <= 0; cnt_mir <= 0; cnt_dpi <= 0;
        end else begin
            if (pulse_rx)   cnt_rx   <= cnt_rx + 1;
            if (pulse_tx)   cnt_tx   <= cnt_tx + 1;
            if (pulse_fwd)  cnt_fwd  <= cnt_fwd + 1;
            if (pulse_drop) cnt_drop <= cnt_drop + 1;
            if (pulse_mir)  cnt_mir  <= cnt_mir + 1;
            if (pulse_dpi)  cnt_dpi  <= cnt_dpi + 1;
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1;
        repeat (30000) @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        repeat (800) @(posedge clk);

        $display("L0 CNT_RX=%0d TX=%0d FWD=%0d DROP=%0d MIR=%0d DPI=%0d",
                 cnt_rx, cnt_tx, cnt_fwd, cnt_drop, cnt_mir, cnt_dpi);
        // First DPI hit on a new flow is MIRROR (drain, no wire TX), not DROP.
        if (cnt_rx == 2 && cnt_fwd >= 1 && cnt_tx >= 1 && cnt_dpi >= 1 && cnt_mir >= 1)
            $display("PASS: tb_l0_loopback");
        else
            $display("FAIL: tb_l0_loopback");
        $finish;
    end
endmodule
