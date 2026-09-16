// netsec_datapath.sv
// Single-clock store-and-forward inline path:
//   capture frame to FIFO while running parser/DPI
//   on frame end + flow lookup done -> IPS action
//   FORWARD/RATE_LIMIT: replay (optional MAC swap); DROP/MIRROR: drain
`timescale 1ns / 1ps

module netsec_datapath #(
    parameter FRAME_DEPTH     = 512,
    parameter ENABLE_MAC_SWAP = 1
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable,

    input  logic [7:0]  s_tdata,
    input  logic        s_tvalid,
    output logic        s_tready,
    input  logic        s_tlast,

    output logic [7:0]  m_tdata,
    output logic        m_tvalid,
    input  logic        m_tready,
    output logic        m_tlast,

    output logic        mirror_pulse,
    output logic [1:0]  last_action,

    output logic        stat_rx_frame,
    output logic        stat_tx_frame,
    output logic        stat_forward,
    output logic        stat_drop,
    output logic        stat_mirror,
    output logic        stat_dpi_hit,

    output logic        flow_update_valid,
    output logic [1:0]  flow_update_state,

    input  logic [31:0] dpi_pat0,
    input  logic [31:0] dpi_pat1,
    input  logic [31:0] dpi_pat2,
    input  logic [31:0] dpi_pat3,

    input  logic         aes_dp_en,
    input  logic [127:0] aes_key,
    output logic [127:0] aes_dp_ct,
    output logic         aes_dp_done
);

    localparam [1:0] ACT_FORWARD    = 2'b00;
    localparam [1:0] ACT_DROP       = 2'b01;
    localparam [1:0] ACT_RATE_LIMIT = 2'b10;
    localparam [1:0] ACT_MIRROR     = 2'b11;

    localparam integer AES_OFF = 42;

    typedef enum logic [2:0] {
        ST_RECV   = 3'd0,
        ST_DECIDE = 3'd1,
        ST_REPLAY = 3'd2,
        ST_DRAIN  = 3'd3,
        ST_AES    = 3'd4
    } state_t;

    state_t state;

    // Frame FIFO: {last, data}
    logic        fifo_full, fifo_empty;
    logic        fifo_wr, fifo_rd;
    logic [8:0]  fifo_wdata, fifo_rdata;

    logic        beat_in;
    logic        abort;
    assign beat_in  = enable && (state == ST_RECV) && s_tvalid && !fifo_full && !abort;
    assign s_tready = enable && ((state == ST_RECV && !fifo_full && !abort) || abort);
    assign fifo_wr  = beat_in;
    assign fifo_wdata = {s_tlast, s_tdata};

    u_sync_fifo #(.DATA_WIDTH(9), .DEPTH(FRAME_DEPTH), .FWFT(1)) u_frame_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(fifo_wr), .wr_data(fifo_wdata), .full(fifo_full),
        .rd_en(fifo_rd), .rd_data(fifo_rdata), .empty(fifo_empty)
    );

    // Parser
    logic hdr_done, ip_valid, l4_valid;
    logic [31:0] src_ip, dst_ip;
    logic [7:0]  protocol;
    logic [3:0]  ip_hdr_len_words;
    logic [15:0] src_port, dst_port;

    u_packet_parser u_parser (
        .clk(clk), .rst_n(rst_n),
        .s_valid(beat_in), .s_data(s_tdata), .s_last(s_tlast),
        .m_valid(), .m_data(), .m_last(),
        .hdr_done(hdr_done), .ip_valid(ip_valid),
        .src_ip(src_ip), .dst_ip(dst_ip), .protocol(protocol),
        .ip_hdr_len_words(ip_hdr_len_words),
        .l4_valid(l4_valid), .src_port(src_port), .dst_port(dst_port)
    );

    // Flow table
    logic        ft_req, ft_resp, ft_hit;
    logic [1:0]  ft_state;
    logic [5:0]  ft_idx; // HASH_BITS=4 + 2 way bits
    logic        ft_done;
    logic        ft_pending;
    logic [1:0]  cap_flow_state;
    logic [5:0]  cap_flow_idx;
    logic [31:0] cap_src_ip, cap_dst_ip;
    logic [15:0] cap_sport, cap_dport;
    logic [7:0]  cap_proto;

    u_flow_table #(.HASH_BITS(4)) u_ft (
        .clk(clk), .rst_n(rst_n),
        .req_valid(ft_req),
        .src_ip(cap_src_ip), .dst_ip(cap_dst_ip),
        .src_port(cap_sport), .dst_port(cap_dport), .protocol(cap_proto),
        .resp_valid(ft_resp), .hit(ft_hit), .flow_state(ft_state), .flow_idx(ft_idx),
        .update_valid(flow_update_valid),
        .update_idx(cap_flow_idx),
        .update_state(flow_update_state)
    );

    // DPI
    logic       dpi_hit_valid;
    logic [3:0] dpi_hit_vector;
    logic       cap_dpi_hit;

    u_dpi_matcher u_dpi (
        .clk(clk), .rst_n(rst_n),
        .data_valid(beat_in), .data(s_tdata), .data_last(s_tlast),
        .pat0(dpi_pat0), .pat1(dpi_pat1), .pat2(dpi_pat2), .pat3(dpi_pat3),
        .ready(),
        .hit_valid(dpi_hit_valid), .hit_vector(dpi_hit_vector)
    );

    logic         aes_go, aes_core_done;
    logic [127:0] aes_pt_cap, aes_ct_cap;
    logic         aes_have_block;

    u_aes128_core u_aes_dp (
        .clk(clk), .rst_n(rst_n),
        .start(aes_go), .key(aes_key), .plaintext(aes_pt_cap),
        .done(aes_core_done), .ciphertext(aes_ct_cap)
    );

    assign aes_dp_ct   = aes_ct_cap;
    assign aes_dp_done = aes_core_done;

    // IPS
    logic       ips_fire, ips_out_valid;
    logic [1:0] ips_action;
    logic       ips_fu_valid;
    logic [1:0] ips_fu_state;

    u_ips_decision u_ips (
        .clk(clk), .rst_n(rst_n),
        .valid(ips_fire),
        .flow_state(cap_flow_state),
        .dpi_hit(cap_dpi_hit),
        .out_valid(ips_out_valid),
        .action(ips_action),
        .flow_update_valid(ips_fu_valid),
        .flow_update_state(ips_fu_state)
    );

    assign flow_update_valid = ips_fu_valid;
    assign flow_update_state = ips_fu_state;

    // MAC header capture for swap
    logic [7:0] da [0:5];
    logic [7:0] sa [0:5];
    logic [10:0] rx_byte_idx;
    logic [10:0] tx_byte_idx;
    logic [1:0]  decided_action;
    logic        frame_ended;
    logic        need_decide;
    logic [1:0]  dpi_lag;

    assign last_action = decided_action;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_RECV;
            ft_req         <= 1'b0;
            ft_done        <= 1'b0;
            ft_pending     <= 1'b0;
            ips_fire       <= 1'b0;
            cap_dpi_hit    <= 1'b0;
            frame_ended    <= 1'b0;
            need_decide    <= 1'b0;
            dpi_lag        <= 2'd0;
            decided_action <= ACT_FORWARD;
            rx_byte_idx    <= '0;
            tx_byte_idx    <= '0;
            mirror_pulse   <= 1'b0;
            stat_rx_frame  <= 1'b0;
            stat_tx_frame  <= 1'b0;
            stat_forward   <= 1'b0;
            stat_drop      <= 1'b0;
            stat_mirror    <= 1'b0;
            stat_dpi_hit   <= 1'b0;
            cap_flow_state <= 2'b00;
            cap_flow_idx   <= '0;
            abort          <= 1'b0;
            aes_go         <= 1'b0;
            aes_have_block <= 1'b0;
            aes_pt_cap     <= '0;
            for (int i = 0; i < 6; i++) begin
                da[i] <= '0;
                sa[i] <= '0;
            end
        end else begin
            ft_req        <= 1'b0;
            ips_fire      <= 1'b0;
            mirror_pulse  <= 1'b0;
            stat_rx_frame <= 1'b0;
            stat_tx_frame <= 1'b0;
            stat_forward  <= 1'b0;
            stat_drop     <= 1'b0;
            stat_mirror   <= 1'b0;
            stat_dpi_hit  <= 1'b0;
            aes_go        <= 1'b0;

            if (dpi_hit_valid && (|dpi_hit_vector)) begin
                cap_dpi_hit  <= 1'b1;
                stat_dpi_hit <= 1'b1;
            end

            if (ft_resp) begin
                ft_done        <= 1'b1;
                ft_pending     <= 1'b0;
                cap_flow_state <= ft_hit ? ft_state : 2'b00;
                cap_flow_idx   <= ft_idx;
            end

            unique case (state)
                ST_RECV: begin
                    if (enable && !abort && fifo_full && s_tvalid && !s_tlast)
                        abort <= 1'b1;

                    if (abort && s_tvalid && s_tlast) begin
                        abort          <= 1'b0;
                        rx_byte_idx    <= '0;
                        need_decide    <= 1'b0;
                        ft_pending     <= 1'b0;
                        ft_done        <= 1'b0;
                        cap_dpi_hit    <= 1'b0;
                        aes_have_block <= 1'b0;
                        stat_drop      <= 1'b1;
                        state          <= ST_DRAIN;
                    end else if (beat_in) begin
                        if (rx_byte_idx < 11'd6)
                            da[rx_byte_idx] <= s_tdata;
                        else if (rx_byte_idx < 11'd12)
                            sa[rx_byte_idx - 11'd6] <= s_tdata;

                        if (rx_byte_idx >= AES_OFF[10:0] &&
                            rx_byte_idx < AES_OFF[10:0] + 11'd16) begin
                            aes_pt_cap <= {aes_pt_cap[119:0], s_tdata};
                            if (rx_byte_idx == AES_OFF[10:0] + 11'd15)
                                aes_have_block <= 1'b1;
                        end

                        if (s_tlast) begin
                            rx_byte_idx   <= '0;
                            frame_ended   <= 1'b1;
                            stat_rx_frame <= 1'b1;
                            need_decide   <= 1'b1;
                            dpi_lag       <= 2'd2;
                        end else begin
                            rx_byte_idx <= rx_byte_idx + 1'b1;
                        end
                    end

                    if (hdr_done) begin
                        cap_src_ip <= src_ip;
                        cap_dst_ip <= dst_ip;
                        cap_sport  <= src_port;
                        cap_dport  <= dst_port;
                        cap_proto  <= protocol;
                        ft_req     <= 1'b1;
                        ft_pending <= 1'b1;
                        ft_done    <= 1'b0;
                    end

                    // Decide after frame end, flow lookup, and DPI registered hit
                    if (need_decide && dpi_lag != 2'd0)
                        dpi_lag <= dpi_lag - 2'd1;
                    else if (need_decide && dpi_lag == 2'd0 && !ft_pending) begin
                        if (!ft_done)
                            cap_flow_state <= 2'b00;
                        ips_fire    <= 1'b1;
                        need_decide <= 1'b0;
                        state       <= ST_DECIDE;
                    end
                end

                ST_DECIDE: begin
                    if (ips_out_valid) begin
                        decided_action <= ips_action;
                        unique case (ips_action)
                            ACT_FORWARD, ACT_RATE_LIMIT: begin
                                stat_forward <= 1'b1;
                                tx_byte_idx  <= '0;
                                if (aes_dp_en && aes_have_block) begin
                                    aes_go <= 1'b1;
                                    state  <= ST_AES;
                                end else begin
                                    state <= ST_REPLAY;
                                end
                            end
                            ACT_MIRROR: begin
                                stat_mirror  <= 1'b1;
                                mirror_pulse <= 1'b1;
                                state        <= ST_DRAIN;
                            end
                            default: begin
                                stat_drop <= 1'b1;
                                state     <= ST_DRAIN;
                            end
                        endcase
                    end
                end

                ST_AES: begin
                    if (aes_core_done) begin
                        tx_byte_idx <= '0;
                        state       <= ST_REPLAY;
                    end
                end

                ST_REPLAY: begin
                    if (m_tvalid && m_tready) begin
                        tx_byte_idx <= tx_byte_idx + 1'b1;
                        if (m_tlast) begin
                            stat_tx_frame <= 1'b1;
                            frame_ended   <= 1'b0;
                            cap_dpi_hit   <= 1'b0;
                            ft_done       <= 1'b0;
                            tx_byte_idx   <= '0;
                            aes_have_block <= 1'b0;
                            state         <= ST_RECV;
                        end
                    end
                end

                ST_DRAIN: begin
                    if (fifo_empty || (fifo_rd && fifo_rdata[8])) begin
                        frame_ended <= 1'b0;
                        cap_dpi_hit <= 1'b0;
                        ft_done     <= 1'b0;
                        aes_have_block <= 1'b0;
                        state       <= ST_RECV;
                    end
                end
            endcase
        end
    end

    // TX / drain combo
    logic [7:0] raw_data;
    logic       raw_last;
    assign raw_data = fifo_rdata[7:0];
    assign raw_last = fifo_rdata[8];

    always_comb begin
        fifo_rd  = 1'b0;
        m_tvalid = 1'b0;
        m_tdata  = 8'h00;
        m_tlast  = 1'b0;

        if (state == ST_REPLAY && !fifo_empty) begin
            m_tvalid = 1'b1;
            m_tlast  = raw_last;
            if (ENABLE_MAC_SWAP != 0) begin
                unique case (tx_byte_idx)
                    11'd0: m_tdata = sa[0];
                    11'd1: m_tdata = sa[1];
                    11'd2: m_tdata = sa[2];
                    11'd3: m_tdata = sa[3];
                    11'd4: m_tdata = sa[4];
                    11'd5: m_tdata = sa[5];
                    11'd6: m_tdata = da[0];
                    11'd7: m_tdata = da[1];
                    11'd8: m_tdata = da[2];
                    11'd9: m_tdata = da[3];
                    11'd10: m_tdata = da[4];
                    11'd11: m_tdata = da[5];
                    default: m_tdata = raw_data;
                endcase
            end else begin
                m_tdata = raw_data;
            end
            fifo_rd = m_tready;
            if (aes_dp_en && aes_have_block &&
                tx_byte_idx >= AES_OFF[10:0] &&
                tx_byte_idx < AES_OFF[10:0] + 11'd16)
                m_tdata = aes_ct_cap[127-8*(tx_byte_idx-AES_OFF[10:0]) -: 8];
        end else if (state == ST_DRAIN && !fifo_empty) begin
            fifo_rd = 1'b1;
        end
    end

endmodule
