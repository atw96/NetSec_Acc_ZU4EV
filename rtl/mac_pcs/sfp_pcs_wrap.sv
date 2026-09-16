// sfp_pcs_wrap.sv — SFP1 1000BASE-X PCS/PMA wrapper
// ENABLE=0: stub (no GT serial top ports).
// ENABLE=1: instantiate sfp_pcs_1g from scripts/create_sfp_pcs.tcl
// PG047: configuration_vector[1] = Loopback Control on classic PCS/PMA.
`timescale 1ns / 1ps

module sfp_pcs_wrap #(
    parameter bit ENABLE = 1'b0
) (
    input  logic        freerun_clk,
    input  logic        rst_n,
    input  logic        gt_loopback_en,

    input  logic        mgtrefclk_p,
    input  logic        mgtrefclk_n,
    input  logic        gthrxn_in,
    input  logic        gthrxp_in,
    output logic        gthtxn_out,
    output logic        gthtxp_out,

    output logic        sfp_tx_dis,
    input  logic        sfp1_los,
    input  logic        sfp2_los,

    output logic        sfp_link_status,
    output logic [15:0] sfp_status_vector
);

    assign sfp_tx_dis = 1'b0;

    generate
        if (!ENABLE) begin : g_stub
            assign gthtxn_out = 1'b0;
            assign gthtxp_out = 1'b0;
            assign sfp_link_status = 1'b0;
            assign sfp_status_vector = {14'd0, sfp2_los, sfp1_los};
            logic _u;
            assign _u = freerun_clk ^ rst_n ^ gt_loopback_en ^ mgtrefclk_p ^ mgtrefclk_n ^
                        gthrxn_in ^ gthrxp_in;
        end else begin : g_pcs
            logic [4:0]  configuration_vector;
            logic [15:0] status_vector;
            logic        signal_detect;

            assign configuration_vector = {3'b000, gt_loopback_en, 1'b0};
            assign signal_detect = ~sfp1_los | gt_loopback_en;

            sfp_pcs_1g u_pcs (
                .gtrefclk_p            (mgtrefclk_p),
                .gtrefclk_n            (mgtrefclk_n),
                .gtrefclk_out          (),
                .rxn                   (gthrxn_in),
                .rxp                   (gthrxp_in),
                .txn                   (gthtxn_out),
                .txp                   (gthtxp_out),
                .independent_clock_bufg(freerun_clk),
                .reset                 (~rst_n),
                .pma_reset_out         (),
                .mmcm_locked_out       (),
                .gtpowergood           (),
                .signal_detect         (signal_detect),
                .configuration_vector  (configuration_vector),
                .an_adv_config_vector  (16'd0),
                .an_restart_config     (1'b0),
                .an_interrupt          (),
                .status_vector         (status_vector),
                .gmii_txd              (8'h00),
                .gmii_tx_en            (1'b0),
                .gmii_tx_er            (1'b0),
                .gmii_rxd              (),
                .gmii_rx_dv            (),
                .gmii_rx_er            (),
                .gmii_isolate          (),
                .userclk_out           (),
                .userclk2_out          (),
                .rxuserclk_out         (),
                .rxuserclk2_out        (),
                .resetdone             ()
            );

            assign sfp_status_vector = status_vector;
            assign sfp_link_status   = status_vector[0];
        end
    endgenerate

endmodule
