// netsec_cdc.sv — minimal pulse/level CDC between AXI (PS) and logic (125 MHz) domains
`timescale 1ns / 1ps

module netsec_pulse_cdc (
    input  logic src_clk,
    input  logic src_rst_n,
    input  logic src_pulse,
    input  logic dst_clk,
    input  logic dst_rst_n,
    output logic dst_pulse
);
    logic toggle;
    always_ff @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) toggle <= 1'b0;
        else if (src_pulse) toggle <= ~toggle;
    end
    logic [2:0] sync;
    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            sync <= '0;
            dst_pulse <= 1'b0;
        end else begin
            sync <= {sync[1:0], toggle};
            dst_pulse <= sync[1] ^ sync[2];
        end
    end
endmodule

module netsec_level_cdc #(parameter WIDTH = 1) (
    input  logic             src_clk,
    input  logic [WIDTH-1:0] src_level,
    input  logic             dst_clk,
    input  logic             dst_rst_n,
    output logic [WIDTH-1:0] dst_level
);
    logic [WIDTH-1:0] s0, s1;
    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            s0 <= '0; s1 <= '0;
        end else begin
            s0 <= src_level;
            s1 <= s0;
        end
    end
    assign dst_level = s1;
endmodule
