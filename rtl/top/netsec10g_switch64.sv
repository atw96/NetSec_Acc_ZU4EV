// netsec10g_switch64.sv — BIST / INLINE / LOOP / DISABLE over two 64-bit datapaths.
// INLINE crosses the ports (rx0 -> tx1, rx1 -> tx0). inj_start plays the two
// canned frames into port 0 (same payloads as pkt_gen_bram).
`timescale 1ns / 1ps

module netsec10g_switch64 #(
    parameter HASH_BITS    = 13,
    parameter NUM_PAT      = 16,
    parameter ROM_PATTERNS = 160,
    parameter AES_PIPE     = 1,
    parameter AES_LANES    = 3,
    parameter FIFO_BYTES   = 131072,
    parameter DLY          = 480
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic [1:0]            mode,
    input  logic [1:0]            dp_en,
    input  logic                  aes0_en,
    input  logic                  aes1_en,
    input  logic [127:0]          aes_key,
    input  logic [NUM_PAT*32-1:0] pats,
    input  logic                  inj_start,

    input  logic [63:0] rx0_tdata,
    input  logic [7:0]  rx0_tkeep,
    input  logic        rx0_tvalid,
    output logic        rx0_tready,
    input  logic        rx0_tlast,
    input  logic        rx0_tuser,
    input  logic [63:0] rx1_tdata,
    input  logic [7:0]  rx1_tkeep,
    input  logic        rx1_tvalid,
    output logic        rx1_tready,
    input  logic        rx1_tlast,
    input  logic        rx1_tuser,

    output logic [63:0] tx0_tdata,
    output logic [7:0]  tx0_tkeep,
    output logic        tx0_tvalid,
    input  logic        tx0_tready,
    output logic        tx0_tlast,
    output logic        tx0_tuser,
    output logic [63:0] tx1_tdata,
    output logic [7:0]  tx1_tkeep,
    output logic        tx1_tvalid,
    input  logic        tx1_tready,
    output logic        tx1_tlast,
    output logic        tx1_tuser,

    output logic [1:0]  last_action0,
    output logic [1:0]  last_action1,
    output logic        pulse_rx0, pulse_tx0, pulse_fwd0, pulse_drop0, pulse_mir0, pulse_dpi0,
    output logic        pulse_rx1, pulse_tx1, pulse_fwd1, pulse_drop1, pulse_mir1, pulse_dpi1,
    output logic        pulse_csum0, pulse_csum1,
    output logic        pulse_ovf0, pulse_ovf1,
    output logic        pulse_flow0, pulse_flow1,
    output logic [NUM_PAT-1:0] pulse_phit0, pulse_phit1,
    output logic [127:0] aes0_ct, aes1_ct,
    output logic         aes0_done, aes1_done,
    output logic         aes0_fold, aes1_fold
);
    localparam [1:0] MODE_INLINE = 2'd1;
    localparam [1:0] MODE_LOOP   = 2'd2;

    wire inspect = (mode == MODE_INLINE) || (mode == MODE_LOOP);

    logic [63:0] inj_d;
    logic [7:0]  inj_k;
    logic        inj_v, inj_r, inj_l, inj_u, inj_busy;
    pkt_gen_inj64 u_inj (
        .clk(clk), .rst_n(rst_n), .start(inj_start),
        .m_tdata(inj_d), .m_tkeep(inj_k), .m_tvalid(inj_v), .m_tready(inj_r),
        .m_tlast(inj_l), .m_tuser(inj_u), .busy(inj_busy)
    );

    logic [63:0] a_d, b_d, a_od, b_od;
    logic [7:0]  a_k, b_k, a_ok, b_ok;
    logic        a_v, a_r, a_l, a_u;
    logic        b_v, b_r, b_l, b_u;
    logic        a_ov, a_ol, a_ou, a_or;
    logic        b_ov, b_ol, b_ou, b_or;

    assign a_d = inj_busy ? inj_d : rx0_tdata;
    assign a_k = inj_busy ? inj_k : rx0_tkeep;
    assign a_v = inspect && (inj_busy ? inj_v : rx0_tvalid);
    assign a_l = inj_busy ? inj_l : rx0_tlast;
    assign a_u = inj_busy ? inj_u : rx0_tuser;
    assign inj_r      = inj_busy ? a_r : 1'b0;
    assign rx0_tready = inj_busy ? 1'b0 : (inspect ? a_r : 1'b1);

    assign b_d = rx1_tdata;
    assign b_k = rx1_tkeep;
    assign b_v = inspect && rx1_tvalid;
    assign b_l = rx1_tlast;
    assign b_u = rx1_tuser;
    assign rx1_tready = inspect ? b_r : 1'b1;

    logic [63:0] a_m_d, b_m_d;
    logic [7:0]  a_m_k, b_m_k;
    logic        a_m_v, a_m_r, a_m_l, a_m_u;
    logic        b_m_v, b_m_r, b_m_l, b_m_u;
    logic        a_r_dp, b_r_dp;

    always_comb begin
        a_od = a_d; a_ok = a_k; a_ov = a_v; a_ol = a_l; a_ou = a_u;
        b_od = b_d; b_ok = b_k; b_ov = b_v; b_ol = b_l; b_ou = b_u;
        a_m_r = 1'b1;
        b_m_r = 1'b1;
        if (dp_en[0]) begin
            a_od = a_m_d; a_ok = a_m_k; a_ov = a_m_v; a_ol = a_m_l; a_ou = a_m_u;
            a_m_r = a_or;
        end
        if (dp_en[1]) begin
            b_od = b_m_d; b_ok = b_m_k; b_ov = b_m_v; b_ol = b_m_l; b_ou = b_m_u;
            b_m_r = b_or;
        end
    end

    always_comb begin
        tx0_tdata = '0; tx0_tkeep = '0; tx0_tvalid = 1'b0; tx0_tlast = 1'b0; tx0_tuser = 1'b0;
        tx1_tdata = '0; tx1_tkeep = '0; tx1_tvalid = 1'b0; tx1_tlast = 1'b0; tx1_tuser = 1'b0;
        a_or = 1'b1;
        b_or = 1'b1;
        if (mode == MODE_INLINE) begin
            tx1_tdata = a_od; tx1_tkeep = a_ok; tx1_tvalid = a_ov; tx1_tlast = a_ol; tx1_tuser = a_ou;
            a_or = tx1_tready;
            tx0_tdata = b_od; tx0_tkeep = b_ok; tx0_tvalid = b_ov; tx0_tlast = b_ol; tx0_tuser = b_ou;
            b_or = tx0_tready;
        end else if (mode == MODE_LOOP) begin
            tx0_tdata = a_od; tx0_tkeep = a_ok; tx0_tvalid = a_ov; tx0_tlast = a_ol; tx0_tuser = a_ou;
            a_or = tx0_tready;
            tx1_tdata = b_od; tx1_tkeep = b_ok; tx1_tvalid = b_ov; tx1_tlast = b_ol; tx1_tuser = b_ou;
            b_or = tx1_tready;
        end
    end

    // Port 1 uses one fewer AES window than port 0 so six full pipes do not
    // fill the ZU4EV LUT fabric. AES_LANES=1 keeps both ports at one window.
    localparam integer AES_LANES_B = (AES_LANES > 1) ? (AES_LANES - 1) : AES_LANES;

    netsec_dp64 #(
        .HASH_BITS(HASH_BITS), .NUM_PAT(NUM_PAT), .ROM_PATTERNS(ROM_PATTERNS),
        .AES_PIPE(AES_PIPE), .AES_LANES(AES_LANES), .FIFO_BYTES(FIFO_BYTES),
        .DLY(DLY)
    ) u_dpa (
        .clk(clk), .rst_n(rst_n), .enable(inspect && dp_en[0]),
        .s_tdata(a_d), .s_tkeep(a_k), .s_tvalid(dp_en[0] ? a_v : 1'b0),
        .s_tready(a_r_dp), .s_tlast(a_l), .s_tuser(a_u),
        .m_tdata(a_m_d), .m_tkeep(a_m_k), .m_tvalid(a_m_v), .m_tready(a_m_r),
        .m_tlast(a_m_l), .m_tuser(a_m_u),
        .pats(pats), .aes_en(aes0_en), .aes_key(aes_key),
        .aes_ct(aes0_ct), .aes_done(aes0_done), .aes_fold_pulse(aes0_fold),
        .last_action(last_action0),
        .stat_rx(pulse_rx0), .stat_tx(pulse_tx0), .stat_fwd(pulse_fwd0),
        .stat_drop(pulse_drop0), .stat_mir(pulse_mir0), .stat_dpi(pulse_dpi0),
        .stat_csum(pulse_csum0), .stat_ovf(pulse_ovf0), .stat_flow(pulse_flow0),
        .stat_phit(pulse_phit0)
    );
    assign a_r = dp_en[0] ? a_r_dp : a_or;

    netsec_dp64 #(
        .HASH_BITS(HASH_BITS), .NUM_PAT(NUM_PAT), .ROM_PATTERNS(ROM_PATTERNS),
        .AES_PIPE(AES_PIPE), .AES_LANES(AES_LANES_B), .FIFO_BYTES(FIFO_BYTES),
        .DLY(DLY)
    ) u_dpb (
        .clk(clk), .rst_n(rst_n), .enable(inspect && dp_en[1]),
        .s_tdata(b_d), .s_tkeep(b_k), .s_tvalid(dp_en[1] ? b_v : 1'b0),
        .s_tready(b_r_dp), .s_tlast(b_l), .s_tuser(b_u),
        .m_tdata(b_m_d), .m_tkeep(b_m_k), .m_tvalid(b_m_v), .m_tready(b_m_r),
        .m_tlast(b_m_l), .m_tuser(b_m_u),
        .pats(pats), .aes_en(aes1_en), .aes_key(aes_key),
        .aes_ct(aes1_ct), .aes_done(aes1_done), .aes_fold_pulse(aes1_fold),
        .last_action(last_action1),
        .stat_rx(pulse_rx1), .stat_tx(pulse_tx1), .stat_fwd(pulse_fwd1),
        .stat_drop(pulse_drop1), .stat_mir(pulse_mir1), .stat_dpi(pulse_dpi1),
        .stat_csum(pulse_csum1), .stat_ovf(pulse_ovf1), .stat_flow(pulse_flow1),
        .stat_phit(pulse_phit1)
    );
    assign b_r = dp_en[1] ? b_r_dp : b_or;
endmodule
