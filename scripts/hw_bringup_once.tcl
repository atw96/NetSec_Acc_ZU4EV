################################################################################
# JTAG bring-up with slow TCK (debug hub was flaky at default speed)
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root scripts hw_jtag.tcl]

set bit [file join $repo_root bitstream_output system_top.bit]

open_hw_manager
catch {connect_hw_server}

# Slow TCK before opening the target
set tgts [get_hw_targets]
puts "INFO: targets = $tgts"
foreach t $tgts {
    catch {set_property PARAM.FREQUENCY 1000000 $t}
    puts "INFO: $t FREQ=[get_property PARAM.FREQUENCY $t]"
}

if {[catch {open_hw_target} err]} {
    puts "ERROR: open_hw_target: $err"
    exit 1
}

puts "INFO: devices = [get_hw_devices]"
current_hw_device [get_hw_devices xczu4_0]

set ltx [file join $repo_root vivado_proj netsec_accel_zu4ev.runs impl_1 system_top.ltx]
if {[file exists $bit]} {
    set_property PROGRAM.FILE $bit [current_hw_device]
}
if {[file exists $ltx]} {
    set_property PROBES.FILE $ltx [current_hw_device]
    puts "INFO: probes = $ltx"
}
if {[catch {program_hw_devices [current_hw_device]} perr]} {
    puts "WARN: program_hw_devices: $perr"
} else {
    puts "INFO: program_hw_devices returned OK"
}
catch {close_hw_target}
foreach t [get_hw_targets] {
    catch {set_property PARAM.FREQUENCY 1000000 $t}
}
open_hw_target
current_hw_device [get_hw_devices xczu4_0]
if {[file exists $ltx]} {
    set_property PROBES.FILE $ltx [current_hw_device]
}
after 2000
if {[catch {refresh_hw_device [current_hw_device]} rerr]} {
    puts "WARN: refresh_hw_device: $rerr"
}

puts "INFO: hw_axis = [get_hw_axis -quiet]"
puts "INFO: hw_ilas = [get_hw_ilas -quiet]"

if {[llength [get_hw_axis -quiet]] == 0} {
    puts "ERROR: still no hw_axi after slow TCK"
    exit 3
}

puts "CTRL     [nsec_rd 0x00]"
puts "STATUS   [nsec_rd 0x04]"
puts "LOOPBACK [nsec_rd 0x08]"
nsec_l0_test
puts "INFO: bring-up done"
exit 0
