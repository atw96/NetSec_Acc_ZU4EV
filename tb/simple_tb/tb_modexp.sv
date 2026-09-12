`timescale 1ns/1ps
module tb_modexp;

    logic clk = 0, rst_n = 0;
    logic start, done;
    logic [31:0] base_in, exp_in, mod_in, result;
    int errors = 0;

    u_modexp_demo #(.WIDTH(32)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .base_in(base_in), .exp_in(exp_in), .mod_in(mod_in),
        .done(done), .result(result)
    );

    always #5 clk = ~clk;

    task automatic run_vec(input [31:0] b, input [31:0] e, input [31:0] m, input [31:0] expected, input string name);
        @(negedge clk);
        base_in = b; exp_in = e; mod_in = m; start = 1;
        @(negedge clk);
        start = 0;
        wait (done == 1'b1);
        @(negedge clk);
        if (result !== expected) begin
            errors++;
            $display("FAIL[%s]: %0d^%0d mod %0d = %0d, expect %0d", name, b, e, m, result, expected);
        end else begin
            $display("PASS[%s]: %0d^%0d mod %0d = %0d", name, b, e, m, result);
        end
    endtask

    initial begin
        start=0; base_in=0; exp_in=0; mod_in=0;
        #12 rst_n = 1;

        // 期望值来自 Python: pow(base, exp, mod)
        run_vec(32'd7,    32'd560,   32'd561,   32'd1,     "vec0_fermat_pseudo");
        run_vec(32'd123,  32'd45,    32'd2027,  32'd668,   "vec1_small_prime_mod");
        run_vec(32'd2,    32'd10,    32'd1000,  32'd24,    "vec2_pow2");
        run_vec(32'd65535,32'd65537, 32'd104729,32'd48758, "vec3_larger");

        if (errors == 0) $display("PASS: tb_modexp all vectors matched Python pow() reference.");
        else             $display("tb_modexp: %0d FAILURE(S)", errors);
        $finish;
    end

endmodule
