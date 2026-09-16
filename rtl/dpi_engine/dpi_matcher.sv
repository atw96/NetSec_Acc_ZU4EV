// dpi_matcher.sv
// 4×4B 可编程 Aho-Corasick。
// 建表：插入 trie → fail → 展开 trans[state][byte]（多周期，非数据面）。
// 匹配：1 拍查 trans，命中相对数据延迟 1 拍（store-and-forward 可容忍）。
module u_dpi_matcher #(
    parameter NUM_PATTERNS = 4,
    parameter integer MAX_NODES = 17
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        data_valid,
    input  logic [7:0]  data,
    input  logic        data_last,
    input  logic [31:0] pat0,
    input  logic [31:0] pat1,
    input  logic [31:0] pat2,
    input  logic [31:0] pat3,
    output logic        ready,
    output logic        hit_valid,
    output logic [NUM_PATTERNS-1:0] hit_vector
);

    localparam integer N = MAX_NODES;

    logic [7:0] edge_ch  [0:N-1][0:3];
    logic [4:0] edge_to  [0:N-1][0:3];
    logic [2:0] edge_cnt [0:N-1];
    logic [4:0] fail_t   [0:N-1];
    logic [3:0] out_t    [0:N-1];
    logic [4:0] parent   [0:N-1];
    logic [7:0] inch     [0:N-1];
    logic [4:0] node_cnt;

    (* ram_style = "distributed" *) logic [4:0] trans [0:N-1][0:255];

    logic [31:0] pat0_d, pat1_d, pat2_d, pat3_d;

    typedef enum logic [2:0] {ST_CLR, ST_INS, ST_FWALK, ST_EXPAND, ST_READY} bld_t;
    bld_t bld;

    logic [1:0] pat_i, byte_i;
    logic [4:0] cur, fail_idx, match_st;
    logic [4:0] fill_s, fill_t;
    logic [8:0] fill_c; // 0..256
    integer ci, cj, ii, kk, ll;

    logic [31:0] ins_pat;
    logic [7:0]  ins_ch;
    always_comb begin
        case (pat_i)
            2'd0: ins_pat = pat0;
            2'd1: ins_pat = pat1;
            2'd2: ins_pat = pat2;
            default: ins_pat = pat3;
        endcase
        case (byte_i)
            2'd0: ins_ch = ins_pat[31:24];
            2'd1: ins_ch = ins_pat[23:16];
            2'd2: ins_ch = ins_pat[15:8];
            default: ins_ch = ins_pat[7:0];
        endcase
    end

    logic       ins_hit;
    logic [4:0] ins_dest;
    always_comb begin
        ins_hit  = 1'b0;
        ins_dest = node_cnt;
        for (ii = 0; ii < 4; ii++) begin
            if (ii < edge_cnt[cur] && edge_ch[cur][ii] == ins_ch) begin
                ins_hit  = 1'b1;
                ins_dest = edge_to[cur][ii];
            end
        end
    end

    logic       fw_hit;
    logic [4:0] fw_to;
    logic [4:0] fw_s;
    logic [7:0] fch;
    assign fw_s = fail_t[parent[fail_idx]];
    assign fch  = inch[fail_idx];
    always_comb begin
        fw_hit = 1'b0;
        fw_to  = 5'd0;
        for (kk = 0; kk < 4; kk++) begin
            if (kk < edge_cnt[fw_s] && edge_ch[fw_s][kk] == fch &&
                edge_to[fw_s][kk] != fail_idx) begin
                fw_hit = 1'b1;
                fw_to  = edge_to[fw_s][kk];
            end
        end
    end

    // sequential expand: one fail-hop per cycle
    logic       ex_hit;
    logic [4:0] ex_to;
    always_comb begin
        ex_hit = 1'b0;
        ex_to  = 5'd0;
        for (ll = 0; ll < 4; ll++) begin
            if (ll < edge_cnt[fill_t] && edge_ch[fill_t][ll] == fill_c[7:0]) begin
                ex_hit = 1'b1;
                ex_to  = edge_to[fill_t][ll];
            end
        end
    end

    assign ready = (bld == ST_READY);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bld       <= ST_CLR;
            node_cnt  <= 5'd1;
            pat_i     <= 2'd0;
            byte_i    <= 2'd0;
            cur       <= 5'd0;
            fail_idx  <= 5'd1;
            match_st  <= 5'd0;
            fill_s    <= 5'd0;
            fill_c    <= 9'd0;
            fill_t    <= 5'd0;
            hit_valid <= 1'b0;
            hit_vector<= 4'd0;
            pat0_d <= 32'h0; pat1_d <= 32'h0;
            pat2_d <= 32'h0; pat3_d <= 32'h0;
            for (ci = 0; ci < N; ci++) begin
                edge_cnt[ci] <= 3'd0;
                fail_t[ci]   <= 5'd0;
                out_t[ci]    <= 4'd0;
                parent[ci]   <= 5'd0;
                inch[ci]     <= 8'd0;
                for (cj = 0; cj < 4; cj++) begin
                    edge_ch[ci][cj] <= 8'd0;
                    edge_to[ci][cj] <= 5'd0;
                end
            end
        end else begin
            hit_valid  <= 1'b0;
            hit_vector <= 4'd0;
            pat0_d <= pat0; pat1_d <= pat1;
            pat2_d <= pat2; pat3_d <= pat3;

            if (bld == ST_READY &&
                (pat0 != pat0_d || pat1 != pat1_d || pat2 != pat2_d || pat3 != pat3_d)) begin
                bld      <= ST_CLR;
                match_st <= 5'd0;
            end

            case (bld)
                ST_CLR: begin
                    for (ci = 0; ci < N; ci++) begin
                        edge_cnt[ci] <= 3'd0;
                        fail_t[ci]   <= 5'd0;
                        out_t[ci]    <= 4'd0;
                    end
                    node_cnt  <= 5'd1;
                    fail_t[0] <= 5'd0;
                    pat_i     <= 2'd0;
                    byte_i    <= 2'd0;
                    cur       <= 5'd0;
                    bld       <= ST_INS;
                end
                ST_INS: begin
                    if (!ins_hit && node_cnt < 5'd17 && edge_cnt[cur] < 3'd4) begin
                        edge_ch[cur][edge_cnt[cur]] <= ins_ch;
                        edge_to[cur][edge_cnt[cur]] <= node_cnt;
                        edge_cnt[cur] <= edge_cnt[cur] + 3'd1;
                        parent[node_cnt] <= cur;
                        inch[node_cnt]   <= ins_ch;
                        node_cnt <= node_cnt + 5'd1;
                    end
                    if (byte_i == 2'd3) begin
                        out_t[ins_dest] <= out_t[ins_dest] | (4'b0001 << pat_i);
                        cur    <= 5'd0;
                        byte_i <= 2'd0;
                        if (pat_i == 2'd3) begin
                            fail_idx <= 5'd1;
                            bld      <= ST_FWALK;
                        end else
                            pat_i <= pat_i + 2'd1;
                    end else begin
                        cur    <= ins_dest;
                        byte_i <= byte_i + 2'd1;
                    end
                end
                ST_FWALK: begin
                    if (fail_idx >= node_cnt) begin
                        fill_s <= 5'd0;
                        fill_c <= 9'd0;
                        fill_t <= 5'd0;
                        bld    <= ST_EXPAND;
                    end else begin
                        fail_t[fail_idx] <= fw_hit ? fw_to : 5'd0;
                        out_t[fail_idx]  <= out_t[fail_idx] | out_t[fw_hit ? fw_to : 5'd0];
                        fail_idx <= fail_idx + 5'd1;
                    end
                end
                ST_EXPAND: begin
                    if (ex_hit) begin
                        trans[fill_s][fill_c[7:0]] <= ex_to;
                        if (fill_c == 9'd255) begin
                            fill_c <= 9'd0;
                            if (fill_s + 5'd1 >= node_cnt)
                                bld <= ST_READY;
                            else begin
                                fill_s <= fill_s + 5'd1;
                                fill_t <= fill_s + 5'd1;
                            end
                        end else begin
                            fill_c <= fill_c + 9'd1;
                            fill_t <= fill_s;
                        end
                    end else if (fill_t == 5'd0) begin
                        trans[fill_s][fill_c[7:0]] <= 5'd0;
                        if (fill_c == 9'd255) begin
                            fill_c <= 9'd0;
                            if (fill_s + 5'd1 >= node_cnt)
                                bld <= ST_READY;
                            else begin
                                fill_s <= fill_s + 5'd1;
                                fill_t <= fill_s + 5'd1;
                            end
                        end else begin
                            fill_c <= fill_c + 9'd1;
                            fill_t <= fill_s;
                        end
                    end else begin
                        fill_t <= fail_t[fill_t];
                    end
                end
                ST_READY: begin
                    if (data_valid) begin
                        match_st   <= data_last ? 5'd0 : trans[match_st][data];
                        hit_vector <= out_t[trans[match_st][data]];
                        hit_valid  <= |out_t[trans[match_st][data]];
                    end
                end
                default: bld <= ST_CLR;
            endcase
        end
    end

endmodule
