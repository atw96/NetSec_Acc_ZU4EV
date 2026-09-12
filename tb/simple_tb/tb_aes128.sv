`timescale 1ns/1ps
module tb_aes128;

    logic clk = 0, rst_n = 0;
    logic start, done;
    logic [127:0] key, plaintext, ciphertext;
    int errors = 0;

    u_aes128_core dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .key(key), .plaintext(plaintext),
        .done(done), .ciphertext(ciphertext)
    );

    always #5 clk = ~clk;

    task automatic run_vec(input [127:0] k, input [127:0] pt, input [127:0] expected, input string name);
        @(negedge clk);
        key = k; plaintext = pt; start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait (done == 1'b1);
        @(negedge clk);
        if (ciphertext !== expected) begin
            errors++;
            $display("FAIL[%s]: ct=%032h expect %032h", name, ciphertext, expected);
        end else begin
            $display("PASS[%s]: ct=%032h", name, ciphertext);
        end
    endtask

    initial begin
        start = 0; key = 0; plaintext = 0;
        #12 rst_n = 1;

        // vec: fips197_appendix_b
        run_vec(128'h000102030405060708090a0b0c0d0e0f,
                128'h00112233445566778899aabbccddeeff,
                128'h69c4e0d86a7b0430d8cdb78070b4c55a,
                "fips197_appendix_b");

        // vec: all-zero
        run_vec(128'h00000000000000000000000000000000,
                128'h00000000000000000000000000000000,
                128'h66e94bd4ef8a2c3b884cfa59ca342b2e,
                "fips197_allzero");

        // vec: random_1
        run_vec(128'h2b7e151628aed2a6abf7158809cf4f3c,
                128'h6bc1bee22e409f96e93d7e117393172a,
                128'h3ad77bb40d7a3660a89ecaf32466ef97,
                "random_1");

        if (errors == 0) $display("PASS: tb_aes128 all NIST/PyCryptodome vectors matched.");
        else             $display("tb_aes128: %0d FAILURE(S)", errors);
        $finish;
    end

endmodule
