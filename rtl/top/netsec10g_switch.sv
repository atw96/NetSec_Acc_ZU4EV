// netsec10g_switch.sv — BIST/INLINE/LOOP/DISABLE + dual netsec_datapath
`timescale 1ns / 1ps

module netsec_ipv4_csum_chk (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       beat,
    input  logic [7:0] data,
    input  logic       last,
    output logic       pulse_err
);
    logic [10:0] idx;
    logic        is_ipv4, ihl5, armed;
    logic [16:0] acc;
    logic [16:0] tmp;
    logic [7:0]  hi;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx       <= '0;
            is_ipv4   <= 1'b0;
            ihl5      <= 1'b0;
            armed     <= 1'b0;
            acc       <= '0;
            hi        <= '0;
            pulse_err <= 1'b0;
        end else begin
            pulse_err <= 1'b0;
            if (beat) begin
                if (idx == 11'd12)
                    hi <= data;
                if (idx == 11'd13)
                    is_ipv4 <= ({hi, data} == 16'h0800);
                if (idx == 11'd14)
                    ihl5 <= (data[3:0] == 4'd5);
                if (is_ipv4 && idx >= 11'd14 && idx < 11'd34) begin
                    if (!idx[0])
                        hi <= data;
                    else begin
                        tmp = acc + {1'b0, hi, data};
                        if (tmp[16])
                            tmp = tmp[15:0] + 17'd1;
                        acc <= tmp;
                    end
                    if (idx == 11'd14)
                        armed <= 1'b1;
                end
                if (last) begin
                    if (armed && ihl5 && is_ipv4 && acc[15:0] != 16'hFFFF)
                        pulse_err <= 1'b1;
                    idx     <= '0;
                    is_ipv4 <= 1'b0;
                    ihl5    <= 1'b0;
                    armed   <= 1'b0;
                    acc     <= '0;
                end else begin
                    idx <= idx + 1'b1;
                end
            end
        end
    end
endmodule

module netsec10g_switch #(
    parameter FRAME_DEPTH = 4096
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [1:0]  mode,
    input  logic [1:0]  dp_en,
    input  logic        aes_dp0_en,
    input  logic        aes_dp1_en,
    input  logic [127:0] aes_key,
    input  logic [31:0] dpi_pat0,
    input  logic [31:0] dpi_pat1,
    input  logic [31:0] dpi_pat2,
    input  logic [31:0] dpi_pat3,

    input  logic [7:0]  rx0_tdata,
    input  logic        rx0_tvalid,
    output logic        rx0_tready,
    input  logic        rx0_tlast,
    input  logic [7:0]  rx1_tdata,
    input  logic        rx1_tvalid,
    output logic        rx1_tready,
    input  logic        rx1_tlast,

    output logic [7:0]  tx0_tdata,
    output logic        tx0_tvalid,
    input  logic        tx0_tready,
    output logic        tx0_tlast,
    output logic [7:0]  tx1_tdata,
    output logic        tx1_tvalid,
    input  logic        tx1_tready,
    output logic        tx1_tlast,

    output logic [1:0]  last_action0,
    output logic [1:0]  last_action1,
    output logic        pulse_rx0,
    output logic        pulse_tx0,
    output logic        pulse_fwd0,
    output logic        pulse_drop0,
    output logic        pulse_mir0,
    output logic        pulse_dpi0,
    output logic        pulse_rx1,
    output logic        pulse_tx1,
    output logic        pulse_fwd1,
    output logic        pulse_drop1,
    output logic        pulse_mir1,
    output logic        pulse_dpi1,
    output logic        pulse_csum0,
    output logic        pulse_csum1,
    output logic [127:0] aes_dp0_ct,
    output logic        aes_dp0_done,
    output logic [127:0] aes_dp1_ct,
    output logic        aes_dp1_done
);

    localparam [1:0] MODE_BIST    = 2'd0;
    localparam [1:0] MODE_INLINE  = 2'd1;
    localparam [1:0] MODE_LOOP    = 2'd2;
    localparam [1:0] MODE_DISABLE = 2'd3;

    logic inspect;
    assign inspect = (mode == MODE_INLINE) || (mode == MODE_LOOP);

    logic [7:0] a_s_tdata, a_m_tdata, b_s_tdata, b_m_tdata;
    logic       a_s_tvalid, a_s_tready, a_s_tlast;
    logic       a_m_tvalid, a_m_tready, a_m_tlast;
    logic       b_s_tvalid, b_s_tready, b_s_tlast;
    logic       b_m_tvalid, b_m_tready, b_m_tlast;

    logic [7:0] a_in_tdata, b_in_tdata;
    logic       a_in_tvalid, a_in_tlast, a_in_tready;
    logic       b_in_tvalid, b_in_tlast, b_in_tready;

    assign a_in_tdata  = rx0_tdata;
    assign a_in_tvalid = inspect & rx0_tvalid;
    assign a_in_tlast  = rx0_tlast;
    assign b_in_tdata  = rx1_tdata;
    assign b_in_tvalid = inspect & rx1_tvalid;
    assign b_in_tlast  = rx1_tlast;
    assign rx0_tready  = inspect ? a_in_tready : 1'b1;
    assign rx1_tready  = inspect ? b_in_tready : 1'b1;

    logic [7:0] a_out_tdata, b_out_tdata;
    logic       a_out_tvalid, a_out_tlast, a_out_tready;
    logic       b_out_tvalid, b_out_tlast, b_out_tready;

    always_comb begin
        if (dp_en[0]) begin
            a_s_tdata   = a_in_tdata;
            a_s_tvalid  = a_in_tvalid;
            a_s_tlast   = a_in_tlast;
            a_in_tready = a_s_tready;
            a_out_tdata  = a_m_tdata;
            a_out_tvalid = a_m_tvalid;
            a_out_tlast  = a_m_tlast;
            a_m_tready   = a_out_tready;
        end else begin
            a_s_tdata   = 8'd0;
            a_s_tvalid  = 1'b0;
            a_s_tlast   = 1'b0;
            a_m_tready  = 1'b1;
            a_out_tdata  = a_in_tdata;
            a_out_tvalid = a_in_tvalid;
            a_out_tlast  = a_in_tlast;
            a_in_tready  = a_out_tready;
        end
        if (dp_en[1]) begin
            b_s_tdata   = b_in_tdata;
            b_s_tvalid  = b_in_tvalid;
            b_s_tlast   = b_in_tlast;
            b_in_tready = b_s_tready;
            b_out_tdata  = b_m_tdata;
            b_out_tvalid = b_m_tvalid;
            b_out_tlast  = b_m_tlast;
            b_m_tready   = b_out_tready;
        end else begin
            b_s_tdata   = 8'd0;
            b_s_tvalid  = 1'b0;
            b_s_tlast   = 1'b0;
            b_m_tready  = 1'b1;
            b_out_tdata  = b_in_tdata;
            b_out_tvalid = b_in_tvalid;
            b_out_tlast  = b_in_tlast;
            b_in_tready  = b_out_tready;
        end
    end

    always_comb begin
        tx0_tdata  = 8'd0;
        tx0_tvalid = 1'b0;
        tx0_tlast  = 1'b0;
        tx1_tdata  = 8'd0;
        tx1_tvalid = 1'b0;
        tx1_tlast  = 1'b0;
        a_out_tready = 1'b1;
        b_out_tready = 1'b1;
        unique case (mode)
            MODE_INLINE: begin
                tx1_tdata    = a_out_tdata;
                tx1_tvalid   = a_out_tvalid;
                tx1_tlast    = a_out_tlast;
                a_out_tready = tx1_tready;
                tx0_tdata    = b_out_tdata;
                tx0_tvalid   = b_out_tvalid;
                tx0_tlast    = b_out_tlast;
                b_out_tready = tx0_tready;
            end
            MODE_LOOP: begin
                tx0_tdata    = a_out_tdata;
                tx0_tvalid   = a_out_tvalid;
                tx0_tlast    = a_out_tlast;
                a_out_tready = tx0_tready;
                tx1_tdata    = b_out_tdata;
                tx1_tvalid   = b_out_tvalid;
                tx1_tlast    = b_out_tlast;
                b_out_tready = tx1_tready;
            end
            default: ;
        endcase
    end

    netsec_datapath #(.FRAME_DEPTH(FRAME_DEPTH), .ENABLE_MAC_SWAP(0)) u_dpa (
        .clk(clk), .rst_n(rst_n), .enable(inspect & dp_en[0]),
        .s_tdata(a_s_tdata), .s_tvalid(a_s_tvalid), .s_tready(a_s_tready), .s_tlast(a_s_tlast),
        .m_tdata(a_m_tdata), .m_tvalid(a_m_tvalid), .m_tready(a_m_tready), .m_tlast(a_m_tlast),
        .mirror_pulse(), .last_action(last_action0),
        .stat_rx_frame(pulse_rx0), .stat_tx_frame(pulse_tx0),
        .stat_forward(pulse_fwd0), .stat_drop(pulse_drop0),
        .stat_mirror(pulse_mir0), .stat_dpi_hit(pulse_dpi0),
        .flow_update_valid(), .flow_update_state(),
        .dpi_pat0(dpi_pat0), .dpi_pat1(dpi_pat1), .dpi_pat2(dpi_pat2), .dpi_pat3(dpi_pat3),
        .aes_dp_en(aes_dp0_en), .aes_key(aes_key),
        .aes_dp_ct(aes_dp0_ct), .aes_dp_done(aes_dp0_done)
    );

    netsec_datapath #(.FRAME_DEPTH(FRAME_DEPTH), .ENABLE_MAC_SWAP(0)) u_dpb (
        .clk(clk), .rst_n(rst_n), .enable(inspect & dp_en[1]),
        .s_tdata(b_s_tdata), .s_tvalid(b_s_tvalid), .s_tready(b_s_tready), .s_tlast(b_s_tlast),
        .m_tdata(b_m_tdata), .m_tvalid(b_m_tvalid), .m_tready(b_m_tready), .m_tlast(b_m_tlast),
        .mirror_pulse(), .last_action(last_action1),
        .stat_rx_frame(pulse_rx1), .stat_tx_frame(pulse_tx1),
        .stat_forward(pulse_fwd1), .stat_drop(pulse_drop1),
        .stat_mirror(pulse_mir1), .stat_dpi_hit(pulse_dpi1),
        .flow_update_valid(), .flow_update_state(),
        .dpi_pat0(dpi_pat0), .dpi_pat1(dpi_pat1), .dpi_pat2(dpi_pat2), .dpi_pat3(dpi_pat3),
        .aes_dp_en(aes_dp1_en), .aes_key(aes_key),
        .aes_dp_ct(aes_dp1_ct), .aes_dp_done(aes_dp1_done)
    );

    netsec_ipv4_csum_chk u_c0 (
        .clk(clk), .rst_n(rst_n),
        .beat(a_s_tvalid & a_s_tready), .data(a_s_tdata), .last(a_s_tlast),
        .pulse_err(pulse_csum0)
    );
    netsec_ipv4_csum_chk u_c1 (
        .clk(clk), .rst_n(rst_n),
        .beat(b_s_tvalid & b_s_tready), .data(b_s_tdata), .last(b_s_tlast),
        .pulse_err(pulse_csum1)
    );
endmodule
