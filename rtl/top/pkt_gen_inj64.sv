// pkt_gen_inj64.sv — one-shot copy of pkt_gen_bram's two canned frames, 64-bit.
// Frame 0 carries the FIPS-197 plaintext at byte offset 42.
// Frame 1 carries "GET " at bytes 54-57 (crosses a beat boundary).
`timescale 1ns / 1ps

module pkt_gen_inj64 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    output logic [63:0] m_tdata,
    output logic [7:0]  m_tkeep,
    output logic        m_tvalid,
    input  logic        m_tready,
    output logic        m_tlast,
    output logic        m_tuser,
    output logic        busy
);
    // 16 beats: frame0 (8, last keep 0x0F) then frame1 (8, keep 0xFF). Bit 8 of the
    // sideband marks frame0's short last beat.
    localparam integer N = 16;
    logic [63:0] rom_d [0:N-1];
    logic [7:0]  rom_k [0:N-1];
    logic        rom_l [0:N-1];

    initial begin
        rom_d[0]  = 64'h0002_ffff_ffff_ffff; rom_k[0]  = 8'hff; rom_l[0]  = 1'b0;
        rom_d[1]  = 64'h0045_0008_0100_0000; rom_k[1]  = 8'hff; rom_l[1]  = 1'b0;
        rom_d[2]  = 64'h0640_0040_0100_2800; rom_k[2]  = 8'hff; rom_l[2]  = 1'b0;
        rom_d[3]  = 64'ha8c0_0201_a8c0_0000; rom_k[3]  = 8'hff; rom_l[3]  = 1'b0;
        rom_d[4]  = 64'h0000_5000_d204_6401; rom_k[4]  = 8'hff; rom_l[4]  = 1'b0;
        rom_d[5]  = 64'h5544_3322_1100_0100; rom_k[5]  = 8'hff; rom_l[5]  = 1'b0;
        rom_d[6]  = 64'hddcc_bbaa_9988_7766; rom_k[6]  = 8'hff; rom_l[6]  = 1'b0;
        rom_d[7]  = 64'h0000_0000_0000_ffee; rom_k[7]  = 8'h0f; rom_l[7]  = 1'b1;
        rom_d[8]  = 64'h0002_ffff_ffff_ffff; rom_k[8]  = 8'hff; rom_l[8]  = 1'b0;
        rom_d[9]  = 64'h0045_0008_0200_0000; rom_k[9]  = 8'hff; rom_l[9]  = 1'b0;
        rom_d[10] = 64'h0640_0040_0200_2c00; rom_k[10] = 8'hff; rom_l[10] = 1'b0;
        rom_d[11] = 64'ha8c0_0500_000a_0000; rom_k[11] = 8'hff; rom_l[11] = 1'b0;
        rom_d[12] = 64'h0000_5000_d204_6401; rom_k[12] = 8'hff; rom_l[12] = 1'b0;
        rom_d[13] = 64'h0250_0000_0000_0100; rom_k[13] = 8'hff; rom_l[13] = 1'b0;
        rom_d[14] = 64'h4547_0000_0000_0020; rom_k[14] = 8'hff; rom_l[14] = 1'b0;
        rom_d[15] = 64'h0000_0000_002f_2054; rom_k[15] = 8'hff; rom_l[15] = 1'b1;
    end

    logic [4:0] idx;
    logic       active, start_d, gap;

    assign busy    = active;
    assign m_tuser = 1'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active   <= 1'b0;
            start_d  <= 1'b0;
            gap      <= 1'b0;
            idx      <= '0;
            m_tvalid <= 1'b0;
            m_tlast  <= 1'b0;
            m_tdata  <= '0;
            m_tkeep  <= '0;
        end else begin
            start_d <= start;
            if (start && !start_d && !active) begin
                active   <= 1'b1;
                gap      <= 1'b0;
                idx      <= '0;
                m_tvalid <= 1'b0;
            end else if (active && gap) begin
                gap      <= 1'b0;
                m_tvalid <= 1'b1;
                m_tdata  <= rom_d[idx];
                m_tkeep  <= rom_k[idx];
                m_tlast  <= rom_l[idx];
            end else if (active && !m_tvalid) begin
                m_tvalid <= 1'b1;
                m_tdata  <= rom_d[idx];
                m_tkeep  <= rom_k[idx];
                m_tlast  <= rom_l[idx];
            end else if (active && m_tvalid && m_tready) begin
                if (idx == N-1) begin
                    active   <= 1'b0;
                    m_tvalid <= 1'b0;
                    m_tlast  <= 1'b0;
                end else if (rom_l[idx]) begin
                    m_tvalid <= 1'b0;
                    m_tlast  <= 1'b0;
                    gap      <= 1'b1;
                    idx      <= idx + 1'b1;
                end else begin
                    idx      <= idx + 1'b1;
                    m_tdata  <= rom_d[idx + 1];
                    m_tkeep  <= rom_k[idx + 1];
                    m_tlast  <= rom_l[idx + 1];
                end
            end
        end
    end
endmodule
