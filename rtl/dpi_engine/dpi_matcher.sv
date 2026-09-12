// dpi_matcher.sv
// 并行比较器阵列多模式匹配引擎（Aho-Corasick 的简化替代方案，见
// docs/module_spec/04_dpi_engine.md 中的设计取舍说明）。
// 内置 4 条固定长度(4B)可配置的示例特征串（非真实威胁情报库，仅用于演示匹配机制）。
module u_dpi_matcher #(
    parameter NUM_PATTERNS = 4
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       data_valid,
    input  logic [7:0] data,
    input  logic       data_last,
    output logic       hit_valid,
    output logic [NUM_PATTERNS-1:0] hit_vector
);

    // 示例特征（32bit = 4 字节拼接，字节序与报文流一致）："GET ", "cmd.", "SELE"(CT 前4字节), NOP sled
    localparam [31:0] PAT0 = 32'h47455420;
    localparam [31:0] PAT1 = 32'h636d642e;
    localparam [31:0] PAT2 = 32'h53454c45;
    localparam [31:0] PAT3 = 32'h90909090;

    // 滑动窗口：hist[0]=上一拍字节, hist[1]=上上拍, hist[2]=上上上拍
    logic [7:0] hist [0:2];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hist[0] <= '0; hist[1] <= '0; hist[2] <= '0;
        end else if (data_valid) begin
            hist[2] <= hist[1];
            hist[1] <= hist[0];
            hist[0] <= data;
        end
    end

    // 当前完整 4 字节窗口：w0(最新,=本拍data) w1 w2 w3(最旧)
    wire [7:0] w0 = data;
    wire [7:0] w1 = hist[0];
    wire [7:0] w2 = hist[1];
    wire [7:0] w3 = hist[2];

    wire [31:0] window = {w3, w2, w1, w0}; // w3=最旧字节(对应特征首字节) ... w0=最新字节(特征末字节)

    assign hit_valid     = data_valid;
    assign hit_vector[0] = data_valid && (window == PAT0);
    assign hit_vector[1] = data_valid && (window == PAT1);
    assign hit_vector[2] = data_valid && (window == PAT2);
    assign hit_vector[3] = data_valid && (window == PAT3);

endmodule
