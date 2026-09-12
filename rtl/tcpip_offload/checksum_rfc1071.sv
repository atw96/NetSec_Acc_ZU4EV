// checksum_rfc1071.sv
// RFC1071 反码和校验和硬件加速引擎：逐 16bit 字流水线累加 + end-around carry。
module u_checksum_rfc1071 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,       // 拉高 1 拍，清零累加器，开始新的一次计算
    input  logic        data_valid,
    input  logic [15:0] data,        // 16bit 字（若原始数据为奇数字节，最后一字节需在上层补零对齐）
    input  logic        data_last,
    output logic        checksum_valid,
    output logic [15:0] checksum
);

    logic [16:0] acc; // 多 1 位用于捕获进位

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc            <= '0;
            checksum       <= '0;
            checksum_valid <= 1'b0;
        end else begin
            checksum_valid <= 1'b0;

            if (start) begin
                acc <= '0;
            end else if (data_valid) begin
                logic [16:0] sum_tmp;
                sum_tmp = {1'b0, acc[15:0]} + {1'b0, data};
                // end-around carry: 若产生进位，将进位加回低16位
                acc <= sum_tmp[16] ? (sum_tmp[15:0] + 17'd1) : sum_tmp;

                if (data_last) begin
                    // 取反得到最终校验和；用当前拍算出的 sum_tmp（含本字节）折算
                    logic [16:0] final_sum;
                    final_sum = sum_tmp[16] ? (sum_tmp[15:0] + 17'd1) : sum_tmp;
                    checksum       <= ~final_sum[15:0];
                    checksum_valid <= 1'b1;
                end
            end
        end
    end

endmodule
