// flow_table_uram.sv — 4-way set-associative flow table.
// key RAM is coded for URAM; meta (valid/state) for BRAM.
// HASH_BITS must divide 104. Lookup latency is 2 cycles. One request in flight.
// Evict: first invalid way, else way 0.
`timescale 1ns / 1ps

module mem_ultra #(
    parameter WIDTH = 104,
    parameter DEPTH = 8192
) (
    input  logic                     clk,
    input  logic                     we,
    input  logic [$clog2(DEPTH)-1:0] waddr,
    input  logic [WIDTH-1:0]         wdata,
    input  logic [$clog2(DEPTH)-1:0] raddr,
    output logic [WIDTH-1:0]         rdata
);
    (* ram_style = "ultra" *) logic [WIDTH-1:0] mem [0:DEPTH-1];
    integer ii;
    initial for (ii = 0; ii < DEPTH; ii = ii + 1) mem[ii] = '0;
    always_ff @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end
endmodule

module mem_block #(
    parameter WIDTH = 16,
    parameter DEPTH = 8192
) (
    input  logic                     clk,
    input  logic                     we,
    input  logic [$clog2(DEPTH)-1:0] waddr,
    input  logic [WIDTH-1:0]         wdata,
    input  logic [$clog2(DEPTH)-1:0] raddr,
    output logic [WIDTH-1:0]         rdata
);
    (* ram_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];
    integer ii;
    initial for (ii = 0; ii < DEPTH; ii = ii + 1) mem[ii] = '0;
    always_ff @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end
endmodule

module u_flow_table_uram #(
    parameter HASH_BITS = 13,
    parameter WAYS      = 4
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 req_valid,
    input  logic [103:0]         key,
    output logic                 resp_valid,
    output logic                 hit,
    output logic                 alloc,
    output logic [1:0]           flow_state,
    output logic [HASH_BITS+1:0] flow_idx,
    input  logic                 update_valid,
    input  logic [HASH_BITS+1:0] update_idx,
    input  logic [1:0]           update_state
);
    localparam DEPTH = (1 << HASH_BITS);

    function automatic [HASH_BITS-1:0] hash104(input logic [103:0] k);
        logic [HASH_BITS-1:0] h;
        logic [103:0] kk;
        integer s;
        h  = '0;
        kk = k;
        for (s = 0; s < (104 / HASH_BITS); s = s + 1) begin
            h  = h ^ kk[HASH_BITS-1:0];
            kk = kk >> HASH_BITS;
        end
        hash104 = h;
    endfunction

    logic [HASH_BITS-1:0] hash_q, hash_qq;
    logic [103:0]         key_qq;
    logic                 req_q, req_qq;
    logic                 upd_pend;
    logic [HASH_BITS+1:0] upd_idx_r;
    logic [1:0]           upd_state_r;

    logic [103:0] key_rd  [0:WAYS-1];
    logic [15:0]  meta_rd [0:WAYS-1];

    integer w;
    logic [WAYS-1:0] way_hit;
    logic            any_hit, have_inval;
    logic [1:0]      hit_way, alloc_way;
    always_comb begin
        any_hit    = 1'b0;
        hit_way    = 2'd0;
        have_inval = 1'b0;
        alloc_way  = 2'd0;
        way_hit    = '0;
        for (w = 0; w < WAYS; w = w + 1) begin
            way_hit[w] = meta_rd[w][0] && (key_rd[w] == key_qq);
            if (way_hit[w] && !any_hit) begin
                any_hit = 1'b1;
                hit_way = w[1:0];
            end
            if (!meta_rd[w][0] && !have_inval) begin
                have_inval = 1'b1;
                alloc_way  = w[1:0];
            end
        end
    end

    wire       do_alloc = req_qq && !any_hit;
    wire [1:0] use_way  = any_hit ? hit_way : alloc_way;

    wire upd_go = upd_pend && !(do_alloc && alloc_way == upd_idx_r[1:0]);

    genvar gw;
    generate
        for (gw = 0; gw < WAYS; gw = gw + 1) begin : g_way
            wire we_k = do_alloc && (alloc_way == gw[1:0]);
            wire we_m = we_k || (upd_go && upd_idx_r[1:0] == gw[1:0]);
            wire [HASH_BITS-1:0] maddr = we_k ? hash_qq : upd_idx_r[HASH_BITS+1:2];
            wire [15:0] mdata = we_k ? 16'h0001 : {13'd0, upd_state_r, 1'b1};
            mem_ultra #(.WIDTH(104), .DEPTH(DEPTH)) u_key (
                .clk(clk), .we(we_k), .waddr(hash_qq), .wdata(key_qq),
                .raddr(hash_q), .rdata(key_rd[gw])
            );
            mem_block #(.WIDTH(16), .DEPTH(DEPTH)) u_meta (
                .clk(clk), .we(we_m), .waddr(maddr), .wdata(mdata),
                .raddr(hash_q), .rdata(meta_rd[gw])
            );
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_q       <= 1'b0;
            req_qq      <= 1'b0;
            resp_valid  <= 1'b0;
            hit         <= 1'b0;
            alloc       <= 1'b0;
            flow_state  <= 2'b00;
            flow_idx    <= '0;
            hash_q      <= '0;
            hash_qq     <= '0;
            key_qq      <= '0;
            upd_pend    <= 1'b0;
            upd_idx_r   <= '0;
            upd_state_r <= 2'b00;
        end else begin
            req_q   <= req_valid;
            req_qq  <= req_q;
            hash_q  <= hash104(key);
            hash_qq <= hash_q;
            if (req_valid) key_qq <= key;

            resp_valid <= req_qq;
            hit        <= req_qq && any_hit;
            alloc      <= do_alloc;
            flow_state <= (req_qq && any_hit) ? meta_rd[hit_way][2:1] : 2'b00;
            flow_idx   <= {hash_qq, use_way};

            if (update_valid) begin
                upd_pend    <= 1'b1;
                upd_idx_r   <= update_idx;
                upd_state_r <= update_state;
            end else if (upd_go) begin
                upd_pend <= 1'b0;
            end
        end
    end
endmodule
