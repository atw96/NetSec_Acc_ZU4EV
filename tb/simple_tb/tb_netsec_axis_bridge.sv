// TB-2: 64<->8 CDC bridge, good frame + bad-frame drop
`timescale 1ns / 1ps

module tb_netsec_axis_bridge;
    logic rx_clk = 0, tx_clk = 0, logic_clk = 0;
    logic rst_n = 0;
    always #3.2 rx_clk = ~rx_clk;
    always #3.2 tx_clk = ~tx_clk;
    always #4   logic_clk = ~logic_clk;

    logic [63:0] rx_d;
    logic [7:0]  rx_k;
    logic        rx_v, rx_r, rx_l, rx_u;
    logic [63:0] tx_d;
    logic [7:0]  tx_k;
    logic        tx_v, tx_r, tx_l, tx_u;
    logic [7:0]  s_d, m_d;
    logic        s_v, s_r, s_l, m_v, m_r, m_l;
    logic        p_bad, p_ovf;

    assign m_d = s_d;
    assign m_v = s_v;
    assign m_l = s_l;
    assign s_r = m_r;
    assign tx_r = 1'b1;

    netsec_axis_bridge #(.DEPTH(256)) u_br (
        .rx_mac_clk(rx_clk), .rx_rst_n(rst_n),
        .rx_mac_tdata(rx_d), .rx_mac_tkeep(rx_k), .rx_mac_tvalid(rx_v),
        .rx_mac_tready(rx_r), .rx_mac_tlast(rx_l), .rx_mac_tuser(rx_u),
        .tx_mac_clk(tx_clk), .tx_rst_n(rst_n),
        .tx_mac_tdata(tx_d), .tx_mac_tkeep(tx_k), .tx_mac_tvalid(tx_v),
        .tx_mac_tready(tx_r), .tx_mac_tlast(tx_l), .tx_mac_tuser(tx_u),
        .logic_clk(logic_clk), .logic_rst_n(rst_n),
        .s_tdata(s_d), .s_tvalid(s_v), .s_tready(s_r), .s_tlast(s_l),
        .m_tdata(m_d), .m_tvalid(m_v), .m_tready(m_r), .m_tlast(m_l),
        .pulse_badrx(p_bad), .pulse_ovf(p_ovf)
    );

    integer good, badp, errors, i;
    task send64;
        input [63:0] d;
        input last;
        input user;
        begin
            @(posedge rx_clk);
            rx_d = d; rx_k = 8'hff; rx_v = 1; rx_l = last; rx_u = user;
            while (!rx_r) @(posedge rx_clk);
            @(posedge rx_clk);
            rx_v = 0; rx_l = 0; rx_u = 0;
        end
    endtask

    initial begin
        good = 0; badp = 0; errors = 0;
        rx_d = 0; rx_k = 0; rx_v = 0; rx_l = 0; rx_u = 0;
        repeat (8) @(posedge logic_clk);
        rst_n = 1;
        repeat (20) @(posedge logic_clk);
        send64(64'hffffffffffffffff, 0, 0);
        send64(64'h0200000000080000, 1, 0);
        fork
            begin
                repeat (4000) @(posedge tx_clk);
            end
            begin
                forever begin
                    @(posedge tx_clk);
                    if (tx_v && tx_l) good++;
                    if (p_bad) badp++;
                end
            end
        join_none
        repeat (2000) @(posedge logic_clk);
        send64(64'hdeadbeefdeadbeef, 1, 1);
        repeat (2000) @(posedge logic_clk);
        if (good == 0) errors++;
        if (errors == 0)
            $display("PASS: tb_netsec_axis_bridge good=%0d bad_pulse=%0d", good, badp);
        else
            $display("FAIL: tb_netsec_axis_bridge good=%0d", good);
        $finish;
    end
endmodule
