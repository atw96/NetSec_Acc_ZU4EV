################################################################################
# Dual-lane GTH Wizard @ 10.3125G / QPLL0 / 64B66B gearbox
# SFP1=X0Y4, SFP2=X0Y5. Do not enable X0Y6/X0Y7 (PCIe).
#
# Vivado 2020.1 Wizard will not accept 10.3125G + exactly 125 MHz
# (10.3125/125 = 82.5). Closest legal refclk is 125.7621951 MHz.
# The board oscillator is SiT9121 125.000 MHz, so the serial rate is
# ~10.250 Gbps. Both SFP ports share that crystal, so fiber inter-port
# loopback still locks. XDC create_clock stays 8.000 ns (real 125 MHz).
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set proj_xpr  [file join $repo_root vivado_proj netsec_accel_zu4ev.xpr]
if {[current_project -quiet] eq ""} {
    if {![file exists $proj_xpr]} { error "No project. Run create_project.tcl first." }
    open_project $proj_xpr
}

if {[llength [get_ips -quiet gt_sfp_10g]] == 0} {
    create_ip -name gtwizard_ultrascale -vendor xilinx.com -library ip -module_name gt_sfp_10g
}

set ip [get_ips gt_sfp_10g]
set_property -dict [list \
    CONFIG.GT_TYPE {GTH} \
    CONFIG.CHANNEL_ENABLE {X0Y5 X0Y4} \
    CONFIG.TX_MASTER_CHANNEL {X0Y4} \
    CONFIG.RX_MASTER_CHANNEL {X0Y4} \
    CONFIG.TX_LINE_RATE {10.3125} \
    CONFIG.RX_LINE_RATE {10.3125} \
] $ip
# Legal Wizard value nearest the 125.000 MHz SiT9121
set_property -dict [list \
    CONFIG.TX_REFCLK_FREQUENCY {125.7621951} \
    CONFIG.RX_REFCLK_FREQUENCY {125.7621951} \
    CONFIG.TX_PLL_TYPE {QPLL0} \
    CONFIG.RX_PLL_TYPE {QPLL0} \
    CONFIG.TX_REFCLK_SOURCE {X0Y4 clk1 X0Y5 clk1} \
    CONFIG.RX_REFCLK_SOURCE {X0Y4 clk1 X0Y5 clk1} \
] $ip
set_property -dict [list \
    CONFIG.TX_DATA_ENCODING {64B66B} \
    CONFIG.RX_DATA_DECODING {64B66B} \
] $ip
set_property -dict [list \
    CONFIG.TX_USER_DATA_WIDTH {64} \
    CONFIG.RX_USER_DATA_WIDTH {64} \
    CONFIG.TX_INT_DATA_WIDTH {32} \
    CONFIG.RX_INT_DATA_WIDTH {32} \
    CONFIG.FREERUN_FREQUENCY {50} \
    CONFIG.LOCATE_COMMON {CORE} \
    CONFIG.LOCATE_RESET_CONTROLLER {CORE} \
    CONFIG.LOCATE_TX_USER_CLOCKING {CORE} \
    CONFIG.LOCATE_RX_USER_CLOCKING {CORE} \
] $ip

set opt {loopback_in rxgearboxslip_in txheader_in rxheader_out txsequence_in rxdatavalid_out rxheadervalid_out}
if {[catch {set_property CONFIG.ENABLE_OPTIONAL_PORTS $opt $ip} e]} {
    puts "WARN: ENABLE_OPTIONAL_PORTS: $e"
}

generate_target all [get_ips gt_sfp_10g]

set extras [list \
    [file join $repo_root rtl mac_pcs sfp10g_wrap.sv] \
    [file join $repo_root rtl top pkt_gen_10g.sv] \
    [file join $repo_root rtl top sfp10g_regs.sv] \
    [file join $repo_root rtl top system_top_sfp10g.sv] \
]
foreach f $extras {
    if {[file exists $f] && [llength [get_files -quiet $f]] == 0} {
        add_files -norecurse $f
        set_property file_type SystemVerilog [get_files $f]
    }
}

puts "INFO: gt_sfp_10g generated (10.3125G / Wizard refclk 125.7621951; crystal 125.000)."
puts "INFO: Build with scripts/build_sfp10g.tcl"
