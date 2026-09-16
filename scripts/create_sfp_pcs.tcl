################################################################################
# scripts/create_sfp_pcs.tcl
# Optional: generate gig_ethernet_pcs_pma (1000BASE-X) for SFP1 / GTH X0Y4
# Enable by setting NETSEC_ENABLE_SFP=1 and replacing sfp_pcs_wrap body.
#
# PG047 note: configuration_vector[1] is Loopback Control on classic PCS/PMA;
# confirm against the IP version shipped with Vivado 2020.1 before relying on it.
# Fallback: GT Wizard with loopback_in=3'b010 (Near-End PMA) + PRBS (factory gt_test).
################################################################################

set repo_root [file normalize [file join [file dirname [info script]] ..]]
set proj_xpr  [file join $repo_root vivado_proj netsec_accel_zu4ev.xpr]
if {[current_project -quiet] eq ""} {
    if {[file exists $proj_xpr]} {
        open_project $proj_xpr
    } else {
        error "No project. Run scripts/create_project.tcl first."
    }
}

set repo_root [file normalize [file join [file dirname [info script]] ..]]
set proj_xpr  [file join $repo_root vivado_proj netsec_accel_zu4ev.xpr]
if {[current_project -quiet] eq ""} {
    if {[file exists $proj_xpr]} {
        open_project $proj_xpr
    } else {
        error "No project. Run scripts/create_project.tcl first."
    }
}

if {[llength [get_ips -quiet sfp_pcs_1g]] == 0} {
    create_ip -name gig_ethernet_pcs_pma -vendor xilinx.com -library ip -version 16.2 \
        -module_name sfp_pcs_1g
}

set_property -dict [list \
    CONFIG.Standard {1000BASEX} \
    CONFIG.Management_Interface {false} \
    CONFIG.SupportLevel {Include_Shared_Logic_in_Core} \
    CONFIG.RefClkRate {125} \
    CONFIG.Physical_Interface {Transceiver} \
] [get_ips sfp_pcs_1g]

generate_target all [get_ips sfp_pcs_1g]

# Lock SFP1 to Bank224 Lane0 when the property exists
catch {set_property CONFIG.GT_Location {X0Y4} [get_ips sfp_pcs_1g]}

# Do not latch ENABLE=1 onto the fileset — default bitstream stays L0–L3.
# L4 rebuild: set_property generic {NETSEC_ENABLE_SFP=1'b1} + verilog_define NETSEC_SFP_PORTS
puts "INFO: sfp_pcs_1g generated. L4 opt-in: NETSEC_ENABLE_SFP=1 / NETSEC_SFP_PORTS."
puts "INFO: Fallback if loopback bit != PG047: factory gtwizard + loopback_in=3'b010."
