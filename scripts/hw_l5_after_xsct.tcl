################################################################################
# After xsct has already programmed PL: connect Vivado, skip program, run L5.
# Usage:
#   xsct scripts/xsct_fpga_only.tcl
#   vivado -mode batch -source scripts/hw_l5_after_xsct.tcl
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root scripts hw_jtag.tcl]

open_hw_manager
if {[catch {connect_hw_server} cerr]} {
    puts "NEED_HW: connect_hw_server: $cerr"
    exit 2
}
foreach t [get_hw_targets -quiet] {
    catch {set_property PARAM.FREQUENCY 1000000 $t}
}
if {[catch {open_hw_target} err]} {
    puts "NEED_HW: open_hw_target: $err"
    exit 2
}
catch {set_property PARAM.FREQUENCY 1000000 [current_hw_target]}
set fab [lsearch -inline -regexp [get_hw_devices] {xczu|xc7|xck}]
if {$fab eq ""} { set fab [lindex [get_hw_devices] 0] }
current_hw_device $fab
catch {set_property PROBES.FILE {} [current_hw_device]}
after 2000
if {[catch {refresh_hw_device [current_hw_device]} rerr]} {
    puts "WARN: refresh_hw_device: $rerr"
}
puts "INFO: current_hw_device = [current_hw_device] hw_axi=[get_hw_axis -quiet]"
if {[llength [get_hw_axis -quiet]] == 0} {
    puts "NEED_HW: no hw_axi — PL may not be programmed / debug hub missing"
    exit 2
}

puts "===== L5a BIST nsec_sfp10g_check ====="
if {[catch {nsec_sfp10g_check} e1]} {
    puts "NEED_HW: nsec_sfp10g_check: $e1"
    exit 3
}

puts "===== L5b INLINE nsec_l5_test ====="
if {[catch {nsec_l5_test} e2]} {
    puts "NEED_HW: nsec_l5_test: $e2"
    exit 3
}

puts "INFO: hw_l5_after_xsct done"
exit 0
