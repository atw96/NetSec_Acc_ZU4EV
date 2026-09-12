// packet_parser.sv
// L2(Ethernet)/L3(IPv4)/L4(TCP/UDP) 报文解析引擎
// 简化说明：仅支持不带 VLAN Tag 的以太网帧 + IPv4 + TCP/UDP，见 docs/module_spec/01_packet_parser.md
module u_packet_parser (
    input  logic        clk,
    input  logic        rst_n,

    // 上游输入（来自 MAC RX，字节流）
    input  logic        s_valid,
    input  logic [7:0]  s_data,
    input  logic        s_last,

    // 下游输出：字节流透传
    output logic        m_valid,
    output logic [7:0]  m_data,
    output logic        m_last,

    // 下游输出：解析结果总线（在 hdr_done 拉高时视为完整有效）
    output logic        hdr_done,
    output logic        ip_valid,
    output logic [31:0] src_ip,
    output logic [31:0] dst_ip,
    output logic [7:0]  protocol,
    output logic [3:0]  ip_hdr_len_words, // IHL, 单位 4 字节
    output logic        l4_valid,
    output logic [15:0] src_port,
    output logic [15:0] dst_port
);

    // 字节透传（组合，零延迟）
    assign m_valid = s_valid;
    assign m_data  = s_data;
    assign m_last  = s_last;

    logic [10:0] byte_cnt;      // 当前帧内字节索引，足够覆盖最大 1518B 帧
    logic [7:0]  eth_type_hi;
    logic [15:0] eth_type_full;
    logic        is_ip;
    logic [10:0] l4_start;      // L4 头起始的字节索引（相对帧首）

    assign eth_type_full = {eth_type_hi, s_data};

    // hdr_done: 组合脉冲，避免多重驱动冲突
    assign hdr_done = s_valid && (
                        (byte_cnt == 11'd13 && eth_type_full != 16'h0800) ||
                        (is_ip && byte_cnt == (l4_start + 11'd3) &&
                         (protocol == 8'd6 || protocol == 8'd17))
                       );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_cnt         <= '0;
            eth_type_hi      <= '0;
            is_ip            <= 1'b0;
            ip_valid         <= 1'b0;
            l4_valid         <= 1'b0;
            src_ip           <= '0;
            dst_ip           <= '0;
            protocol         <= '0;
            ip_hdr_len_words <= '0;
            l4_start         <= '0;
            src_port         <= '0;
            dst_port         <= '0;
        end else if (s_valid) begin

            // 帧内字节计数：last 字节处理完后，下一拍回到 0
            if (s_last) byte_cnt <= '0;
            else        byte_cnt <= byte_cnt + 1'b1;

            case (byte_cnt)
                11'd12: eth_type_hi <= s_data;
                11'd13: begin
                    is_ip    <= (eth_type_full == 16'h0800);
                    ip_valid <= (eth_type_full == 16'h0800);
                end
                11'd14: begin
                    ip_hdr_len_words <= s_data[3:0];
                    // l4_start = 14 (ETH) + IHL*4
                    l4_start <= 11'd14 + ({7'b0, s_data[3:0]} << 2);
                end
                11'd23: if (is_ip) protocol <= s_data;
                11'd26: if (is_ip) src_ip[31:24] <= s_data;
                11'd27: if (is_ip) src_ip[23:16] <= s_data;
                11'd28: if (is_ip) src_ip[15:8]  <= s_data;
                11'd29: if (is_ip) src_ip[7:0]   <= s_data;
                11'd30: if (is_ip) dst_ip[31:24] <= s_data;
                11'd31: if (is_ip) dst_ip[23:16] <= s_data;
                11'd32: if (is_ip) dst_ip[15:8]  <= s_data;
                11'd33: if (is_ip) dst_ip[7:0]   <= s_data;
                default: ;
            endcase

            if (is_ip) begin
                if (byte_cnt == l4_start)       src_port[15:8] <= s_data;
                else if (byte_cnt == l4_start+1) src_port[7:0]  <= s_data;
                else if (byte_cnt == l4_start+2) dst_port[15:8] <= s_data;
                else if (byte_cnt == l4_start+3) begin
                    dst_port[7:0] <= s_data;
                    l4_valid      <= (protocol == 8'd6 || protocol == 8'd17);
                end
            end
            // 说明：is_ip/ip_valid/l4_valid 等字段在 hdr_done 拉高时视为对"当前帧"有效，
            // 会在下一帧解析到对应字段时被自然覆盖，此处不做额外清零，
            // 以避免在 s_last 当拍误清掉刚刚解析完成的结果。
        end
    end

endmodule
