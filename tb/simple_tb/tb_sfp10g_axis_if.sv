// TB-1: tx_src mux — BIST vs EXT 64-bit AXIS
`timescale 1ns / 1ps

module tb_sfp10g_axis_if;
    logic clk = 0, rst = 1, enable = 0;
    always #3.2 clk = ~clk;

    logic [1:0] tx_src = 2'b00;
    logic [63:0] gen_d, ext_d, axis_d;
    logic [7:0]  gen_k, ext_k, axis_k;
    logic        gen_v, gen_r, gen_l, gen_u, gen_p;
    logic        ext_v, ext_r, ext_l, ext_u;
    logic        axis_r = 1;

    pkt_gen_10g #(.PORT_ID(8'h01)) u_gen (
        .clk(clk), .rst(rst), .enable(enable & ~tx_src[0]),
        .m_tdata(gen_d), .m_tkeep(gen_k), .m_tvalid(gen_v), .m_tready(gen_r),
        .m_tlast(gen_l), .m_tuser(gen_u), .pulse_tx(gen_p)
    );

    assign axis_d = tx_src[0] ? ext_d : gen_d;
    assign axis_k = tx_src[0] ? ext_k : gen_k;
    assign axis_v = tx_src[0] ? ext_v : gen_v;
    assign axis_l = tx_src[0] ? ext_l : gen_l;
    assign gen_r  = tx_src[0] ? 1'b0 : axis_r;
    assign ext_r  = tx_src[0] ? axis_r : 1'b0;

    integer frames, errors;
    initial begin
        frames = 0; errors = 0;
        ext_d = 64'h0102030405060708; ext_k = 8'hff; ext_v = 0; ext_l = 0; ext_u = 0;
        repeat (4) @(posedge clk);
        rst = 0; enable = 1;
        repeat (4000) @(posedge clk);
        if (gen_p) frames++;
        repeat (8000) @(posedge clk);
        if (frames == 0 && !gen_v) begin
            // wait more for gap=1023
        end
        repeat (2000) @(posedge clk);
        if (!gen_v && frames == 0) begin
            $display("WARN: BIST still in gap");
        end
        // switch to EXT
        tx_src = 2'b01;
        @(posedge clk);
        ext_v = 1; ext_l = 1;
        @(posedge clk);
        if (!(axis_d === ext_d && axis_v === 1'b1 && axis_l === 1'b1))
            errors++;
        ext_v = 0; ext_l = 0;
        if (errors == 0)
            $display("PASS: tb_sfp10g_axis_if");
        else
            $display("FAIL: tb_sfp10g_axis_if errors=%0d", errors);
        $finish;
    end
endmodule
