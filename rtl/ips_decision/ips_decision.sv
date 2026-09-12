// ips_decision.sv
// 综合流表状态(02模块) + DPI命中(04模块)，输出决策动作。
// 决策表见 docs/module_spec/06_ips_decision.md
module u_ips_decision (
    input  logic       clk,
    input  logic       rst_n,

    input  logic        valid,
    input  logic [1:0]  flow_state,   // 00=新流 01=已放行 10=可疑 11=阻断
    input  logic        dpi_hit,      // 该报文/流是否命中 DPI 特征

    output logic        out_valid,
    output logic [1:0]  action,           // 00=FORWARD 01=DROP 10=RATE_LIMIT 11=MIRROR_TO_PS
    output logic        flow_update_valid,
    output logic [1:0]  flow_update_state
);

    localparam [1:0] ACT_FORWARD     = 2'b00;
    localparam [1:0] ACT_DROP        = 2'b01;
    localparam [1:0] ACT_RATE_LIMIT  = 2'b10;
    localparam [1:0] ACT_MIRROR      = 2'b11;

    localparam [1:0] FS_NEW      = 2'b00;
    localparam [1:0] FS_ALLOWED  = 2'b01;
    localparam [1:0] FS_SUSPECT  = 2'b10;
    localparam [1:0] FS_BLOCKED  = 2'b11;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid         <= 1'b0;
            action            <= ACT_FORWARD;
            flow_update_valid <= 1'b0;
            flow_update_state <= FS_NEW;
        end else begin
            out_valid         <= valid;
            flow_update_valid <= 1'b0;
            flow_update_state <= flow_state;

            if (valid) begin
                case (flow_state)
                    FS_BLOCKED: begin
                        action <= ACT_DROP;
                    end
                    FS_SUSPECT: begin
                        if (dpi_hit) begin
                            action <= ACT_MIRROR; // DROP + 告警上送，简化为单一动作码 MIRROR 代表告警
                        end else begin
                            action <= ACT_RATE_LIMIT;
                        end
                    end
                    default: begin // FS_NEW, FS_ALLOWED
                        if (dpi_hit) begin
                            action            <= ACT_MIRROR;
                            flow_update_valid <= 1'b1;
                            flow_update_state <= FS_SUSPECT; // 首次命中，标记该流为可疑
                        end else begin
                            action <= ACT_FORWARD;
                        end
                    end
                endcase
            end
        end
    end

endmodule
