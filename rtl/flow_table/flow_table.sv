// flow_table.sv — synthesizable 4-way hash flow table
// Sync reset; RAM contents not wiped on reset (valid bits cleared only) to allow BRAM.
`timescale 1ns / 1ps

module u_flow_table #(
    parameter HASH_BITS = 4,
    parameter WAYS      = 4
) (
    input  logic         clk,
    input  logic         rst_n,

    input  logic         req_valid,
    input  logic [31:0]  src_ip,
    input  logic [31:0]  dst_ip,
    input  logic [15:0]  src_port,
    input  logic [15:0]  dst_port,
    input  logic [7:0]   protocol,

    output logic         resp_valid,
    output logic         hit,
    output logic [1:0]   flow_state,
    output logic [HASH_BITS+1:0] flow_idx,

    input  logic         update_valid,
    input  logic [HASH_BITS+1:0] update_idx,
    input  logic [1:0]   update_state
);

    localparam DEPTH = (1 << HASH_BITS);
    localparam TOTAL = DEPTH * WAYS;

    (* ram_style = "distributed" *) logic         valid_mem [0:TOTAL-1];
    (* ram_style = "block" *)        logic [1:0]   state_mem [0:TOTAL-1];
    (* ram_style = "block" *)        logic [7:0]   age_mem   [0:TOTAL-1];
    (* ram_style = "block" *)        logic [103:0] key_mem   [0:TOTAL-1];

    logic [103:0] lookup_key;
    logic [HASH_BITS-1:0] hash_idx;

    assign lookup_key = {src_ip, dst_ip, src_port, dst_port, protocol};

    always_comb begin
        logic [103:0] k;
        logic [HASH_BITS-1:0] h;
        int seg;
        k = lookup_key;
        h = '0;
        for (seg = 0; seg < (104 / HASH_BITS) + 1; seg++) begin
            h = h ^ k[HASH_BITS-1:0];
            k = k >> HASH_BITS;
        end
        hash_idx = h;
    end

    integer w;
    logic found;
    logic [1:0] way_sel;
    logic alloc_found;
    logic [1:0] alloc_way;
    logic [7:0] max_age;
    integer base_idx, idx;
    integer vi;

    // Sync reset — clear valids only (keeps BRAM inference for key/state/age)
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            resp_valid <= 1'b0;
            hit        <= 1'b0;
            flow_state <= 2'b00;
            flow_idx   <= '0;
            for (vi = 0; vi < TOTAL; vi = vi + 1)
                valid_mem[vi] <= 1'b0;
        end else begin
            resp_valid <= 1'b0;

            if (update_valid) begin
                state_mem[update_idx[HASH_BITS+1:2]*WAYS + update_idx[1:0]] <= update_state;
            end

            if (req_valid) begin
                base_idx = hash_idx * WAYS;
                found   = 1'b0;
                way_sel = 2'd0;
                for (w = 0; w < WAYS; w = w + 1) begin
                    if (!found && valid_mem[base_idx+w] && key_mem[base_idx+w] == lookup_key) begin
                        found   = 1'b1;
                        way_sel = w[1:0];
                    end
                end

                if (found) begin
                    idx = base_idx + way_sel;
                    hit          <= 1'b1;
                    flow_state   <= state_mem[idx];
                    flow_idx     <= {hash_idx, way_sel};
                    age_mem[idx] <= 8'd0;
                end else begin
                    alloc_found = 1'b0;
                    alloc_way   = 2'd0;
                    max_age     = 8'd0;
                    for (w = 0; w < WAYS; w = w + 1) begin
                        if (!valid_mem[base_idx+w] && !alloc_found) begin
                            alloc_found = 1'b1;
                            alloc_way   = w[1:0];
                        end
                        if (age_mem[base_idx+w] >= max_age) begin
                            max_age = age_mem[base_idx+w];
                            if (!alloc_found) alloc_way = w[1:0];
                        end
                    end
                    idx = base_idx + alloc_way;
                    valid_mem[idx] <= 1'b1;
                    state_mem[idx] <= 2'b00;
                    age_mem[idx]   <= 8'd0;
                    key_mem[idx]   <= lookup_key;
                    hit            <= 1'b0;
                    flow_state     <= 2'b00;
                    flow_idx       <= {hash_idx, alloc_way};
                end
                resp_valid <= 1'b1;

                for (w = 0; w < WAYS; w = w + 1) begin
                    if (valid_mem[base_idx+w] && !(found && w[1:0] == way_sel)) begin
                        if (age_mem[base_idx+w] != 8'hFF)
                            age_mem[base_idx+w] <= age_mem[base_idx+w] + 8'd1;
                    end
                end
            end
        end
    end

endmodule
