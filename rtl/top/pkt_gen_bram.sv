// pkt_gen_bram.sv — L0 self-test stimulus (two canned Ethernet frames)
`timescale 1ns / 1ps

module pkt_gen_bram (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       start,
    output logic [7:0] m_tdata,
    output logic       m_tvalid,
    input  logic       m_tready,
    output logic       m_tlast,
    output logic       busy
);

    (* rom_style = "block" *) logic [7:0] mem [0:159];

    initial begin
        integer i;
        for (i = 0; i < 160; i++) mem[i] = 8'h00;

        // Frame 0 @0 len=60
        mem[0]=8'hff; mem[1]=8'hff; mem[2]=8'hff; mem[3]=8'hff; mem[4]=8'hff; mem[5]=8'hff;
        mem[6]=8'h02; mem[7]=8'h00; mem[8]=8'h00; mem[9]=8'h00; mem[10]=8'h00; mem[11]=8'h01;
        mem[12]=8'h08; mem[13]=8'h00;
        mem[14]=8'h45; mem[15]=8'h00; mem[16]=8'h00; mem[17]=8'h28;
        mem[18]=8'h00; mem[19]=8'h01; mem[20]=8'h40; mem[21]=8'h00;
        mem[22]=8'h40; mem[23]=8'h06; mem[24]=8'h00; mem[25]=8'h00;
        mem[26]=8'hc0; mem[27]=8'ha8; mem[28]=8'h01; mem[29]=8'h02;
        mem[30]=8'hc0; mem[31]=8'ha8; mem[32]=8'h01; mem[33]=8'h64;
        mem[34]=8'h04; mem[35]=8'hd2; mem[36]=8'h00; mem[37]=8'h50;
        mem[38]=8'h00; mem[39]=8'h00; mem[40]=8'h00; mem[41]=8'h01;
        // bytes 42-57 = FIPS-197 Appendix B plaintext (AES datapath self-test)
        mem[42]=8'h00; mem[43]=8'h11; mem[44]=8'h22; mem[45]=8'h33;
        mem[46]=8'h44; mem[47]=8'h55; mem[48]=8'h66; mem[49]=8'h77;
        mem[50]=8'h88; mem[51]=8'h99; mem[52]=8'haa; mem[53]=8'hbb;
        mem[54]=8'hcc; mem[55]=8'hdd; mem[56]=8'hee; mem[57]=8'hff;
        mem[58]=8'h00; mem[59]=8'h00;

        // Frame 1 @80 len=64 — payload "GET /..."
        mem[80]=8'hff; mem[81]=8'hff; mem[82]=8'hff; mem[83]=8'hff; mem[84]=8'hff; mem[85]=8'hff;
        mem[86]=8'h02; mem[87]=8'h00; mem[88]=8'h00; mem[89]=8'h00; mem[90]=8'h00; mem[91]=8'h02;
        mem[92]=8'h08; mem[93]=8'h00;
        mem[94]=8'h45; mem[95]=8'h00; mem[96]=8'h00; mem[97]=8'h2c;
        mem[98]=8'h00; mem[99]=8'h02; mem[100]=8'h40; mem[101]=8'h00;
        mem[102]=8'h40; mem[103]=8'h06; mem[104]=8'h00; mem[105]=8'h00;
        mem[106]=8'h0a; mem[107]=8'h00; mem[108]=8'h00; mem[109]=8'h05;
        mem[110]=8'hc0; mem[111]=8'ha8; mem[112]=8'h01; mem[113]=8'h64;
        mem[114]=8'h04; mem[115]=8'hd2; mem[116]=8'h00; mem[117]=8'h50;
        mem[118]=8'h00; mem[119]=8'h00; mem[120]=8'h00; mem[121]=8'h01;
        mem[122]=8'h00; mem[123]=8'h00; mem[124]=8'h00; mem[125]=8'h00;
        mem[126]=8'h50; mem[127]=8'h02; mem[128]=8'h20; mem[129]=8'h00;
        mem[130]=8'h00; mem[131]=8'h00; mem[132]=8'h00; mem[133]=8'h00;
        mem[134]=8'h47; mem[135]=8'h45; mem[136]=8'h54; mem[137]=8'h20;
        mem[138]=8'h2f; mem[139]=8'h00; mem[140]=8'h00; mem[141]=8'h00;
        mem[142]=8'h00; mem[143]=8'h00;
    end

    logic        active;
    logic [1:0]  frame_sel;
    logic [7:0]  idx;
    logic [7:0]  cur_len;
    logic [7:0]  base;
    logic        start_d;

    assign busy = active;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active    <= 1'b0;
            frame_sel <= 2'd0;
            idx       <= '0;
            m_tvalid  <= 1'b0;
            m_tdata   <= '0;
            m_tlast   <= 1'b0;
            start_d   <= 1'b0;
            cur_len   <= 8'd60;
            base      <= 8'd0;
        end else begin
            start_d <= start;
            if (start && !start_d && !active) begin
                active    <= 1'b1;
                frame_sel <= 2'd0;
                idx       <= '0;
                base      <= 8'd0;
                cur_len   <= 8'd60;
                m_tvalid  <= 1'b0;
            end else if (active) begin
                if (!m_tvalid) begin
                    m_tvalid <= 1'b1;
                    m_tdata  <= mem[base + idx];
                    m_tlast  <= (idx == cur_len - 8'd1);
                end else if (m_tready) begin
                    if (idx == cur_len - 8'd1) begin
                        m_tvalid <= 1'b0;
                        m_tlast  <= 1'b0;
                        if (frame_sel == 2'd0) begin
                            frame_sel <= 2'd1;
                            idx       <= '0;
                            base      <= 8'd80;
                            cur_len   <= 8'd64;
                        end else begin
                            active <= 1'b0;
                        end
                    end else begin
                        idx      <= idx + 1'b1;
                        m_tdata  <= mem[base + idx + 8'd1];
                        m_tlast  <= (idx + 8'd1 == cur_len - 8'd1);
                    end
                end
            end else begin
                m_tvalid <= 1'b0;
                m_tlast  <= 1'b0;
            end
        end
    end

endmodule
