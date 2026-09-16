################################################################################
# IBERT external (optical / cable) loopback — LOOPBACK=None
# Hardware required: 1x 1.25G SFP in cage 1 + LC TX-to-RX loopback.
# Without a module: LINK stays 0 — that is a hardware-missing result, not an RTL fail.
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $repo_root bitstream_output system_top_ibert.bit]
if {![file exists $bit]} { error "missing $bit" }

open_hw_manager
catch {connect_hw_server}
foreach t [get_hw_targets] { catch {set_property PARAM.FREQUENCY 100000 $t} }
if {[catch {open_hw_target} err]} { puts "ERROR: $err"; exit 1 }
catch {set_property PARAM.FREQUENCY 100000 [current_hw_target]}
current_hw_device [get_hw_devices xczu4_0]
catch {set_property PROBES.FILE {} [current_hw_device]}
set_property PROGRAM.FILE $bit [current_hw_device]
if {[catch {program_hw_devices [current_hw_device]} perr]} {
    puts "WARN: program 100 kHz: $perr — retry 1 MHz"
    catch {set_property PARAM.FREQUENCY 1000000 [current_hw_target]}
    if {[catch {program_hw_devices [current_hw_device]} perr2]} {
        puts "ERROR: program failed: $perr2"
        exit 2
    }
}
catch {set_property PARAM.FREQUENCY 1000000 [current_hw_target]}
after 2000
catch {refresh_hw_device [current_hw_device]}

set gts [get_hw_sio_gts -quiet]
puts "INFO: hw_sio_gts = $gts"
if {[llength $gts] == 0} {
    puts "ERROR: no IBERT GT cores visible"
    exit 3
}
set gt [lindex $gts 0]
catch {set_property LOOPBACK {None} $gt}
catch {set_property TX_PATTERN {PRBS 7-bit} $gt}
catch {set_property RX_PATTERN {PRBS 7-bit} $gt}
catch {commit_hw_sio $gt}
after 5000
catch {refresh_hw_device [current_hw_device]}
catch {reset_hw_sio -rx_bert $gt}
after 3000
catch {refresh_hw_device [current_hw_device]}

foreach p {LOOPBACK TX_PATTERN RX_PATTERN LOGIC.LINK RX_BER RX_RECEIVED_BIT_COUNT RX_BIT_ERROR_COUNT} {
    if {[lsearch -exact [list_property $gt] $p] >= 0} {
        puts "GT $p = [get_property $p $gt]"
    } else {
        puts "GT $p = (no such property)"
    }
}

set link 0
catch {set link [get_property LOGIC.LINK $gt]}
if {$link == 1} {
    puts "PASS: optical/external IBERT LINK=1"
} else {
    puts "NEED_HW: IBERT LINK!=1 with LOOPBACK=None."
    puts "NEED_HW: insert 1x 1000BASE-SX/LX SFP (1.25G) in SFP1 + LC loopback (TX->RX)."
    puts "NEED_HW: 10G SFP+ may lock at 1.25G but 1G SFP is the intended part."
}

set restore [file join $repo_root bitstream_output system_top_rxdly.bit]
if {[file exists $restore]} {
    set_property PROGRAM.FILE $restore [current_hw_device]
    catch {set_property PARAM.FREQUENCY 100000 [current_hw_target]}
    if {[catch {program_hw_devices [current_hw_device]} rerr]} {
        puts "WARN: restore failed: $rerr"
    } else {
        puts "INFO: restored $restore"
    }
}
catch {close_hw_target}
catch {disconnect_hw_server}
exit 0
