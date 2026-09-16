################################################################################
# Program system_top_sfp.bit (L4 GT PRBS). No jtag_axi on this image.
# Pass: pl_led follows prbs_match after link; no PCS counters.
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $repo_root bitstream_output system_top_sfp.bit]
if {![file exists $bit]} { error "missing $bit — run scripts/build_sfp.tcl" }

open_hw_manager
catch {connect_hw_server}
foreach t [get_hw_targets] { catch {set_property PARAM.FREQUENCY 1000000 $t} }
if {[catch {open_hw_target} err]} { puts "ERROR: $err"; exit 1 }
current_hw_device [get_hw_devices xczu4_0]
set_property PROGRAM.FILE $bit [current_hw_device]
if {[catch {program_hw_devices [current_hw_device]} perr]} { puts "WARN: $perr" }
after 2000
catch {refresh_hw_device [current_hw_device]}
puts "INFO: programmed $bit"
puts "INFO: L4 image has no jtag_axi. Watch PL LED now: heartbeat=no link, SOLID=near-end PMA match."
puts "INFO: holding 8s for visual check, then restoring system_top_rxdly.bit"
after 8000
set restore [file join $repo_root bitstream_output system_top_rxdly.bit]
if {![file exists $restore]} {
    set restore [file join $repo_root bitstream_output system_top.bit]
}
set_property PROGRAM.FILE $restore [current_hw_device]
if {[catch {program_hw_devices [current_hw_device]} rerr]} {
    puts "WARN: restore $restore failed: $rerr"
} else {
    puts "INFO: restored $restore"
}
catch {close_hw_target}
catch {disconnect_hw_server}
exit 0
