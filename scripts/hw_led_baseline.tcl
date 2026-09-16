################################################################################
# Program clk90off and dump B0/STATUS so LED path can be judged.
# LED itself is visual (AE15, hb[24] ~1.5 Hz). Fabric alive if STATUS bit1=1.
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root scripts hw_jtag.tcl]

set bit [file join $repo_root bitstream_output system_top_clk90off.bit]
if {![file exists $bit]} { error "missing $bit" }

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
nsec_dump
puts "INFO: LED baseline programmed clk90off. Expect pl_led ~1.5 Hz if AE15 path OK."
puts "INFO: L4 will not use LED as pass criterion (register/IBERT only)."
exit 0
