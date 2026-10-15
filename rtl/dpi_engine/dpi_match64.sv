// dpi_match64.sv — line-rate 4-byte match over a 64-bit beat.
// Programmable patterns (pat[31:24] is the first byte) plus ROM_PATTERNS
// constant signatures. A hit that straddles a beat is caught on the next beat.
`timescale 1ns / 1ps

module dpi_match64 #(
    parameter NUM_PAT      = 16,
    parameter ROM_PATTERNS = 128
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     in_valid,
    input  logic [63:0]              data,
    input  logic [7:0]               keep,
    input  logic                     in_last,
    input  logic [NUM_PAT*32-1:0]    pats,
    output logic                     frame_end_pulse,
    output logic                     frame_hit,
    output logic [NUM_PAT-1:0]       pat_hit
);
    function automatic [31:0] rom_pat(input integer n);
        rom_pat = {8'hC3, n[7:0], 8'h3C, n[7:0] ^ 8'hA5};
    endfunction

    logic [7:0] hist [0:2];
    logic       hist_ok;
    logic [7:0] byte_v [0:7];
    logic [31:0] win [0:7];
    logic [7:0] win_ok;

    integer li;
    always_comb begin
        for (li = 0; li < 8; li = li + 1)
            byte_v[li] = data[8*li +: 8];
        win[0] = {hist[2], hist[1], hist[0], byte_v[0]};
        win[1] = {hist[1], hist[0], byte_v[0], byte_v[1]};
        win[2] = {hist[0], byte_v[0], byte_v[1], byte_v[2]};
        win[3] = {byte_v[0], byte_v[1], byte_v[2], byte_v[3]};
        win[4] = {byte_v[1], byte_v[2], byte_v[3], byte_v[4]};
        win[5] = {byte_v[2], byte_v[3], byte_v[4], byte_v[5]};
        win[6] = {byte_v[3], byte_v[4], byte_v[5], byte_v[6]};
        win[7] = {byte_v[4], byte_v[5], byte_v[6], byte_v[7]};
        win_ok[0] = hist_ok & keep[0];
        win_ok[1] = hist_ok & keep[0] & keep[1];
        win_ok[2] = hist_ok & keep[0] & keep[1] & keep[2];
        win_ok[3] = keep[0] & keep[1] & keep[2] & keep[3];
        win_ok[4] = keep[1] & keep[2] & keep[3] & keep[4];
        win_ok[5] = keep[2] & keep[3] & keep[4] & keep[5];
        win_ok[6] = keep[3] & keep[4] & keep[5] & keep[6];
        win_ok[7] = keep[4] & keep[5] & keep[6] & keep[7];
    end

    logic [NUM_PAT-1:0] match_p;
    logic               match_rom;
    integer p, ww;
    always_comb begin
        match_p   = '0;
        match_rom = 1'b0;
        for (p = 0; p < NUM_PAT; p = p + 1) begin
            for (ww = 0; ww < 8; ww = ww + 1) begin
                if (win_ok[ww] && pats[32*p +: 32] != 32'd0 &&
                    win[ww] == pats[32*p +: 32])
                    match_p[p] = 1'b1;
            end
        end
        for (p = 0; p < ROM_PATTERNS; p = p + 1) begin
            for (ww = 0; ww < 8; ww = ww + 1) begin
                if (win_ok[ww] && win[ww] == rom_pat(p))
                    match_rom = 1'b1;
            end
        end
    end

    logic               valid_d, last_d, rom_d;
    logic [NUM_PAT-1:0] match_d;
    logic [NUM_PAT-1:0] sticky;
    logic               rom_sticky;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hist_ok         <= 1'b0;
            hist[0]         <= '0;
            hist[1]         <= '0;
            hist[2]         <= '0;
            valid_d         <= 1'b0;
            last_d          <= 1'b0;
            rom_d           <= 1'b0;
            match_d         <= '0;
            sticky          <= '0;
            rom_sticky      <= 1'b0;
            frame_end_pulse <= 1'b0;
            frame_hit       <= 1'b0;
            pat_hit         <= '0;
        end else begin
            valid_d <= in_valid;
            last_d  <= in_valid && in_last;
            match_d <= match_p;
            rom_d   <= match_rom;
            frame_end_pulse <= 1'b0;
            pat_hit <= '0;

            if (in_valid) begin
                if (keep[7] & keep[6] & keep[5]) begin
                    hist[2] <= byte_v[5];
                    hist[1] <= byte_v[6];
                    hist[0] <= byte_v[7];
                    hist_ok <= !in_last;
                end else begin
                    hist_ok <= 1'b0;
                end
                if (in_last)
                    hist_ok <= 1'b0;
            end

            if (valid_d) begin
                if (last_d) begin
                    frame_end_pulse <= 1'b1;
                    pat_hit         <= sticky | match_d;
                    frame_hit       <= |(sticky | match_d) | rom_sticky | rom_d;
                    sticky          <= '0;
                    rom_sticky      <= 1'b0;
                end else begin
                    sticky     <= sticky | match_d;
                    rom_sticky <= rom_sticky | rom_d;
                end
            end
        end
    end
endmodule
