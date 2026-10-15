// pkt_gen_10g.sv — periodic 64-byte AXIS (64-bit) Ethernet frames.
// A beat advances only on tvalid && tready. tlast is high on the last beat
// and stays high until that beat is accepted.
`timescale 1ns / 1ps

module pkt_gen_10g #(
    parameter [7:0] PORT_ID = 8'h01
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        enable,
    input  logic [15:0] gap_cycles,
    output logic [63:0] m_tdata,
    output logic [7:0]  m_tkeep,
    output logic        m_tvalid,
    input  logic        m_tready,
    output logic        m_tlast,
    output logic        m_tuser,
    output logic        pulse_tx
);

    logic [3:0]  word;
    logic [15:0] gap_cnt;
    logic [15:0] seq;

    assign m_tkeep = 8'hff;
    assign m_tuser = 1'b0;

    function automatic [63:0] frame_beat(input [3:0] w, input [15:0] s);
        case (w)
            4'd0: frame_beat = {8'h00, 8'h00, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff};
            4'd1: frame_beat = {8'h00, 8'h08, PORT_ID, 8'h00, 8'h00, 8'h00, 8'h00, 8'h02};
            4'd2: frame_beat = {8'h00, 8'h00, 8'h00, 8'h40, 8'h00, 8'h00, 8'h00, 8'h45};
            4'd3: frame_beat = {s[7:0], s[15:8], 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
            default: frame_beat = {8{w, 4'hA}};
        endcase
    endfunction

    always_ff @(posedge clk) begin
        if (rst) begin
            word     <= 4'd0;
            gap_cnt  <= 16'd0;
            seq      <= 16'd0;
            m_tvalid <= 1'b0;
            m_tlast  <= 1'b0;
            m_tdata  <= 64'd0;
            pulse_tx <= 1'b0;
        end else begin
            pulse_tx <= 1'b0;
            if (!enable) begin
                word     <= 4'd0;
                gap_cnt  <= 16'd0;
                m_tvalid <= 1'b0;
                m_tlast  <= 1'b0;
            end else if (!m_tvalid) begin
                m_tlast <= 1'b0;
                if (gap_cnt >= gap_cycles) begin
                    gap_cnt  <= 16'd0;
                    word     <= 4'd0;
                    m_tdata  <= frame_beat(4'd0, seq);
                    m_tvalid <= 1'b1;
                    m_tlast  <= 1'b0;
                end else begin
                    gap_cnt <= gap_cnt + 16'd1;
                end
            end else if (m_tready) begin
                if (word == 4'd7) begin
                    m_tvalid <= 1'b0;
                    m_tlast  <= 1'b0;
                    word     <= 4'd0;
                    gap_cnt  <= 16'd0;
                    seq      <= seq + 16'd1;
                    pulse_tx <= 1'b1;
                end else begin
                    word     <= word + 4'd1;
                    m_tdata  <= frame_beat(word + 4'd1, seq);
                    m_tvalid <= 1'b1;
                    m_tlast  <= (word == 4'd6);
                end
            end
        end
    end

endmodule
