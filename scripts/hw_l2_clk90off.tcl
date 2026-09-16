################################################################################
# Program system_top_clk90off.bit and run L2 PHY loopback
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root scripts hw_jtag.tcl]

set bit [file join $repo_root bitstream_output system_top_clk90off.bit]
if {![file exists $bit]} { error "missing $bit" }
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

puts "===== clk90off L0 sanity ====="
nsec_l0_test
puts "===== clk90off L2 ====="
nsec_l2_test
after 100
puts "===== clk90off L2 second start (look for extra RX from RGMII) ====="
nsec_wr 0x00 0x101
after 80
nsec_dump
puts "INFO: extra MAC RX would make CNT_RX > 4 after two starts (2 gen + echo)"
puts "INFO: hw_l2_clk90off done"
exit 0
