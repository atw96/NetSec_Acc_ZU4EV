################################################################################
# After default rebuild: L0 then L2 regression (clk90off expected).
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root scripts hw_jtag.tcl]
set bit [file join $repo_root bitstream_output system_top.bit]
open_hw_manager
catch {connect_hw_server}
foreach t [get_hw_targets] { catch {set_property PARAM.FREQUENCY 1000000 $t} }
if {[catch {open_hw_target} err]} { puts "ERROR: $err"; exit 1 }
current_hw_device [get_hw_devices xczu4_0]
set_property PROGRAM.FILE $bit [current_hw_device]
if {[catch {program_hw_devices [current_hw_device]} perr]} { puts "WARN: $perr" }
catch {close_hw_target}
foreach t [get_hw_targets] { catch {set_property PARAM.FREQUENCY 1000000 $t} }
open_hw_target
current_hw_device [get_hw_devices xczu4_0]
after 1500
catch {refresh_hw_device [current_hw_device]}
if {[llength [get_hw_axis -quiet]] == 0} { puts "ERROR: no hw_axi"; exit 3 }
puts "===== L0 ====="
nsec_l0_test
puts "===== L2 ====="
nsec_l2_test
puts "INFO: hw_l0_l2_reg done"
exit 0
