################################################################################
# One-shot L5a/L5b: program default system_top at 100 kHz, then poke 0xC0 / 0x100.
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root scripts hw_jtag.tcl]

set bit [file join $repo_root bitstream_output system_top_rxdly.bit]
if {![file exists $bit]} {
    set bit [file join $repo_root bitstream_output system_top.bit]
}
if {![file exists $bit]} { puts "NEED_HW: missing bitstream"; exit 2 }

open_hw_manager
if {[info exists ::env(NSEC_HW_URL)] && $::env(NSEC_HW_URL) ne ""} {
    if {[catch {connect_hw_server -url $::env(NSEC_HW_URL)} cerr]} {
        puts "NEED_HW: connect_hw_server $::env(NSEC_HW_URL): $cerr"
        exit 2
    }
} else {
    catch {connect_hw_server}
}
foreach t [get_hw_targets -quiet] { catch {set_property PARAM.FREQUENCY 100000 $t} }
if {[catch {open_hw_target} err]} {
    puts "NEED_HW: open_hw_target: $err"
    exit 2
}
catch {set_property PARAM.FREQUENCY 100000 [current_hw_target]}
set fab [lsearch -inline -regexp [get_hw_devices] {xczu|xc7|xck}]
if {$fab eq ""} { set fab [lindex [get_hw_devices] 0] }
current_hw_device $fab
catch {set_property PROBES.FILE {} [current_hw_device]}
set_property PROGRAM.FILE $bit [current_hw_device]
puts "INFO: programming $bit TCK=[get_property PARAM.FREQUENCY [current_hw_target]]"
if {[catch {program_hw_devices [current_hw_device]} perr]} {
    puts "WARN: program 100 kHz: $perr — retry 1 MHz"
    catch {set_property PARAM.FREQUENCY 1000000 [current_hw_target]}
    if {[catch {program_hw_devices [current_hw_device]} perr2]} {
        puts "NEED_HW: nsec_program failed: $perr2"
        exit 2
    }
}
catch {set_property PARAM.FREQUENCY 1000000 [current_hw_target]}
after 3000
if {[catch {refresh_hw_device [current_hw_device]} rerr]} {
    puts "WARN: refresh_hw_device: $rerr"
}
puts "INFO: current_hw_device = [current_hw_device] hw_axi=[get_hw_axis -quiet]"
if {[llength [get_hw_axis -quiet]] == 0} {
    puts "NEED_HW: no hw_axi after program"
    exit 2
}

puts "===== L5a BIST nsec_sfp10g_check ====="
if {[catch {nsec_sfp10g_check} e1]} {
    puts "NEED_HW: nsec_sfp10g_check: $e1"
}

puts "===== L5b INLINE nsec_l5_test ====="
if {[catch {nsec_l5_test} e2]} {
    puts "NEED_HW: nsec_l5_test: $e2"
}

puts "INFO: hw_l5_once done"
exit 0
