// netsec_dp64.sv — 64-bit store-and-forward inspection at line rate.
// Header parse, 4-byte DPI, URAM flow table and IPS all finish before the
// delayed tlast is committed. DROP/MIRROR set tuser so the frame FIFO discards
// the frame; FORWARD/RATE_LIMIT pass it through.
`timescale 1ns / 1ps

module netsec_dp64 #(
    parameter HASH_BITS    = 13,
    parameter NUM_PAT      = 16,
    parameter ROM_PATTERNS = 160,
    parameter AES_PIPE     = 1,
    parameter AES_LANES    = 3,
    parameter FIFO_BYTES   = 131072,
    parameter DLY          = 480
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   enable,
    input  logic [63:0]            s_tdata,
    input  logic [7:0]             s_tkeep,
    input  logic                   s_tvalid,
    output logic                   s_tready,
    input  logic                   s_tlast,
    input  logic                   s_tuser,
    output logic [63:0]            m_tdata,
    output logic [7:0]             m_tkeep,
    output logic                   m_tvalid,
    input  logic                   m_tready,
    output logic                   m_tlast,
    output logic                   m_tuser,
    input  logic [NUM_PAT*32-1:0]  pats,
    input  logic                   aes_en,
    input  logic [127:0]           aes_key,
    output logic [127:0]           aes_ct,
    output logic                   aes_done,
    output logic                   aes_fold_pulse,
    output logic [1:0]             last_action,
    output logic                   stat_rx,
    output logic                   stat_tx,
    output logic                   stat_fwd,
    output logic                   stat_drop,
    output logic                   stat_mir,
    output logic                   stat_dpi,
    output logic                   stat_csum,
    output logic                   stat_ovf,
    output logic                   stat_flow,
    output logic [NUM_PAT-1:0]     stat_phit
);
    localparam [1:0] ACT_FORWARD = 2'b00;
    localparam [1:0] ACT_DROP    = 2'b01;
    localparam [1:0] ACT_RATE    = 2'b10;
    localparam [1:0] ACT_MIRROR  = 2'b11;

    // One beat is four 16-bit words, summed in parallel. The running total
    // is folded on the next cycle so the carry chain stays off the 160 MHz path.
    function automatic [18:0] csum_beat(input logic [63:0] d);
        logic [16:0] a, b;
        a = {1'b0, d[7:0],   d[15:8]}  + {1'b0, d[23:16], d[31:24]};
        b = {1'b0, d[39:32], d[47:40]} + {1'b0, d[55:48], d[63:56]};
        csum_beat = {2'b0, a} + {2'b0, b};
    endfunction

    function automatic [16:0] csum_fold(input logic [16:0] acc, input logic [18:0] part);
        logic [19:0] s;
        logic [16:0] f;
        s = {3'b0, acc} + {1'b0, part};
        f = {1'b0, s[15:0]} + {13'd0, s[19:16]};
        if (f[16]) csum_fold = {1'b0, f[15:0]} + 17'd1;
        else       csum_fold = f;
    endfunction

    function automatic [7:0] lane_b(input logic [63:0] w, input integer n);
        lane_b = w[8*n +: 8];
    endfunction

    logic [10:0] byte_base;
    logic        is_ip, ihl5;
    logic [31:0] src_ip, dst_ip;
    logic [15:0] src_port, dst_port;
    logic [7:0]  protocol;
    logic [16:0] csum_acc;
    logic [18:0] csum_part, csum_part_q;
    logic        csum_hdr_q, csum_arm;
    logic        csum_ran, ft_sent;
    logic        dpi_done, flow_done, ips_arm, cap_dpi;
    logic [1:0]  cap_state;
    logic [HASH_BITS+1:0] cap_idx;

    wire accept = enable && s_tvalid && s_tready;

    logic        ft_req;
    logic [103:0] ft_key;
    logic        ft_resp, ft_hit, ft_alloc;
    logic [1:0]  ft_state;
    logic [HASH_BITS+1:0] ft_idx;
    logic        ips_fire, ips_out, ips_fu;
    logic [1:0]  ips_action, ips_fu_state;
    logic        frame_end, frame_hit;
    logic [NUM_PAT-1:0] pat_hit;

    dpi_match64 #(.NUM_PAT(NUM_PAT), .ROM_PATTERNS(ROM_PATTERNS)) u_dpi (
        .clk(clk), .rst_n(rst_n),
        .in_valid(accept), .data(s_tdata), .keep(s_tkeep), .in_last(s_tlast),
        .pats(pats),
        .frame_end_pulse(frame_end), .frame_hit(frame_hit), .pat_hit(pat_hit)
    );

    u_flow_table_uram #(.HASH_BITS(HASH_BITS)) u_ft (
        .clk(clk), .rst_n(rst_n),
        .req_valid(ft_req), .key(ft_key),
        .resp_valid(ft_resp), .hit(ft_hit), .alloc(ft_alloc),
        .flow_state(ft_state), .flow_idx(ft_idx),
        .update_valid(ips_fu), .update_idx(cap_idx), .update_state(ips_fu_state)
    );

    u_ips_decision u_ips (
        .clk(clk), .rst_n(rst_n),
        .valid(ips_fire), .flow_state(cap_state), .dpi_hit(cap_dpi),
        .out_valid(ips_out), .action(ips_action),
        .flow_update_valid(ips_fu), .flow_update_state(ips_fu_state)
    );

    // AES capture of 16-byte windows starting at byte 42.
    localparam integer AES_N = (AES_PIPE != 0) ? AES_LANES : 1;
    logic [127:0] cap_q [0:AES_N-1];
    logic [4:0]   cap_n [0:AES_N-1];
    logic [AES_N-1:0] aes_go;
    logic [127:0] ct_lane [0:AES_N-1];
    logic [AES_N-1:0] done_lane;

    generate
        if (AES_PIPE != 0) begin : g_pipe
            genvar ga;
            for (ga = 0; ga < AES_N; ga = ga + 1) begin : g_aes
                u_aes128_pipe u_aes (
                    .clk(clk), .rst_n(rst_n), .start(aes_go[ga]),
                    .key(aes_key), .plaintext(cap_q[ga]),
                    .done(done_lane[ga]), .ciphertext(ct_lane[ga])
                );
            end
        end else begin : g_iter
            u_aes128_core u_aes (
                .clk(clk), .rst_n(rst_n), .start(aes_go[0]),
                .key(aes_key), .plaintext(cap_q[0]),
                .done(done_lane[0]), .ciphertext(ct_lane[0])
            );
        end
    endgenerate

    assign aes_ct   = ct_lane[0];
    assign aes_done = done_lane[0];
    generate
        if (AES_N > 1) begin : g_fold
            logic [AES_N-1:1] fold_bit;
            for (genvar gk = 1; gk < AES_N; gk = gk + 1) begin : g_fb
                assign fold_bit[gk] = done_lane[gk] && (^ct_lane[gk]);
            end
            assign aes_fold_pulse = |fold_bit;
        end else begin : g_fold0
            assign aes_fold_pulse = 1'b0;
        end
    endgenerate

    // Delay pipe + action FIFO. Decision is a few cycles after tlast; the
    // pipe holds the frame long enough that the action is queued first.
    (* srl_style = "registers" *) logic               p_v [0:DLY-1];
    (* srl_style = "registers" *) logic               p_l [0:DLY-1];
    (* srl_style = "registers" *) logic               p_u [0:DLY-1];
    (* srl_style = "registers" *) logic [7:0]         p_k [0:DLY-1];
    (* srl_style = "registers" *) logic [63:0]        p_d [0:DLY-1];
    localparam integer AF_DEPTH = (DLY / 8) + 4;
    localparam integer AF_W     = (AF_DEPTH <= 2) ? 1 : $clog2(AF_DEPTH);
    logic               af_drop [0:AF_DEPTH-1];
    logic [AF_W-1:0]    af_w, af_r;
    logic [AF_W:0]      af_n;
    wire                af_empty = (af_n == 0);
    wire                head_drop = af_drop[af_r];

    logic               fifo_tready;
    wire                head_v = p_v[DLY-1];
    wire                hold = head_v && (!fifo_tready || (p_l[DLY-1] && af_empty));
    assign s_tready = !hold;

    wire                wr_valid = head_v && !hold;
    wire                wr_last  = p_l[DLY-1];
    wire                wr_user  = wr_last && (p_u[DLY-1] || head_drop);
    wire [63:0]         wr_data  = p_d[DLY-1];
    wire [7:0]          wr_keep  = p_k[DLY-1];

    logic m_ovf;
    axis_async_fifo #(
        .DEPTH(FIFO_BYTES),
        .DATA_WIDTH(64),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(8),
        .LAST_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(1),
        .USER_BAD_FRAME_VALUE(1'b1),
        .USER_BAD_FRAME_MASK(1'b1),
        .DROP_OVERSIZE_FRAME(1),
        .DROP_BAD_FRAME(1),
        .DROP_WHEN_FULL(1)
    ) u_ff (
        .s_clk(clk), .s_rst(~rst_n),
        .s_axis_tdata(wr_data), .s_axis_tkeep(wr_keep),
        .s_axis_tvalid(wr_valid), .s_axis_tready(fifo_tready),
        .s_axis_tlast(wr_last), .s_axis_tid(8'd0), .s_axis_tdest(8'd0),
        .s_axis_tuser(wr_user),
        .m_clk(clk), .m_rst(~rst_n),
        .m_axis_tdata(m_tdata), .m_axis_tkeep(m_tkeep),
        .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
        .m_axis_tlast(m_tlast), .m_axis_tid(), .m_axis_tdest(),
        .m_axis_tuser(m_tuser),
        .s_pause_req(1'b0), .s_pause_ack(),
        .m_pause_req(1'b0), .m_pause_ack(),
        .s_status_depth(), .s_status_depth_commit(),
        .s_status_overflow(), .s_status_bad_frame(), .s_status_good_frame(),
        .m_status_depth(), .m_status_depth_commit(),
        .m_status_overflow(m_ovf), .m_status_bad_frame(), .m_status_good_frame()
    );

    integer i, lane, al, bi;
    logic [127:0] cap_v [0:AES_N-1];
    logic [4:0]   n_v   [0:AES_N-1];
    logic [7:0]   bv;
    logic         ip_b, ihl_b;

    // Header words only. Byte 14-15 on beat 8, full beats at 16 and 24,
    // bytes 32-33 on beat 32. Lane 0 is tdata[7:0].
    always_comb begin
        csum_part = '0;
        if (accept && byte_base == 11'd8) begin
            if ({s_tdata[39:32], s_tdata[47:40]} == 16'h0800 && s_tdata[51:48] == 4'd5)
                csum_part = {3'b0, s_tdata[55:48], s_tdata[63:56]};
        end else if (accept && is_ip && ihl5 &&
                     (byte_base == 11'd16 || byte_base == 11'd24)) begin
            csum_part = csum_beat(s_tdata);
        end else if (accept && is_ip && ihl5 && byte_base == 11'd32) begin
            csum_part = {3'b0, s_tdata[7:0], s_tdata[15:8]};
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_base  <= '0;
            is_ip      <= 1'b0;
            ihl5       <= 1'b0;
            src_ip     <= '0;
            dst_ip     <= '0;
            src_port   <= '0;
            dst_port   <= '0;
            protocol   <= '0;
            csum_acc    <= '0;
            csum_part_q <= '0;
            csum_hdr_q  <= 1'b0;
            csum_arm    <= 1'b0;
            csum_ran    <= 1'b0;
            ft_sent    <= 1'b0;
            ft_req     <= 1'b0;
            ft_key     <= '0;
            dpi_done   <= 1'b0;
            flow_done  <= 1'b0;
            ips_arm    <= 1'b0;
            ips_fire   <= 1'b0;
            cap_dpi    <= 1'b0;
            cap_state  <= 2'b00;
            cap_idx    <= '0;
            last_action<= ACT_FORWARD;
            stat_rx    <= 1'b0;
            stat_tx    <= 1'b0;
            stat_fwd   <= 1'b0;
            stat_drop  <= 1'b0;
            stat_mir   <= 1'b0;
            stat_dpi   <= 1'b0;
            stat_csum  <= 1'b0;
            stat_ovf   <= 1'b0;
            stat_flow  <= 1'b0;
            stat_phit  <= '0;
            af_w       <= '0;
            af_r       <= '0;
            af_n       <= '0;
            for (i = 0; i < AF_DEPTH; i = i + 1) af_drop[i] <= 1'b0;
            for (i = 0; i < DLY; i = i + 1) begin
                p_v[i] <= 1'b0;
                p_l[i] <= 1'b0;
                p_u[i] <= 1'b0;
                p_k[i] <= '0;
                p_d[i] <= '0;
            end
            for (al = 0; al < AES_N; al = al + 1) begin
                cap_q[al]  <= '0;
                cap_n[al]  <= '0;
                aes_go[al] <= 1'b0;
            end
        end else begin
            ft_req    <= 1'b0;
            ips_fire  <= 1'b0;
            stat_rx   <= 1'b0;
            stat_tx   <= 1'b0;
            stat_fwd  <= 1'b0;
            stat_drop <= 1'b0;
            stat_mir  <= 1'b0;
            stat_dpi  <= 1'b0;
            stat_csum <= 1'b0;
            stat_ovf  <= m_ovf;
            stat_flow <= 1'b0;
            stat_phit <= '0;
            for (al = 0; al < AES_N; al = al + 1)
                aes_go[al] <= 1'b0;

            if (m_tvalid && m_tready && m_tlast)
                stat_tx <= 1'b1;

            if (accept && byte_base == 11'd0) begin
                ft_sent  <= 1'b0;
                csum_ran <= 1'b0;
                is_ip    <= 1'b0;
                ihl5     <= 1'b0;
            end

            ip_b  = 1'b0;
            ihl_b = 1'b0;
            if (accept && byte_base == 11'd8) begin
                bv    = lane_b(s_tdata, 6);
                ip_b  = ({lane_b(s_tdata, 4), lane_b(s_tdata, 5)} == 16'h0800);
                ihl_b = (bv[3:0] == 4'd5);
                is_ip <= ip_b;
                ihl5  <= ihl_b;
                if (ip_b && !ihl_b && !ft_sent) begin
                    ft_req  <= 1'b1;
                    ft_key  <= '0;
                    ft_sent <= 1'b1;
                end
                if (!ip_b && !ft_sent) begin
                    ft_req  <= 1'b1;
                    ft_key  <= '0;
                    ft_sent <= 1'b1;
                end
            end
            if (accept && is_ip && ihl5 && byte_base == 11'd16)
                protocol <= lane_b(s_tdata, 7);
            if (accept && is_ip && ihl5 && byte_base == 11'd24) begin
                src_ip <= {lane_b(s_tdata, 2), lane_b(s_tdata, 3),
                           lane_b(s_tdata, 4), lane_b(s_tdata, 5)};
                dst_ip[31:16] <= {lane_b(s_tdata, 6), lane_b(s_tdata, 7)};
            end
            if (accept && is_ip && ihl5 && byte_base == 11'd32) begin
                csum_ran <= 1'b1;
                dst_ip[15:0] <= {lane_b(s_tdata, 0), lane_b(s_tdata, 1)};
                src_port <= {lane_b(s_tdata, 2), lane_b(s_tdata, 3)};
                dst_port <= {lane_b(s_tdata, 4), lane_b(s_tdata, 5)};
                if (!ft_sent) begin
                    ft_req <= 1'b1;
                    ft_key <= {src_ip, dst_ip[31:16],
                               lane_b(s_tdata, 0), lane_b(s_tdata, 1),
                               lane_b(s_tdata, 2), lane_b(s_tdata, 3),
                               lane_b(s_tdata, 4), lane_b(s_tdata, 5),
                               protocol};
                    ft_sent <= 1'b1;
                end
            end
            csum_part_q <= csum_part;
            csum_hdr_q  <= accept && is_ip && ihl5 && (byte_base == 11'd32);
            if (accept && byte_base == 11'd0)
                csum_acc <= '0;
            else
                csum_acc <= csum_fold(csum_acc, csum_part_q);
            // The last header word is folded on the cycle after beat 32.
            // Sample one cycle later, when csum_acc holds the full sum.
            if (csum_arm) begin
                if (csum_acc[15:0] != 16'hFFFF)
                    stat_csum <= 1'b1;
                csum_arm <= 1'b0;
            end
            if (csum_hdr_q)
                csum_arm <= 1'b1;

            for (al = 0; al < AES_N; al = al + 1) begin
                cap_v[al] = cap_q[al];
                n_v[al]   = cap_n[al];
            end
            if (accept) begin
                for (lane = 0; lane < 8; lane = lane + 1) begin
                    if (s_tkeep[lane]) begin
                        bi = byte_base + lane;
                        bv = lane_b(s_tdata, lane);
                        for (al = 0; al < AES_N; al = al + 1) begin
                            if (bi >= 42 + 16*al && bi < 58 + 16*al && n_v[al] < 5'd16) begin
                                cap_v[al] = {cap_v[al][119:0], bv};
                                n_v[al]   = n_v[al] + 5'd1;
                            end
                        end
                    end
                end
            end
            for (al = 0; al < AES_N; al = al + 1) begin
                cap_q[al]  <= cap_v[al];
                aes_go[al] <= aes_en && (n_v[al] == 5'd16) && (cap_n[al] != 5'd16);
                cap_n[al]  <= (accept && s_tlast) ? 5'd0 : n_v[al];
            end

            if (accept) begin
                if (s_tlast) begin
                    byte_base <= '0;
                    stat_rx   <= 1'b1;
                end else
                    byte_base <= byte_base + 11'd8;
            end

            if (frame_end) begin
                dpi_done  <= 1'b1;
                cap_dpi   <= frame_hit;
                stat_dpi  <= frame_hit;
                stat_phit <= pat_hit;
            end
            if (ft_resp) begin
                flow_done <= 1'b1;
                cap_state <= ft_hit ? ft_state : 2'b00;
                cap_idx   <= ft_idx;
                stat_flow <= ft_alloc;
            end
            if (dpi_done && flow_done && !ips_arm) begin
                ips_fire <= 1'b1;
                ips_arm  <= 1'b1;
            end
            // frame_end and ft_resp can land on the same cycle the flags
            // are still low; fire on the raw pulses too.
            if (!ips_arm && ((dpi_done || frame_end) && (flow_done || ft_resp))) begin
                ips_fire <= 1'b1;
                ips_arm  <= 1'b1;
                if (frame_end) cap_dpi <= frame_hit;
                if (ft_resp)   cap_state <= ft_hit ? ft_state : 2'b00;
            end

            if (ips_out && af_n < AF_DEPTH) begin
                af_drop[af_w] <= (ips_action == ACT_DROP) || (ips_action == ACT_MIRROR);
                af_w          <= (af_w == AF_DEPTH-1) ? '0 : af_w + {{(AF_W-1){1'b0}}, 1'b1};
            end
            if (ips_out) begin
                last_action <= ips_action;
                dpi_done    <= 1'b0;
                flow_done   <= 1'b0;
                ips_arm     <= 1'b0;
                cap_dpi     <= 1'b0;
                case (ips_action)
                    ACT_MIRROR: stat_mir <= 1'b1;
                    ACT_DROP:   stat_drop <= 1'b1;
                    default:    stat_fwd <= 1'b1;
                endcase
            end

            if (wr_valid && wr_last && !af_empty)
                af_r <= (af_r == AF_DEPTH-1) ? '0 : af_r + {{(AF_W-1){1'b0}}, 1'b1};

            begin
                integer af_next;
                af_next = af_n;
                if (ips_out && af_n < AF_DEPTH)
                    af_next = af_next + 1;
                if (wr_valid && wr_last && !af_empty)
                    af_next = af_next - 1;
                af_n <= af_next[AF_W:0];
            end

            if (!hold) begin
                for (i = DLY-1; i > 0; i = i - 1) begin
                    p_v[i] <= p_v[i-1];
                    p_l[i] <= p_l[i-1];
                    p_u[i] <= p_u[i-1];
                    p_k[i] <= p_k[i-1];
                    p_d[i] <= p_d[i-1];
                end
                p_v[0] <= accept;
                p_l[0] <= s_tlast;
                p_u[0] <= s_tuser;
                p_k[0] <= s_tkeep;
                p_d[0] <= s_tdata;
            end
        end
    end
endmodule
