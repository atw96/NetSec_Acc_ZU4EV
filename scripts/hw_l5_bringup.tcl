################################################################################
# Robust L5 bring-up on ZU4EV:
#  1) connect existing/fresh hw_server
#  2) TCK 100 kHz program (tolerate End of startup LOW)
#  3) refresh; if no hw_axi, retry program once at 1 MHz
#  4) L5a + L5b register dumps
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root scripts hw_jtag.tcl]

set bit [file join $repo_root bitstream_output system_top_rxdly.bit]
if {![file exists $bit]} {
    set bit [file join $repo_root bitstream_output system_top.bit]
}
if {![file exists $bit]} {
    puts "NEED_HW: missing bitstream"; flush stdout; exit 2
}
puts "INFO: bit=$bit size=[file size $bit]"; flush stdout

set url "TCP:127.0.0.1:3125"
if {[info exists ::env(NSEC_HW_URL)] && $::env(NSEC_HW_URL) ne ""} {
    set url $::env(NSEC_HW_URL)
}

open_hw_manager
puts "INFO: connect_hw_server $url"; flush stdout
if {[catch {connect_hw_server -url $url} cerr]} {
    puts "WARN: $url failed ($cerr); trying default"; flush stdout
    if {[catch {connect_hw_server} cerr2]} {
        puts "NEED_HW: connect_hw_server: $cerr2"; flush stdout; exit 2
    }
}
after 1000
set tgts [get_hw_targets -quiet]
puts "INFO: targets=$tgts"; flush stdout
if {[llength $tgts] == 0} {
    puts "NEED_HW: no hw_targets (cable locked or missing)"; flush stdout; exit 2
}
foreach t $tgts { catch {set_property PARAM.FREQUENCY 100000 $t} }
if {[catch {open_hw_target} err]} {
    puts "NEED_HW: open_hw_target: $err"; flush stdout; exit 2
}
catch {set_property PARAM.FREQUENCY 100000 [current_hw_target]}
set fab [lsearch -inline -regexp [get_hw_devices] {xczu|xc7|xck}]
if {$fab eq ""} { set fab [lindex [get_hw_devices] 0] }
current_hw_device $fab
catch {set_property PROBES.FILE {} [current_hw_device]}
puts "INFO: device=$fab TCK=[get_property PARAM.FREQUENCY [current_hw_target]]"; flush stdout

proc nsec_try_program {bit} {
    set_property PROGRAM.FILE $bit [current_hw_device]
    set ok 0
    if {[catch {program_hw_devices [current_hw_device]} perr]} {
        puts "WARN: program_hw_devices: $perr"; flush stdout
        # End of startup LOW sometimes still leaves fabric usable — refresh anyway
    } else {
        set ok 1
        puts "INFO: program_hw_devices returned OK"; flush stdout
    }
    after 2000
    catch {refresh_hw_device [current_hw_device]}
    set axi [get_hw_axis -quiet]
    puts "INFO: after program hw_axi=$axi"; flush stdout
    return [expr {[llength $axi] > 0}]
}

set programmed [nsec_try_program $bit]
if {!$programmed} {
    puts "INFO: retry program at 1 MHz"; flush stdout
    catch {set_property PARAM.FREQUENCY 1000000 [current_hw_target]}
    set programmed [nsec_try_program $bit]
}
if {!$programmed} {
    # Last chance: close/reopen target then program
    puts "INFO: close/reopen target then program"; flush stdout
    catch {close_hw_target}
    after 1000
    foreach t [get_hw_targets -quiet] { catch {set_property PARAM.FREQUENCY 100000 $t} }
    if {[catch {open_hw_target} err]} {
        puts "NEED_HW: reopen failed: $err"; flush stdout; exit 2
    }
    catch {set_property PARAM.FREQUENCY 100000 [current_hw_target]}
    current_hw_device [lsearch -inline -regexp [get_hw_devices] {xczu|xc7|xck}]
    catch {set_property PROBES.FILE {} [current_hw_device]}
    set programmed [nsec_try_program $bit]
}
if {!$programmed} {
    puts "NEED_HW: no hw_axi after all program attempts"; flush stdout
    exit 2
}

catch {set_property PARAM.FREQUENCY 1000000 [current_hw_target]}
after 3000

puts "===== L5a BIST nsec_sfp10g_check ====="; flush stdout
if {[catch {nsec_sfp10g_check} e1]} {
    puts "NEED_HW: nsec_sfp10g_check: $e1"; flush stdout; exit 3
}

puts "===== L5b INLINE nsec_l5_test ====="; flush stdout
if {[catch {nsec_l5_test} e2]} {
    puts "NEED_HW: nsec_l5_test: $e2"; flush stdout; exit 3
}

puts "===== L5c on-chip inject nsec_l5c_test ====="; flush stdout
if {[catch {nsec_l5c_test} e3]} {
    puts "NEED_HW: nsec_l5c_test: $e3"; flush stdout; exit 3
}

puts "INFO: hw_l5_bringup done"; flush stdout
exit 0
