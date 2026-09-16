`timescale 1ns / 1ps
// L0 FORWARD frame 0 bytes 42-57 are FIPS-197 PT; AES datapath must emit NIST CT.
module tb_aes_datapath;
    logic clk = 0, rst_n = 0, start = 0;
    always #4 clk = ~clk;

    logic [7:0] gen_tdata, dp_m_tdata;
    logic       gen_tvalid, gen_tready, gen_tlast;
    logic       dp_m_tvalid, dp_m_tready, dp_m_tlast;
    logic [1:0] last_action;
    logic       pulse_rx, pulse_tx, pulse_fwd, pulse_dpi, pulse_mir;
    logic [127:0] aes_ct;
    logic         aes_done;

    integer tx_idx;
    logic [7:0] tx_bytes [0:63];
    integer errors;

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
        .stat_forward(pulse_fwd), .stat_drop(),
        .stat_mirror(pulse_mir), .stat_dpi_hit(pulse_dpi),
        .flow_update_valid(), .flow_update_state(),
        .dpi_pat0(32'h47455420), .dpi_pat1(32'h636d642e),
        .dpi_pat2(32'h53454c45), .dpi_pat3(32'h90909090),
        .aes_dp_en(1'b1),
        .aes_key(128'h000102030405060708090a0b0c0d0e0f),
        .aes_dp_ct(aes_ct), .aes_dp_done(aes_done)
    );

    assign dp_m_tready = 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_idx <= 0;
        end else if (dp_m_tvalid && dp_m_tready && tx_idx < 64) begin
            tx_bytes[tx_idx] <= dp_m_tdata;
            tx_idx <= dp_m_tlast ? tx_idx : tx_idx + 1;
        end
    end

    initial begin
        errors = 0;
        repeat (8) @(posedge clk);
        rst_n = 1;
        repeat (30000) @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        repeat (1200) @(posedge clk);

        if (aes_ct !== 128'h69c4e0d86a7b0430d8cdb78070b4c55a) begin
            errors++;
            $display("FAIL: aes_dp_ct=%032h", aes_ct);
        end else
            $display("PASS: datapath AES CT register NIST");

        if (tx_bytes[42] !== 8'h69 || tx_bytes[43] !== 8'hc4 ||
            tx_bytes[56] !== 8'hc5 || tx_bytes[57] !== 8'h5a) begin
            errors++;
            $display("FAIL: TX[42]=%02h TX[43]=%02h TX[56]=%02h TX[57]=%02h",
                     tx_bytes[42], tx_bytes[43], tx_bytes[56], tx_bytes[57]);
        end else
            $display("PASS: TX bytes 42-57 are NIST ciphertext");

        if (errors == 0) $display("PASS: tb_aes_datapath");
        else             $display("tb_aes_datapath: %0d FAILURE(S)", errors);
        $finish;
    end
endmodule
