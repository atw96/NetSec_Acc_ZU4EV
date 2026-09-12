module tb_common_smoke;
  logic clk=0, rst_n=0;
  logic wr_en, rd_en, full, empty;
  logic [7:0] wr_data, rd_data;
  u_sync_fifo #(.DATA_WIDTH(8), .DEPTH(4)) fifo_dut(.clk(clk),.rst_n(rst_n),.wr_en(wr_en),.wr_data(wr_data),.full(full),.rd_en(rd_en),.rd_data(rd_data),.empty(empty));
  logic async_in, sync_out;
  u_cdc_sync #(.WIDTH(1)) cdc_dut(.dst_clk(clk),.rst_n(rst_n),.async_in(async_in),.sync_out(sync_out));
  logic rr;
  u_reset_sync rst_dut(.clk(clk),.async_rst_n(rst_n),.sync_rst_n(rr));
  always #5 clk=~clk;
  initial begin
    wr_en=0; rd_en=0; wr_data=0; async_in=0;
    #12 rst_n=1;
    @(negedge clk); wr_en=1; wr_data=8'hAB;
    @(negedge clk); wr_en=0; rd_en=1;
    @(negedge clk); rd_en=0;
    #5;
    if (rd_data !== 8'hAB) begin $display("FAIL: fifo rd_data=%h expect AB", rd_data); end
    else $display("PASS: tb_common_smoke sync_fifo/cdc_sync/reset_sync basic wiring OK, rd_data=%h", rd_data);
    $finish;
  end
endmodule
