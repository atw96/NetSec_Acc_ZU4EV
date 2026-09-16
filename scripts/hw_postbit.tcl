################################################################################
# After new bitstream: program, L0 regression, MDIO ID, L2 PHY loopback
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root scripts hw_jtag.tcl]

set bit [file join $repo_root bitstream_output system_top.bit]
set ltx [file join $repo_root vivado_proj netsec_accel_zu4ev.runs impl_1 system_top.ltx]

open_hw_manager
catch {connect_hw_server}
foreach t [get_hw_targets] { catch {set_property PARAM.FREQUENCY 1000000 $t} }
if {[catch {open_hw_target} err]} { puts "ERROR: $err"; exit 1 }
current_hw_device [get_hw_devices xczu4_0]
set_property PROGRAM.FILE $bit [current_hw_device]
if {[file exists $ltx]} { set_property PROBES.FILE $ltx [current_hw_device] }
if {[catch {program_hw_devices [current_hw_device]} perr]} { puts "WARN: $perr" }
catch {close_hw_target}
foreach t [get_hw_targets] { catch {set_property PARAM.FREQUENCY 1000000 $t} }
open_hw_target
current_hw_device [get_hw_devices xczu4_0]
if {[file exists $ltx]} { set_property PROBES.FILE $ltx [current_hw_device] }
after 2000
catch {refresh_hw_device [current_hw_device]}
if {[llength [get_hw_axis -quiet]] == 0} { puts "ERROR: no hw_axi"; exit 3 }

puts "===== L0 regression ====="
nsec_l0_test

puts "===== MDIO PHY ID ====="
nsec_mdio_id 1
puts "STATUS after ID [nsec_rd 0x04]"

puts "===== L2 PHY loopback ====="
nsec_l2_test

puts "===== L3 monitor (no PC traffic here) ====="
nsec_l3_monitor

puts "INFO: hw_postbit done"
exit 0
