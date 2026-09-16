################################################################################
# Create 1-lane GTH Wizard @ 1.25G / 125 MHz refclk / loopback port
# Factory path: gt_test uses gtwizard_ultrascale + PRBS; we use 1 lane (X0Y4)
#   and loopback_in = 3'b010 (near-end PMA) because no optical module is fitted.
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set proj_xpr  [file join $repo_root vivado_proj netsec_accel_zu4ev.xpr]
if {[current_project -quiet] eq ""} {
    if {![file exists $proj_xpr]} { error "No project. Run create_project.tcl first." }
    open_project $proj_xpr
}

if {[llength [get_ips -quiet gt_sfp_prbs]] == 0} {
    create_ip -name gtwizard_ultrascale -vendor xilinx.com -library ip -module_name gt_sfp_prbs
}

# Order matters: line-rate first, else 16-bit / 100 MHz freerun are illegal.
set ip [get_ips gt_sfp_prbs]
set_property -dict [list \
    CONFIG.GT_TYPE {GTH} \
    CONFIG.CHANNEL_ENABLE {X0Y4} \
    CONFIG.TX_MASTER_CHANNEL {X0Y4} \
    CONFIG.RX_MASTER_CHANNEL {X0Y4} \
    CONFIG.TX_LINE_RATE {1.25} \
    CONFIG.RX_LINE_RATE {1.25} \
    CONFIG.TX_REFCLK_FREQUENCY {125} \
    CONFIG.RX_REFCLK_FREQUENCY {125} \
    CONFIG.TX_PLL_TYPE {QPLL1} \
    CONFIG.RX_PLL_TYPE {QPLL1} \
    CONFIG.TX_REFCLK_SOURCE {X0Y4 clk1} \
    CONFIG.RX_REFCLK_SOURCE {X0Y4 clk1} \
] $ip
set_property -dict [list \
    CONFIG.TX_DATA_ENCODING {RAW} \
    CONFIG.RX_DATA_DECODING {RAW} \
] $ip
set_property -dict [list \
    CONFIG.TX_USER_DATA_WIDTH {16} \
    CONFIG.RX_USER_DATA_WIDTH {16} \
    CONFIG.TX_INT_DATA_WIDTH {16} \
    CONFIG.RX_INT_DATA_WIDTH {16} \
    CONFIG.FREERUN_FREQUENCY {50} \
    CONFIG.LOCATE_COMMON {CORE} \
    CONFIG.LOCATE_RESET_CONTROLLER {CORE} \
    CONFIG.LOCATE_TX_USER_CLOCKING {CORE} \
    CONFIG.LOCATE_RX_USER_CLOCKING {CORE} \
] $ip
if {[catch {set_property CONFIG.ENABLE_OPTIONAL_PORTS {loopback_in} $ip} e]} {
    puts "WARN: ENABLE_OPTIONAL_PORTS loopback_in: $e"
}

generate_target all [get_ips gt_sfp_prbs]

set wrap [file join $repo_root rtl mac_pcs gt_prbs_wrap.sv]
set top  [file join $repo_root rtl top system_top_sfp.sv]
foreach f [list $wrap $top] {
    if {[llength [get_files -quiet $f]] == 0} {
        add_files -norecurse $f
    }
}
set_property file_type SystemVerilog [get_files $wrap]
set_property file_type SystemVerilog [get_files $top]

puts "INFO: gt_sfp_prbs generated. Build L4 with scripts/build_sfp.tcl"
