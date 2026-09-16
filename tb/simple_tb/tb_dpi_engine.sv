`timescale 1ns/1ps
module tb_dpi_engine;

    logic clk = 0, rst_n = 0;
    logic data_valid, data_last;
    logic [7:0] data;
    logic hit_valid, ready;
    logic [3:0] hit_vector;
    int errors = 0;
    int byte_idx;

    u_dpi_matcher dut (
        .clk(clk), .rst_n(rst_n),
        .data_valid(data_valid), .data(data), .data_last(data_last),
        .pat0(32'h47455420), .pat1(32'h636d642e),
        .pat2(32'h53454c45), .pat3(32'h90909090),
        .ready(ready),
        .hit_valid(hit_valid), .hit_vector(hit_vector)
    );

    always #5 clk = ~clk;

    // 与 python_model/golden_model_dpi.py 中 test_stream 完全一致的字节流
    // (95 字节, hex 见该脚本输出)
    localparam int STREAM_LEN = 95;
    logic [7:0] stream [0:STREAM_LEN-1];

    // 期望命中: (byte_idx, pattern_idx) —— 来自 Python 黄金模型输出
    localparam int NUM_EXPECTED = 4;
    int exp_idx [0:NUM_EXPECTED-1];
    int exp_pat [0:NUM_EXPECTED-1];
    int exp_ptr = 0;

    initial begin
        exp_idx[0]=5;  exp_pat[0]=0;
        exp_idx[1]=41; exp_pat[1]=1;
        exp_idx[2]=65; exp_pat[2]=2;
        exp_idx[3]=84; exp_pat[3]=3;
    end

    // 将 hex 字符串解析为字节（与 golden model 输出的 stream hex 完全一致）
    function automatic byte hexpair_to_byte(input byte c_hi, input byte c_lo);
        byte v_hi, v_lo;
        v_hi = (c_hi >= "a") ? (c_hi - "a" + 8'd10) : (c_hi - "0");
        v_lo = (c_lo >= "a") ? (c_lo - "a" + 8'd10) : (c_lo - "0");
        hexpair_to_byte = {v_hi[3:0], v_lo[3:0]};
    endfunction

    initial begin
        string hexstr;
        hexstr = "4142474554202f696e6465782e68746d6c20485454502f312e310d0a72616e646f6d6a756e6b636d642e657865202f63206469726d6f72655f6a756e6b5f53454c454354202a2046524f4d207573657273909090907461696c5f6279746573";
        for (int i = 0; i < STREAM_LEN; i++) begin
            stream[i] = hexpair_to_byte(hexstr[2*i], hexstr[2*i+1]);
        end
    end

    initial begin
        data_valid=0; data=0; data_last=0;
        #12 rst_n = 1;
        repeat (30000) @(posedge clk);
        if (ready !== 1'b1) begin
            $display("FAIL: Aho-Corasick automaton not ready");
            $finish;
        end

        for (byte_idx = 0; byte_idx < STREAM_LEN; byte_idx++) begin
            data_valid = 1;
            data       = stream[byte_idx];
            data_last  = (byte_idx == STREAM_LEN-1);
            @(posedge clk);
            #1;
            if (hit_vector != 4'b0000) begin
                if (exp_ptr < NUM_EXPECTED && byte_idx == exp_idx[exp_ptr] &&
                    hit_vector == (4'b0001 << exp_pat[exp_ptr])) begin
                    $display("PASS: hit at byte_idx=%0d pattern=%0d (matches golden model)",
                              byte_idx, exp_pat[exp_ptr]);
                    exp_ptr++;
                end else begin
                    errors++;
                    $display("FAIL: unexpected hit_vector=%b at byte_idx=%0d", hit_vector, byte_idx);
                end
            end
        end
        @(negedge clk);
        data_valid = 0;

        if (exp_ptr != NUM_EXPECTED) begin
            errors++;
            $display("FAIL: only matched %0d/%0d expected hits", exp_ptr, NUM_EXPECTED);
        end

        if (errors == 0) $display("PASS: tb_dpi_engine all 4 expected hits matched Python golden model, no false positives.");
        else             $display("tb_dpi_engine: %0d FAILURE(S)", errors);
        $finish;
    end

endmodule
