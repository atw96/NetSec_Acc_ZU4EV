// pkt_gen_10g.sv — periodic 64-byte AXIS (64-bit) Ethernet frames
`timescale 1ns / 1ps

module pkt_gen_10g #(
    parameter [7:0] PORT_ID = 8'h01
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        enable,
    output logic [63:0] m_tdata,
    output logic [7:0]  m_tkeep,
    output logic        m_tvalid,
    input  logic        m_tready,
    output logic        m_tlast,
    output logic        m_tuser,
    output logic        pulse_tx
);

    logic [3:0]  word;
    logic [15:0] gap;
    logic [15:0] seq;
    logic        active;

    assign m_tkeep = 8'hff;
    assign m_tuser = 1'b0;

    always_ff @(posedge clk) begin
        if (rst) begin
            word     <= 4'd0;
            gap      <= 16'd0;
            seq      <= 16'd0;
            active   <= 1'b0;
            m_tvalid <= 1'b0;
            m_tlast  <= 1'b0;
            m_tdata  <= 64'd0;
            pulse_tx <= 1'b0;
        end else begin
            pulse_tx <= 1'b0;
            if (!enable) begin
                active   <= 1'b0;
                m_tvalid <= 1'b0;
                m_tlast  <= 1'b0;
                gap      <= 16'd0;
            end else if (!active) begin
                m_tvalid <= 1'b0;
                m_tlast  <= 1'b0;
                if (gap == 16'd1023) begin
                    gap    <= 16'd0;
                    active <= 1'b1;
                    word   <= 4'd0;
                end else begin
                    gap <= gap + 1'b1;
                end
            end else begin
                m_tvalid <= 1'b1;
                m_tlast  <= (word == 4'd7);
                unique case (word)
                    4'd0: m_tdata <= {8'h00, 8'h00, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff};
                    4'd1: m_tdata <= {8'h00, 8'h08, PORT_ID, 8'h00, 8'h00, 8'h00, 8'h00, 8'h02};
                    4'd2: m_tdata <= {8'h00, 8'h00, 8'h00, 8'h40, 8'h00, 8'h00, 8'h00, 8'h45};
                    4'd3: m_tdata <= {seq[7:0], seq[15:8], 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
                    default: m_tdata <= {8{word, 4'hA}};
                endcase
                if (m_tready) begin
                    if (word == 4'd7) begin
                        active   <= 1'b0;
                        m_tvalid <= 1'b0;
                        m_tlast  <= 1'b0;
                        seq      <= seq + 1'b1;
                        pulse_tx <= 1'b1;
                    end else begin
                        word <= word + 1'b1;
                    end
                end
            end
        end
    end

endmodule
