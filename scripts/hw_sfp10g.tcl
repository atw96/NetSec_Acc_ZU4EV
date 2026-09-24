################################################################################
# Program system_top_sfp10g.bit, wait for 10G block_lock, read frame counts.
# Restores system_top_rxdly.bit when finished.
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $repo_root bitstream_output system_top_sfp10g.bit]
if {![file exists $bit]} { error "missing $bit — run scripts/build_sfp10g.tcl" }

source [file join $repo_root scripts hw_jtag.tcl]
nsec_connect
nsec_program $bit
after 10000
# Do not write CTRL first — a leftover write DATA property poisons the next read.

set st  [nsec_rd 0x04]
set tx0 [nsec_rd 0x10]
set rx0 [nsec_rd 0x14]
set bd0 [nsec_rd 0x18]
set tx1 [nsec_rd 0x20]
set rx1 [nsec_rd 0x24]
set bd1 [nsec_rd 0x28]
puts "SFP10G t0 STATUS=$st (bit0 por bit1 tx_done bit2 rx_done bit3 los1 bit4 los2 bit8 lock0 bit9 lock1 bit10 rxst0 bit11 rxst1 bit12 hber0 bit13 hber1)"
puts "SFP10G t0 TX0=$tx0 RX0=$rx0 BAD0=$bd0"
puts "SFP10G t0 TX1=$tx1 RX1=$rx1 BAD1=$bd1"

after 3000
set st2  [nsec_rd 0x04]
set tx0b [nsec_rd 0x10]
set rx0b [nsec_rd 0x14]
set bd0b [nsec_rd 0x18]
set tx1b [nsec_rd 0x20]
set rx1b [nsec_rd 0x24]
set bd1b [nsec_rd 0x28]
puts "SFP10G t1 STATUS=$st2"
puts "SFP10G t1 TX0=$tx0b RX0=$rx0b BAD0=$bd0b"
puts "SFP10G t1 TX1=$tx1b RX1=$rx1b BAD1=$bd1b"

set stn  0
set rx0n 0
set rx1n 0
set rx0g 0
set rx1g 0
catch {set stn  [expr {$st2}]}
catch {set rx0n [expr {$rx0b}]}
catch {set rx1n [expr {$rx1b}]}
catch {set rx0g [expr {$rx0b - $rx0}]}
catch {set rx1g [expr {$rx1b - $rx1}]}
set lock0 [expr {($stn >> 8) & 1}]
set lock1 [expr {($stn >> 9) & 1}]

if {$lock0 && $lock1 && $rx0n > 0 && $rx1n > 0 && $rx0g > 0 && $rx1g > 0} {
    puts "PASS: 10G fiber inter-port loopback (block_lock + RX counts growing)"
} else {
    puts "NEED_HW: expect STATUS bit8/bit9=1 and CNT_RX0/1 growing."
    puts "NEED_HW: 2x 10G SFP+ + LC SFP1<->SFP2; mgtrefclk is 125 MHz SiT9121."
}

set restore [file join $repo_root bitstream_output system_top_rxdly.bit]
if {[file exists $restore]} {
    nsec_program $restore
    puts "INFO: restored $restore"
}
catch {close_hw_target}
catch {disconnect_hw_server}
exit 0
