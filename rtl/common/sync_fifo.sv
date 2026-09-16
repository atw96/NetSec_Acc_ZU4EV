// sync_fifo.sv
// 同步 FIFO（单时钟域）。FWFT=1 时读口为 First-Word Fall-Through：
// empty=0 表示 rd_data 已是队头，无需先打一拍 rd_en。
module u_sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16,                  // 必须为 2 的幂
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter FWFT       = 0
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   wr_en,
    input  logic [DATA_WIDTH-1:0]  wr_data,
    output logic                   full,
    input  logic                   rd_en,
    output logic [DATA_WIDTH-1:0]  rd_data,
    output logic                   empty
);

    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [ADDR_WIDTH:0] wr_ptr, rd_ptr;

    wire raw_full  = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) &&
                     (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
    wire raw_empty = (wr_ptr == rd_ptr);

    assign full = raw_full;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else if (wr_en && !full) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    generate
        if (FWFT != 0) begin : g_fwft
            logic fwft_valid;
            wire  rd_en_int = !raw_empty && (!fwft_valid || rd_en);

            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    rd_ptr     <= '0;
                    rd_data    <= '0;
                    fwft_valid <= 1'b0;
                end else if (rd_en_int) begin
                    rd_data    <= mem[rd_ptr[ADDR_WIDTH-1:0]];
                    rd_ptr     <= rd_ptr + 1'b1;
                    fwft_valid <= 1'b1;
                end else if (rd_en) begin
                    fwft_valid <= 1'b0;
                end
            end
            assign empty = ~fwft_valid;
        end else begin : g_std
            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    rd_ptr  <= '0;
                    rd_data <= '0;
                end else if (rd_en && !raw_empty) begin
                    rd_data <= mem[rd_ptr[ADDR_WIDTH-1:0]];
                    rd_ptr  <= rd_ptr + 1'b1;
                end
            end
            assign empty = raw_empty;
        end
    endgenerate

endmodule
