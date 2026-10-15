// tb_dpi_match64.sv — pattern hit across a 64-bit beat boundary
`timescale 1ns / 1ps

module tb_dpi_match64;
    logic clk = 0, rst_n = 0;
    always #3.2 clk = ~clk;
    logic        v, last, endp, hit;
    logic [63:0] data;
    logic [7:0]  keep;
    logic [127:0] pats;
    logic [3:0]  phit;

    dpi_match64 #(.NUM_PAT(4), .ROM_PATTERNS(2)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(v), .data(data), .keep(keep), .in_last(last),
        .pats(pats), .frame_end_pulse(endp), .frame_hit(hit), .pat_hit(phit)
    );

    integer saw;
    initial begin
        v = 0; last = 0; keep = 8'hff; data = 0; saw = 0;
        pats = 128'h0;
        pats[31:0] = 32'h47455420;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(negedge clk);
        // byte6=0x47, byte7=0x45, next beat byte0=0x54, byte1=0x20
        v <= 1; data <= 64'h4547_ffff_ffff_ffff; last <= 0;
        @(negedge clk);
        data <= 64'h0000_0000_0000_2054; last <= 1;
        @(negedge clk);
        v <= 0; last <= 0;
        repeat (6) @(posedge clk);
        if (saw == 1)
            $display("PASS: tb_dpi_match64");
        else
            $display("FAIL: tb_dpi_match64 saw=%0d", saw);
        $finish;
    end
    always @(posedge clk) if (rst_n && endp && hit && phit[0]) saw <= saw + 1;
endmodule
