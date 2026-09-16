################################################################################
# Program default bit, start PL PHY 1G AN, arm L3, then RELEASE JTAG.
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root scripts hw_jtag.tcl]

set bit [file join $repo_root bitstream_output system_top_rxdly.bit]
if {![file exists $bit]} { error "missing $bit" }

open_hw_manager
catch {connect_hw_server}
# AXI poke at 1 MHz; xsct fpga at 100 kHz if this program fails (DONE low)
foreach t [get_hw_targets] { catch {set_property PARAM.FREQUENCY 1000000 $t} }
if {[catch {open_hw_target} err]} { puts "ERROR: $err"; exit 1 }
catch {set_property PARAM.FREQUENCY 1000000 [current_hw_target]}
current_hw_device [get_hw_devices xczu4_0]
# Mismatched LTX can make program look like it ran while DONE stays 0
catch {set_property PROBES.FILE {} [current_hw_device]}
set_property PROGRAM.FILE $bit [current_hw_device]

set programmed 0
for {set i 1} {$i <= 3} {incr i} {
    puts "INFO: program attempt $i  TCK=[get_property PARAM.FREQUENCY [current_hw_target]]"
    if {![catch {program_hw_devices [current_hw_device]} perr]} {
        set programmed 1
        break
    }
    puts "WARN: program $i: $perr"
    after 2000
}
after 1500
catch {refresh_hw_device [current_hw_device]}
if {[llength [get_hw_axis -quiet]] == 0} {
    puts "ERROR: no hw_axi after program (programmed=$programmed)"
    exit 3
}

nsec_wr 0x00 0x3
after 5
nsec_phy_1g_an 1
nsec_wr 0x08 0x0
nsec_wr 0x00 0x1
nsec_dump
puts "INFO: L3 armed (LOOPBACK=0). Close JTAG for xsct."
catch {close_hw_target}
catch {disconnect_hw_server}
exit 0
