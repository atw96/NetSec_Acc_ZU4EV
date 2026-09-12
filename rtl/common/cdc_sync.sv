// cdc_sync.sv
// 2 级触发器同步器，用于单 bit / 控制信号跨时钟域同步（不适用于多 bit 总线，
// 多 bit 数据请使用格雷码异步 FIFO）。
module u_cdc_sync #(
    parameter WIDTH = 1,
    parameter STAGES = 2
) (
    input  logic             dst_clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] async_in,
    output logic [WIDTH-1:0] sync_out
);
    logic [WIDTH-1:0] sync_chain [0:STAGES-1];

    genvar i;
    generate
        for (i = 0; i < STAGES; i++) begin : g_stage
            always_ff @(posedge dst_clk or negedge rst_n) begin
                if (!rst_n) begin
                    sync_chain[i] <= '0;
                end else if (i == 0) begin
                    sync_chain[i] <= async_in;
                end else begin
                    sync_chain[i] <= sync_chain[i-1];
                end
            end
        end
    endgenerate

    assign sync_out = sync_chain[STAGES-1];
endmodule

// reset_sync.sv
// 异步置位、同步释放的复位同步器。
module u_reset_sync (
    input  logic clk,
    input  logic async_rst_n,
    output logic sync_rst_n
);
    logic rst_ff1;

    always_ff @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            rst_ff1    <= 1'b0;
            sync_rst_n <= 1'b0;
        end else begin
            rst_ff1    <= 1'b1;
            sync_rst_n <= rst_ff1;
        end
    end
endmodule
