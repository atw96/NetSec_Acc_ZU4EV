// netsec_axis_bridge.sv — 64b GT MAC <-> 8b logic_clk CDC + width adapter
`timescale 1ns / 1ps

module netsec_axis_bridge #(
    parameter DEPTH = 1024
) (
    input  logic        rx_mac_clk,
    input  logic        rx_rst_n,
    input  logic [63:0] rx_mac_tdata,
    input  logic [7:0]  rx_mac_tkeep,
    input  logic        rx_mac_tvalid,
    output logic        rx_mac_tready,
    input  logic        rx_mac_tlast,
    input  logic        rx_mac_tuser,

    input  logic        tx_mac_clk,
    input  logic        tx_rst_n,
    output logic [63:0] tx_mac_tdata,
    output logic [7:0]  tx_mac_tkeep,
    output logic        tx_mac_tvalid,
    input  logic        tx_mac_tready,
    output logic        tx_mac_tlast,
    output logic        tx_mac_tuser,

    input  logic        logic_clk,
    input  logic        logic_rst_n,
    output logic [7:0]  s_tdata,
    output logic        s_tvalid,
    input  logic        s_tready,
    output logic        s_tlast,

    input  logic [7:0]  m_tdata,
    input  logic        m_tvalid,
    output logic        m_tready,
    input  logic        m_tlast,

    output logic        pulse_badrx,
    output logic        pulse_ovf
);

    logic rx_ovf, rx_bad, tx_ovf;
    logic [7:0] rx_keep_unused;
    logic       rx_user_unused;

    axis_async_fifo_adapter #(
        .DEPTH(DEPTH),
        .S_DATA_WIDTH(64),
        .S_KEEP_ENABLE(1),
        .S_KEEP_WIDTH(8),
        .M_DATA_WIDTH(8),
        .M_KEEP_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(1),
        .USER_BAD_FRAME_VALUE(1'b1),
        .USER_BAD_FRAME_MASK(1'b1),
        .DROP_OVERSIZE_FRAME(1),
        .DROP_BAD_FRAME(1),
        .DROP_WHEN_FULL(1)
    ) u_rx (
        .s_clk(rx_mac_clk),
        .s_rst(~rx_rst_n),
        .s_axis_tdata(rx_mac_tdata),
        .s_axis_tkeep(rx_mac_tkeep),
        .s_axis_tvalid(rx_mac_tvalid),
        .s_axis_tready(rx_mac_tready),
        .s_axis_tlast(rx_mac_tlast),
        .s_axis_tid(8'd0),
        .s_axis_tdest(8'd0),
        .s_axis_tuser(rx_mac_tuser),
        .m_clk(logic_clk),
        .m_rst(~logic_rst_n),
        .m_axis_tdata(s_tdata),
        .m_axis_tkeep(rx_keep_unused),
        .m_axis_tvalid(s_tvalid),
        .m_axis_tready(s_tready),
        .m_axis_tlast(s_tlast),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser(rx_user_unused),
        .s_pause_req(1'b0),
        .s_pause_ack(),
        .m_pause_req(1'b0),
        .m_pause_ack(),
        .s_status_depth(),
        .s_status_depth_commit(),
        .s_status_overflow(rx_ovf),
        .s_status_bad_frame(rx_bad),
        .s_status_good_frame(),
        .m_status_depth(),
        .m_status_depth_commit(),
        .m_status_overflow(),
        .m_status_bad_frame(),
        .m_status_good_frame()
    );

    axis_async_fifo_adapter #(
        .DEPTH(DEPTH),
        .S_DATA_WIDTH(8),
        .S_KEEP_ENABLE(0),
        .M_DATA_WIDTH(64),
        .M_KEEP_ENABLE(1),
        .M_KEEP_WIDTH(8),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(1),
        .DROP_OVERSIZE_FRAME(1),
        .DROP_BAD_FRAME(0),
        .DROP_WHEN_FULL(1)
    ) u_tx (
        .s_clk(logic_clk),
        .s_rst(~logic_rst_n),
        .s_axis_tdata(m_tdata),
        .s_axis_tkeep(1'b1),
        .s_axis_tvalid(m_tvalid),
        .s_axis_tready(m_tready),
        .s_axis_tlast(m_tlast),
        .s_axis_tid(8'd0),
        .s_axis_tdest(8'd0),
        .s_axis_tuser(1'b0),
        .m_clk(tx_mac_clk),
        .m_rst(~tx_rst_n),
        .m_axis_tdata(tx_mac_tdata),
        .m_axis_tkeep(tx_mac_tkeep),
        .m_axis_tvalid(tx_mac_tvalid),
        .m_axis_tready(tx_mac_tready),
        .m_axis_tlast(tx_mac_tlast),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser(tx_mac_tuser),
        .s_pause_req(1'b0),
        .s_pause_ack(),
        .m_pause_req(1'b0),
        .m_pause_ack(),
        .s_status_depth(),
        .s_status_depth_commit(),
        .s_status_overflow(tx_ovf),
        .s_status_bad_frame(),
        .s_status_good_frame(),
        .m_status_depth(),
        .m_status_depth_commit(),
        .m_status_overflow(),
        .m_status_bad_frame(),
        .m_status_good_frame()
    );

    assign pulse_badrx = rx_bad;
    assign pulse_ovf   = rx_ovf | tx_ovf;

    logic _u;
    assign _u = |rx_keep_unused | rx_user_unused;
endmodule
