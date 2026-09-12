`timescale 1ns/1ps
module tb_ips_decision;

    logic clk = 0, rst_n = 0;
    logic valid, dpi_hit;
    logic [1:0] flow_state;
    logic out_valid, flow_update_valid;
    logic [1:0] action, flow_update_state;
    int errors = 0;

    u_ips_decision dut (
        .clk(clk), .rst_n(rst_n),
        .valid(valid), .flow_state(flow_state), .dpi_hit(dpi_hit),
        .out_valid(out_valid), .action(action),
        .flow_update_valid(flow_update_valid), .flow_update_state(flow_update_state)
    );

    always #5 clk = ~clk;

    task automatic check(input [1:0] fs, input logic hit, input [1:0] exp_action, input string name);
        @(negedge clk);
        valid = 1; flow_state = fs; dpi_hit = hit;
        @(negedge clk);
        valid = 0;
        #1;
        if (action !== exp_action) begin
            errors++;
            $display("FAIL[%s]: flow_state=%b dpi_hit=%b action=%b expect=%b", name, fs, hit, action, exp_action);
        end else begin
            $display("PASS[%s]: flow_state=%b dpi_hit=%b -> action=%b", name, fs, hit, action);
        end
    endtask

    initial begin
        valid=0; flow_state=0; dpi_hit=0;
        #12 rst_n = 1;

        // 穷举决策表 (见 06_ips_decision.md)
        check(2'b11, 1'b0, 2'b01, "blocked_nohit_DROP");
        check(2'b11, 1'b1, 2'b01, "blocked_hit_DROP");
        check(2'b10, 1'b1, 2'b11, "suspect_hit_MIRROR");
        check(2'b10, 1'b0, 2'b10, "suspect_nohit_RATE_LIMIT");
        check(2'b01, 1'b1, 2'b11, "allowed_hit_MIRROR");
        check(2'b01, 1'b0, 2'b00, "allowed_nohit_FORWARD");
        check(2'b00, 1'b1, 2'b11, "new_hit_MIRROR");
        check(2'b00, 1'b0, 2'b00, "new_nohit_FORWARD");

        if (errors == 0) $display("PASS: tb_ips_decision all 8 decision-table combinations passed.");
        else             $display("tb_ips_decision: %0d FAILURE(S)", errors);
        $finish;
    end

endmodule
