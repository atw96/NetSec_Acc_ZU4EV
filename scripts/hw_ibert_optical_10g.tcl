################################################################################
# IBERT 10.0G external fiber loopback — LOOPBACK=None, PRBS31
# (IBERT cannot pair 10.3125G with the board's 125 MHz SiT9121.)
# Topology: SFP1 (X0Y4) TX <-> SFP2 (X0Y5) RX via LC fiber (same PRBS poly).
# Restores system_top_rxdly.bit when finished.
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $repo_root bitstream_output system_top_ibert.bit]
if {![file exists $bit]} { error "missing $bit — run scripts/create_ibert.tcl then build_ibert.tcl" }

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

set targets {}
foreach gt $gts {
    set n [string toupper $gt]
    if {[string match "*X0Y4*" $n] || [string match "*X0Y5*" $n]} {
        lappend targets $gt
    }
}
if {[llength $targets] == 0} {
    puts "WARN: no GT name matched X0Y4/X0Y5 — using first two enumerated cores"
    set targets [lrange $gts 0 1]
}

set pass 1
foreach gt $targets {
    catch {set_property LOOPBACK {None} $gt}
    catch {set_property TX_PATTERN {PRBS 31-bit} $gt}
    catch {set_property RX_PATTERN {PRBS 31-bit} $gt}
    catch {commit_hw_sio $gt}
}
after 5000
catch {refresh_hw_device [current_hw_device]}
foreach gt $targets {
    catch {reset_hw_sio -rx_bert $gt}
}
after 4000
catch {refresh_hw_device [current_hw_device]}

foreach gt $targets {
    puts "==== $gt ===="
    foreach p {LOOPBACK TX_PATTERN RX_PATTERN LOGIC.LINK RX_BER RX_RECEIVED_BIT_COUNT RX_BIT_ERROR_COUNT} {
        if {[lsearch -exact [list_property $gt] $p] >= 0} {
            puts "GT $p = [get_property $p $gt]"
        } else {
            puts "GT $p = (no such property)"
        }
    }
    set link 0
    catch {set link [get_property LOGIC.LINK $gt]}
    if {$link != 1} {
        set pass 0
        puts "NEED_HW: $gt LINK!=1 with LOOPBACK=None @ 10.0G"
    }
}

if {$pass} {
    puts "PASS: optical 10.0G IBERT LINK=1 on SFP1/SFP2 (X0Y4/X0Y5)"
} else {
    puts "NEED_HW: insert 2x 10G SFP+ + LC fiber SFP1<->SFP2; sfp_tx_dis must be 0."
    puts "NEED_HW: if both LINK=0, swap one LC pair (TX/RX polarity)."
    puts "NEED_HW: mgtrefclk is 125 MHz (SiT9121), not 156.25 MHz crystal."
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
