// aes128_pipe.sv — AES-128 encrypt, one round per cycle (10 rounds + final).
// Same round functions as u_aes128_core. Ciphertext is the FIPS-197 mapping
// (first plaintext byte in [127:120]).
import aes_sbox_pkg::*;
`timescale 1ns / 1ps

module u_aes128_pipe (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,
    input  logic [127:0] key,
    input  logic [127:0] plaintext,
    output logic         done,
    output logic [127:0] ciphertext
);
    function automatic [127:0] sub_bytes_fn(input [127:0] s);
        logic [7:0] b[0:15];
        int i;
        for (i = 0; i < 16; i++) b[i] = s[127-8*i -: 8];
        for (i = 0; i < 16; i++) b[i] = aes_sbox_pkg::sbox(b[i]);
        sub_bytes_fn = {b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],
                        b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]};
    endfunction

    function automatic [127:0] shift_rows_fn(input [127:0] s);
        logic [7:0] b[0:15], o[0:15];
        int r, c, i;
        for (i = 0; i < 16; i++) b[i] = s[127-8*i -: 8];
        for (c = 0; c < 4; c++)
            for (r = 0; r < 4; r++)
                o[4*c+r] = b[4*((c+r)%4)+r];
        shift_rows_fn = {o[0],o[1],o[2],o[3],o[4],o[5],o[6],o[7],
                         o[8],o[9],o[10],o[11],o[12],o[13],o[14],o[15]};
    endfunction

    function automatic [127:0] mix_columns_fn(input [127:0] s);
        logic [7:0] b[0:15], o[0:15];
        logic [7:0] a0, a1, a2, a3;
        int c, i;
        for (i = 0; i < 16; i++) b[i] = s[127-8*i -: 8];
        for (c = 0; c < 4; c++) begin
            a0 = b[4*c+0]; a1 = b[4*c+1]; a2 = b[4*c+2]; a3 = b[4*c+3];
            o[4*c+0] = aes_sbox_pkg::gmul(a0,8'h02) ^ aes_sbox_pkg::gmul(a1,8'h03) ^ a2 ^ a3;
            o[4*c+1] = a0 ^ aes_sbox_pkg::gmul(a1,8'h02) ^ aes_sbox_pkg::gmul(a2,8'h03) ^ a3;
            o[4*c+2] = a0 ^ a1 ^ aes_sbox_pkg::gmul(a2,8'h02) ^ aes_sbox_pkg::gmul(a3,8'h03);
            o[4*c+3] = aes_sbox_pkg::gmul(a0,8'h03) ^ a1 ^ a2 ^ aes_sbox_pkg::gmul(a3,8'h02);
        end
        mix_columns_fn = {o[0],o[1],o[2],o[3],o[4],o[5],o[6],o[7],
                          o[8],o[9],o[10],o[11],o[12],o[13],o[14],o[15]};
    endfunction

    function automatic [127:0] expand_round_fn(input [127:0] k, input [7:0] rcon);
        logic [31:0] w0, w1, w2, w3, temp;
        w0 = k[127:96]; w1 = k[95:64]; w2 = k[63:32]; w3 = k[31:0];
        temp = {w3[23:0], w3[31:24]};
        temp = {aes_sbox_pkg::sbox(temp[31:24]), aes_sbox_pkg::sbox(temp[23:16]),
                aes_sbox_pkg::sbox(temp[15:8]),  aes_sbox_pkg::sbox(temp[7:0])};
        temp = temp ^ {rcon, 24'h0};
        w0 = w0 ^ temp; w1 = w1 ^ w0; w2 = w2 ^ w1; w3 = w3 ^ w2;
        expand_round_fn = {w0, w1, w2, w3};
    endfunction

    function automatic [7:0] rcon_fn(input [3:0] rnd);
        case (rnd)
            4'd1:  rcon_fn = 8'h01; 4'd2:  rcon_fn = 8'h02; 4'd3:  rcon_fn = 8'h04;
            4'd4:  rcon_fn = 8'h08; 4'd5:  rcon_fn = 8'h10; 4'd6:  rcon_fn = 8'h20;
            4'd7:  rcon_fn = 8'h40; 4'd8:  rcon_fn = 8'h80; 4'd9:  rcon_fn = 8'h1b;
            4'd10: rcon_fn = 8'h36; default: rcon_fn = 8'h00;
        endcase
    endfunction

    logic [127:0] st [0:10];
    logic [127:0] rk [0:10];
    logic [10:0]  v;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v <= '0;
            done <= 1'b0;
            ciphertext <= '0;
            for (int i = 0; i <= 10; i++) begin
                st[i] <= '0;
                rk[i] <= '0;
            end
        end else begin
            v    <= {v[9:0], start};
            done <= v[9];
            if (start) begin
                st[0] <= plaintext ^ key;
                rk[0] <= key;
            end
            for (int i = 1; i <= 9; i++) begin
                if (v[i-1]) begin
                    rk[i] <= expand_round_fn(rk[i-1], rcon_fn(i[3:0]));
                    st[i] <= mix_columns_fn(shift_rows_fn(sub_bytes_fn(st[i-1]))) ^
                             expand_round_fn(rk[i-1], rcon_fn(i[3:0]));
                end
            end
            if (v[9]) begin
                rk[10]      <= expand_round_fn(rk[9], rcon_fn(4'd10));
                ciphertext  <= shift_rows_fn(sub_bytes_fn(st[9])) ^ expand_round_fn(rk[9], rcon_fn(4'd10));
                st[10]      <= shift_rows_fn(sub_bytes_fn(st[9])) ^ expand_round_fn(rk[9], rcon_fn(4'd10));
            end
        end
    end
endmodule
