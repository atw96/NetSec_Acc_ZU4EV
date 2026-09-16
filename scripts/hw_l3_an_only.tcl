# Assume PL already programmed. AN + arm L3, then release JTAG.
set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root scripts hw_jtag.tcl]
open_hw_manager
catch {connect_hw_server}
foreach t [get_hw_targets] { catch {set_property PARAM.FREQUENCY 1000000 $t} }
if {[catch {open_hw_target} err]} { puts "ERROR: $err"; exit 1 }
catch {set_property PARAM.FREQUENCY 1000000 [current_hw_target]}
current_hw_device [get_hw_devices xczu4_0]
after 800
catch {refresh_hw_device [current_hw_device]}
if {[llength [get_hw_axis -quiet]] == 0} { puts "ERROR: no hw_axi"; exit 3 }
nsec_wr 0x00 0x3
after 5
nsec_phy_1g_an 1
nsec_wr 0x08 0x0
nsec_wr 0x00 0x1
nsec_dump
puts "INFO: L3 armed. Close JTAG for xsct."
catch {close_hw_target}
catch {disconnect_hw_server}
exit 0
