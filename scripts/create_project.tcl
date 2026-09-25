################################################################################
# scripts/create_project.tcl
# Create Vivado 2020.1 project for NetSec-Accel-ZU4EV (part xczu4ev-sfvc784-1-i)
#
# Usage (from Vivado Tcl shell or batch):
#   vivado -mode batch -source scripts/create_project.tcl
################################################################################

set proj_name "netsec_accel_zu4ev"
set proj_dir  [file normalize [file join [file dirname [info script]] .. vivado_proj]]
set repo_root [file normalize [file join [file dirname [info script]] ..]]

puts "INFO: repo_root = $repo_root"
puts "INFO: proj_dir  = $proj_dir"

file mkdir $proj_dir
create_project $proj_name $proj_dir -part xczu4ev-sfvc784-1-i -force
set_property target_language Verilog [current_project]
set_property default_lib work [current_project]

# ---- RTL sources (order: packages first) ----
set files [list \
    [file join $repo_root rtl crypto aes aes_sbox_pkg.sv] \
    [file join $repo_root rtl common sync_fifo.sv] \
    [file join $repo_root rtl common cdc_sync.sv] \
    [file join $repo_root rtl packet_parser packet_parser.sv] \
    [file join $repo_root rtl flow_table flow_table.sv] \
    [file join $repo_root rtl tcpip_offload checksum_rfc1071.sv] \
    [file join $repo_root rtl dpi_engine dpi_matcher.sv] \
    [file join $repo_root rtl crypto aes aes128_core.sv] \
    [file join $repo_root rtl crypto modexp modexp_demo.sv] \
    [file join $repo_root rtl ips_decision ips_decision.sv] \
]

# verilog-ethernet slim vendor
set ve [file join $repo_root rtl mac_pcs third_party verilog-ethernet]
foreach f {
    rtl/lfsr.v
    rtl/iddr.v
    rtl/oddr.v
    rtl/ssio_ddr_in.v
    rtl/ssio_ddr_out.v
    rtl/rgmii_phy_if.v
    rtl/axis_gmii_rx.v
    rtl/axis_gmii_tx.v
    rtl/mac_ctrl_rx.v
    rtl/mac_ctrl_tx.v
    rtl/mac_pause_ctrl_rx.v
    rtl/mac_pause_ctrl_tx.v
    rtl/eth_mac_1g.v
    rtl/eth_mac_1g_rgmii.v
    rtl/eth_mac_1g_rgmii_fifo.v
    rtl/eth_mac_phy_10g.v
    rtl/eth_mac_phy_10g_rx.v
    rtl/eth_mac_phy_10g_tx.v
    rtl/eth_phy_10g.v
    rtl/eth_phy_10g_rx.v
    rtl/eth_phy_10g_tx.v
    rtl/eth_phy_10g_rx_if.v
    rtl/eth_phy_10g_tx_if.v
    rtl/eth_phy_10g_rx_ber_mon.v
    rtl/eth_phy_10g_rx_frame_sync.v
    rtl/xgmii_baser_dec_64.v
    rtl/xgmii_baser_enc_64.v
    rtl/axis_xgmii_rx_64.v
    rtl/axis_xgmii_tx_64.v
    rtl/axis_baser_rx_64.v
    rtl/axis_baser_tx_64.v
    rtl/eth_phy_10g_rx_watchdog.v
    lib/axis/rtl/sync_reset.v
    lib/axis/rtl/axis_adapter.v
    lib/axis/rtl/axis_async_fifo.v
    lib/axis/rtl/axis_async_fifo_adapter.v
} {
    lappend files [file join $ve $f]
}

lappend files \
    [file join $repo_root rtl mac_pcs rgmii_mac_wrap.sv] \
    [file join $repo_root rtl mac_pcs mdio_master.sv] \
    [file join $repo_root rtl mac_pcs sfp_pcs_wrap.sv] \
    [file join $repo_root rtl mac_pcs gt_prbs_wrap.sv] \
    [file join $repo_root rtl mac_pcs sfp10g_wrap.sv] \
    [file join $repo_root rtl top netsec_cdc.sv] \
    [file join $repo_root rtl top netsec_regs.sv] \
    [file join $repo_root rtl top pkt_gen_bram.sv] \
    [file join $repo_root rtl top pkt_gen_10g.sv] \
    [file join $repo_root rtl top sfp10g_regs.sv] \
    [file join $repo_root rtl top netsec_axis_bridge.sv] \
    [file join $repo_root rtl top netsec10g_switch.sv] \
    [file join $repo_root rtl top netsec_datapath.sv] \
    [file join $repo_root rtl top netsec_top.sv] \
    [file join $repo_root rtl top system_top.sv] \
    [file join $repo_root rtl top system_top_sfp.sv] \
    [file join $repo_root rtl top system_top_sfp10g.sv]

add_files -norecurse $files
set_property file_type SystemVerilog [get_files *.sv]
set_property top system_top [current_fileset]

# ---- Constraints ----
add_files -fileset constrs_1 -norecurse [list \
    [file join $repo_root constraints axu4ev_netsec.xdc] \
    [file join $repo_root constraints sfp_gth.xdc] \
    [file join $repo_root constraints timing_exceptions.xdc] \
    [file join $repo_root constraints debug_hub.xdc] \
]
set_property used_in_synthesis false [get_files [file join $repo_root constraints debug_hub.xdc]]

# ---- ILA IP ----
source [file join $repo_root scripts create_debug_cores.tcl]

# ---- Build BD (PS + jtag_axi + AXI to netsec) ----
source [file join $repo_root scripts create_bd.tcl]

# ---- Dual-lane 10G GT Wizard (X0Y4/X0Y5). Sourced again by build.tcl if missing. ----
source [file join $repo_root scripts create_gt_10g.tcl]
set_property verilog_define {NETSEC_SFP_PORTS} [current_fileset]
set_property generic {NETSEC_ENABLE_SFP=1'b0 NETSEC_ENABLE_SFP10G=1'b1 RGMII_TX_USE_CLK90=FALSE} [current_fileset]

puts "INFO: Project created (default top system_top includes dual-SFP 10G). Next: source scripts/build.tcl"
