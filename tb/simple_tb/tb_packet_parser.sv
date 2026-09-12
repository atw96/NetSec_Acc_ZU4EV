`timescale 1ns/1ps
module tb_packet_parser;

    logic clk = 0;
    logic rst_n = 0;
    logic s_valid, s_last;
    logic [7:0] s_data;

    logic m_valid, m_last;
    logic [7:0] m_data;
    logic hdr_done, ip_valid, l4_valid;
    logic [31:0] src_ip, dst_ip;
    logic [7:0]  protocol;
    logic [3:0]  ip_hdr_len_words;
    logic [15:0] src_port, dst_port;

    int errors = 0;

    u_packet_parser dut (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_valid), .s_data(s_data), .s_last(s_last),
        .m_valid(m_valid), .m_data(m_data), .m_last(m_last),
        .hdr_done(hdr_done), .ip_valid(ip_valid),
        .src_ip(src_ip), .dst_ip(dst_ip), .protocol(protocol),
        .ip_hdr_len_words(ip_hdr_len_words), .l4_valid(l4_valid),
        .src_port(src_port), .dst_port(dst_port)
    );

    always #5 clk = ~clk; // 100MHz

    // 构造一帧: ETH(14B) + IPv4(20B, no options) + TCP(20B) + payload(5B) = 59B
    byte frame[0:58];

    initial begin
        // dst mac
        frame[0]=8'hAA; frame[1]=8'hAA; frame[2]=8'hAA; frame[3]=8'hAA; frame[4]=8'hAA; frame[5]=8'hAA;
        // src mac
        frame[6]=8'hBB; frame[7]=8'hBB; frame[8]=8'hBB; frame[9]=8'hBB; frame[10]=8'hBB; frame[11]=8'hBB;
        // ethertype 0x0800
        frame[12]=8'h08; frame[13]=8'h00;
        // IP header (20B)
        frame[14]=8'h45; frame[15]=8'h00;             // ver/ihl=5, dscp
        frame[16]=8'h00; frame[17]=8'h33;             // total length = 51
        frame[18]=8'h00; frame[19]=8'h01;             // id
        frame[20]=8'h00; frame[21]=8'h00;             // flags/frag
        frame[22]=8'h40; frame[23]=8'h06;             // ttl=64, proto=TCP(6)
        frame[24]=8'h00; frame[25]=8'h00;             // hdr checksum (dummy)
        frame[26]=8'hC0; frame[27]=8'hA8; frame[28]=8'h01; frame[29]=8'h0A; // src ip
        frame[30]=8'hC0; frame[31]=8'hA8; frame[32]=8'h01; frame[33]=8'h14; // dst ip
        // TCP header (20B)
        frame[34]=8'h1F; frame[35]=8'h90;             // src port 8080
        frame[36]=8'h00; frame[37]=8'h50;             // dst port 80
        frame[38]=8'h00; frame[39]=8'h00; frame[40]=8'h00; frame[41]=8'h01; // seq
        frame[42]=8'h00; frame[43]=8'h00; frame[44]=8'h00; frame[45]=8'h00; // ack
        frame[46]=8'h50; frame[47]=8'h18;             // data offset/flags
        frame[48]=8'h20; frame[49]=8'h00;             // window
        frame[50]=8'h00; frame[51]=8'h00;             // checksum
        frame[52]=8'h00; frame[53]=8'h00;             // urgent ptr
        // payload "HELLO"
        frame[54]=8'h48; frame[55]=8'h45; frame[56]=8'h4C; frame[57]=8'h4C; frame[58]=8'h4F;
    end

    task automatic send_frame();
        int i;
        for (i = 0; i <= 58; i++) begin
            @(negedge clk);
            s_valid = 1'b1;
            s_data  = frame[i];
            s_last  = (i == 58);
        end
        @(negedge clk);
        s_valid = 1'b0;
        s_last  = 1'b0;
    endtask

    initial begin
        s_valid = 0; s_data = 0; s_last = 0;
        #12 rst_n = 1;
        send_frame();
        #20;

        // 检查解析结果
        if (ip_valid !== 1'b1)                     begin errors++; $display("FAIL: ip_valid=%b expect 1", ip_valid); end
        if (protocol !== 8'd6)                      begin errors++; $display("FAIL: protocol=%0d expect 6(TCP)", protocol); end
        if (src_ip   !== 32'hC0A8010A)              begin errors++; $display("FAIL: src_ip=%h expect C0A8010A", src_ip); end
        if (dst_ip   !== 32'hC0A80114)              begin errors++; $display("FAIL: dst_ip=%h expect C0A80114", dst_ip); end
        if (src_port !== 16'd8080)                   begin errors++; $display("FAIL: src_port=%0d expect 8080", src_port); end
        if (dst_port !== 16'd80)                     begin errors++; $display("FAIL: dst_port=%0d expect 80", dst_port); end
        if (l4_valid !== 1'b1)                       begin errors++; $display("FAIL: l4_valid=%b expect 1", l4_valid); end
        if (ip_hdr_len_words !== 4'd5)               begin errors++; $display("FAIL: ihl=%0d expect 5", ip_hdr_len_words); end

        if (errors == 0)
            $display("PASS: tb_packet_parser all checks passed. src_ip=%h dst_ip=%h src_port=%0d dst_port=%0d proto=%0d",
                       src_ip, dst_ip, src_port, dst_port, protocol);
        else
            $display("tb_packet_parser: %0d FAILURE(S)", errors);

        $finish;
    end

endmodule
