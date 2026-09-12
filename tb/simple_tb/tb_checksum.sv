`timescale 1ns/1ps
module tb_checksum;

    logic clk = 0, rst_n = 0;
    logic start, data_valid, data_last;
    logic [15:0] data;
    logic checksum_valid;
    logic [15:0] checksum;
    int errors = 0;

    u_checksum_rfc1071 dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .data_valid(data_valid), .data(data), .data_last(data_last),
        .checksum_valid(checksum_valid), .checksum(checksum)
    );

    always #5 clk = ~clk;

    logic [15:0] mem [0:31];
    int idx, len;

    task automatic feed_and_check(input logic [15:0] expected, input string name);
        int i;
        @(negedge clk); start = 1; data_valid = 0; data_last = 0;
        @(negedge clk); start = 0;
        for (i = 0; i < len; i++) begin
            @(negedge clk);
            data_valid = 1;
            data       = mem[i];
            data_last  = (i == len-1);
        end
        @(negedge clk);
        data_valid = 0; data_last = 0;
        wait (checksum_valid == 1'b1);
        @(negedge clk);
        if (checksum !== expected) begin
            errors++;
            $display("FAIL[%s]: checksum=0x%04h expect 0x%04h", name, checksum, expected);
        end else begin
            $display("PASS[%s]: checksum=0x%04h", name, checksum);
        end
    endtask

    initial begin
        start=0; data_valid=0; data_last=0; data=0;
        #12 rst_n = 1;

        // vec0: IPv4 header words
        len = 10;
        mem[0]=16'h4500; mem[1]=16'h003C; mem[2]=16'h1C46; mem[3]=16'h4000; mem[4]=16'h4006;
        mem[5]=16'hB1E6; mem[6]=16'hC0A8; mem[7]=16'h0001; mem[8]=16'hC0A8; mem[9]=16'h00C7;
        feed_and_check(16'hEA76, "vec0_ipv4hdr");

        // vec1: simple
        len = 4;
        mem[0]=16'h0001; mem[1]=16'h0203; mem[2]=16'h0405; mem[3]=16'h0607;
        feed_and_check(16'hF3EF, "vec1_simple");

        // vec2: ascii string
        len = 13;
        mem[0]=16'h4845; mem[1]=16'h4C4C; mem[2]=16'h4F2C; mem[3]=16'h204E; mem[4]=16'h4554;
        mem[5]=16'h5345; mem[6]=16'h432D; mem[7]=16'h4143; mem[8]=16'h4345; mem[9]=16'h4C2D;
        mem[10]=16'h5A55; mem[11]=16'h3445; mem[12]=16'h5621;
        feed_and_check(16'h6ABB, "vec2_string");

        if (errors == 0) $display("PASS: tb_checksum all vectors matched Python golden model.");
        else             $display("tb_checksum: %0d FAILURE(S)", errors);
        $finish;
    end

endmodule
