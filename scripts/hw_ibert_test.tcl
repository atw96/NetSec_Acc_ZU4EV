################################################################################
# Program IBERT bit and read Near-End PMA PRBS7 LINK / BER
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
# AXI/IBERT peek at 1 MHz after config
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
catch {set_property LOOPBACK {Near-End PMA} $gt}
catch {set_property TX_PATTERN {PRBS 7-bit} $gt}
catch {set_property RX_PATTERN {PRBS 7-bit} $gt}
catch {commit_hw_sio $gt}
after 2000
catch {refresh_hw_device [current_hw_device]}

foreach p {LOOPBACK TX_PATTERN RX_PATTERN LOGIC.LINK RX_BER RX_RECEIVED_BIT_COUNT RX_BIT_ERROR_COUNT} {
    if {[lsearch -exact [list_property $gt] $p] >= 0} {
        puts "GT $p = [get_property $p $gt]"
    } else {
        puts "GT $p = (no such property)"
    }
}
# dump a few more link-ish props
foreach p [lsort [list_property $gt]] {
    if {[string match -nocase *LINK* $p] || [string match -nocase *BER* $p] ||
        [string match -nocase *ERROR* $p] || [string match -nocase *LOOP* $p]} {
        puts "  $p = [get_property $p $gt]"
    }
}
puts "INFO: hw_ibert_test done"
exit 0
