`timescale 1ns/1ps
module tb_flow_table;

    logic clk = 0, rst_n = 0;
    logic req_valid;
    logic [31:0] src_ip, dst_ip;
    logic [15:0] src_port, dst_port;
    logic [7:0]  protocol;
    logic resp_valid, hit;
    logic [1:0] flow_state;
    logic [7:0] flow_idx;
    logic update_valid;
    logic [7:0] update_idx;
    logic [1:0] update_state;
    int errors = 0;

    u_flow_table #(.HASH_BITS(6), .WAYS(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .req_valid(req_valid), .src_ip(src_ip), .dst_ip(dst_ip),
        .src_port(src_port), .dst_port(dst_port), .protocol(protocol),
        .resp_valid(resp_valid), .hit(hit), .flow_state(flow_state), .flow_idx(flow_idx),
        .update_valid(update_valid), .update_idx(update_idx), .update_state(update_state)
    );

    always #5 clk = ~clk;

    task automatic lookup(input [31:0] sip, input [31:0] dip, input [15:0] sp, input [15:0] dp, input [7:0] proto);
        @(negedge clk);
        req_valid = 1; src_ip=sip; dst_ip=dip; src_port=sp; dst_port=dp; protocol=proto;
        @(negedge clk);
        req_valid = 0;
        wait(resp_valid == 1'b1);
        @(negedge clk); // 稳定
    endtask

    initial begin
        req_valid=0; src_ip=0; dst_ip=0; src_port=0; dst_port=0; protocol=0;
        update_valid=0; update_idx=0; update_state=0;
        #12 rst_n = 1;
        #10;

        // Flow A 第一次访问：应为新流(未命中)
        lookup(32'hC0A8_0101, 32'hC0A8_0102, 16'd12345, 16'd80, 8'd6);
        if (hit !== 1'b0) begin errors++; $display("FAIL: FlowA 1st lookup expect miss(new flow)"); end
        else $display("PASS: FlowA 1st lookup = new flow (miss), flow_idx=%0d", flow_idx);

        // Flow A 第二次访问：应命中，state仍为00(未被外部更新)
        lookup(32'hC0A8_0101, 32'hC0A8_0102, 16'd12345, 16'd80, 8'd6);
        if (hit !== 1'b1) begin errors++; $display("FAIL: FlowA 2nd lookup expect hit"); end
        else $display("PASS: FlowA 2nd lookup = hit, state=%0d", flow_state);

        // 外部(模拟IPS决策)将 FlowA 标记为已放行(01)
        @(negedge clk);
        update_valid = 1; update_idx = flow_idx; update_state = 2'b01;
        @(negedge clk);
        update_valid = 0;

        // Flow A 第三次访问：应命中且 state=01
        lookup(32'hC0A8_0101, 32'hC0A8_0102, 16'd12345, 16'd80, 8'd6);
        if (hit !== 1'b1 || flow_state !== 2'b01) begin
            errors++; $display("FAIL: FlowA 3rd lookup expect hit+state=01, got hit=%b state=%0d", hit, flow_state);
        end else $display("PASS: FlowA 3rd lookup = hit, state correctly updated to 01");

        // Flow B (不同五元组)：应为新流，且不应与 FlowA 混淆
        lookup(32'hC0A8_0101, 32'hC0A8_0103, 16'd12345, 16'd443, 8'd6);
        if (hit !== 1'b0) begin errors++; $display("FAIL: FlowB expect new flow(miss)"); end
        else $display("PASS: FlowB = new flow (miss), independent of FlowA");

        if (errors == 0) $display("PASS: tb_flow_table all checks passed.");
        else             $display("tb_flow_table: %0d FAILURE(S)", errors);
        $finish;
    end

endmodule
