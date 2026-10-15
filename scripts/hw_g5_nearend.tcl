################################################################################
# G5 isolation: existing bitstream, GT near-end PMA loopback (0x08=4).
# Does not rebuild. Programs the current bit only if jtag_axi is absent.
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root scripts hw_jtag.tcl]

set url "TCP:127.0.0.1:3121"
if {[info exists ::env(NSEC_HW_URL)] && $::env(NSEC_HW_URL) ne ""} {
    set url $::env(NSEC_HW_URL)
}

open_hw_manager
puts "INFO: connect_hw_server $url"; flush stdout
if {[catch {connect_hw_server -url $url} cerr]} {
    puts "NEED_HW: connect_hw_server: $cerr"; flush stdout; exit 2
}
after 500
set tgts [get_hw_targets -quiet]
puts "INFO: targets=$tgts"; flush stdout
if {[llength $tgts] == 0} {
    puts "NEED_HW: no hw_targets"; flush stdout; exit 2
}
foreach t $tgts { catch {set_property PARAM.FREQUENCY 1000000 $t} }
if {[catch {open_hw_target} err]} {
    puts "NEED_HW: open_hw_target: $err"; flush stdout; exit 2
}
set fab [lsearch -inline -regexp [get_hw_devices] {xczu|xc7|xck}]
if {$fab eq ""} { set fab [lindex [get_hw_devices] 0] }
current_hw_device $fab
refresh_hw_device -update_hw_probes false [current_hw_device]
set axi [get_hw_axis -quiet]
puts "INFO: device=$fab hw_axi=$axi"; flush stdout

if {[llength $axi] == 0} {
    set bit [file join $repo_root bitstream_output system_top.bit]
    if {![file exists $bit]} {
        puts "NEED_HW: no hw_axi and missing $bit"; flush stdout; exit 2
    }
    puts "INFO: programming existing $bit"; flush stdout
    set_property PROGRAM.FILE $bit [current_hw_device]
    catch {set_property PROBES.FILE {} [current_hw_device]}
    if {[catch {program_hw_devices [current_hw_device]} perr]} {
        puts "WARN: program_hw_devices: $perr"; flush stdout
    }
    after 2000
    catch {refresh_hw_device [current_hw_device]}
    set axi [get_hw_axis -quiet]
    puts "INFO: after program hw_axi=$axi"; flush stdout
    if {[llength $axi] == 0} {
        puts "NEED_HW: no hw_axi"; flush stdout; exit 2
    }
}

puts "===== G5 near-end PMA (0x08=4, BIST) ====="; flush stdout
nsec_wr 0x100 0xC
nsec_wr 0x08 0x4
nsec_wr 0xDC 0x1
after 2000
puts "LOOPBACK [nsec_rd 0x08] NS10G_CTRL [nsec_rd 0x100]"; flush stdout
if {[catch {nsec_sfp10g_check} e]} {
    puts "NEED_HW: nsec_sfp10g_check: $e"; flush stdout
    nsec_wr 0x08 0x1
    exit 3
}
nsec_wr 0x08 0x1
puts "INFO: restored LOOPBACK [nsec_rd 0x08]"; flush stdout
puts "INFO: hw_g5_nearend done"; flush stdout
exit 0
