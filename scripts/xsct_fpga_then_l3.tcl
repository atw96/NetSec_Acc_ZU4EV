################################################################################
# L3 close-loop: never halt A53 (sctlr_el3 timeout).
#   rst-system → TCK 100 kHz fpga → psu_init → hold APU reset
#   → PSU dow → RVBAR → release ACPU0 → PSU mrd mailbox
################################################################################
set repo [file normalize [file join [file dirname [info script]] ..]]
set elf  [file join $repo firmware netsec_l3.elf]
set bin  [file join $repo firmware netsec_l3.bin]
set bit  [file join $repo bitstream_output system_top.bit]
if {![file exists $bin]} { error "missing $bin — run scripts/link_ps_app.bat" }
if {![file exists $bit]} { error "missing $bit" }

connect
after 1500
catch {configparams force-mem-accesses 1}

if {[catch {targets -set -filter {name =~ "PSU"}} e]} {
    puts "ERROR: no PSU: $e"; disconnect; exit 1
}
puts "==== targets ====\n[targets]"
puts "INFO: rst -system"
catch {rst -system}
after 2500

if {[catch {
    set jt [jtag targets]
    puts "JTAG:\n$jt"
    if {[regexp {(?n)^\s*(\d+)\s+} $jt -> jid]} { jtag targets $jid }
    jtag frequency 100000
} e]} { puts "WARN: jtag freq: $e" }

catch {targets -set -filter {name =~ "PL"}}
if {[catch {fpga $bit} e]} {
    puts "ERROR: fpga: $e"; disconnect; exit 1
}
puts "INFO: fpga OK"
catch {jtag frequency 1000000}
after 500

targets -set -filter {name =~ "PSU"}
catch {configparams force-mem-accesses 1}

set psu [file join $repo firmware vitis_ws netsec_plat hw psu_init.tcl]
if {[file exists $psu]} {
    source $psu
    proc psu_ddr_phybringup_data {} { puts "INFO: skip DDR" }
    if {[catch {psu_init} e]} { puts "WARN: psu_init: $e" }
    catch {psu_ps_pl_isolation_removal}
    catch {psu_ps_pl_reset_config}
}
# Arm PL datapath + 1G AN from PSU
if {![catch {mwr -force 0x80050000 0x3}]} { after 5 }
foreach {reg val} {0 0x8000 4 0x0001 9 0x0200 0 0x1200} {
    catch {mwr -force 0x80050054 $val}
    set ctrl [expr {1 | (($reg & 0x1f) << 8) | (1 << 16) | (1 << 17)}]
    catch {mwr -force 0x80050050 $ctrl}
    after 30
}
catch {mwr -force 0x80050008 0x0}
catch {mwr -force 0x80050000 0x1}
after 1500
if {![catch {set st [mrd -force 0x80050004 1]}]} { puts "INFO: PL STATUS $st" }

# Hold all A53 cores in reset so image load does not need DAP halt
catch {mwr -force 0xFD1A0104 0x00003D0F}
after 200

puts "INFO: PSU word-load $bin -> 0xFFFC0000"
set fp [open $bin r]
fconfigure $fp -translation binary
set raw [read $fp]
close $fp
set n [string length $raw]
set addr 0xFFFC0000
set i 0
while {$i + 4 <= $n} {
    set vals {}
    set cnt 0
    while {$cnt < 32 && $i + 4 <= $n} {
        binary scan [string range $raw $i [expr {$i + 3}]] iu w
        lappend vals [format 0x%08X [expr {$w & 0xFFFFFFFF}]]
        incr i 4
        incr cnt
    }
    if {[catch {mwr -force $addr $vals} e]} {
        puts "ERROR: mwr @$addr: $e"
        disconnect
        exit 1
    }
    incr addr [expr {$cnt * 4}]
}
puts "INFO: loaded $n bytes"
# Spot-check vector word at 0xFFFF0000 (should not be 0 if .boot loaded)
if {![catch {set vec [mrd -force 0xFFFF0000 1]}]} { puts "INFO: [0xFFFF0000] $vec" }
if {![catch {set t0 [mrd -force 0xFFFC0000 1]}]} { puts "INFO: [0xFFFC0000] $t0" }
puts "INFO: image loaded"

# RVBAR CPU0 = 0xFFFF0000 (.boot / _vector_table)
catch {mwr -force 0xFD5C0040 0xFFFF0000}
catch {mwr -force 0xFD5C0044 0x00000000}

# Release ACPU0 + L2 + PWRON0; keep CPU1-3 in reset
catch {mwr -force 0xFD1A0104 0x0000380E}
puts "INFO: ACPU0 released"
after 2000

set words ""
for {set i 0} {$i < 40} {incr i} {
    if {![catch {set words [mrd -force 0xFFFEF000 12]}]} {
        puts "MB $i: $words"
        if {[string match -nocase *4E53334C* $words]} {
            puts "INFO: mailbox complete"
            break
        }
    } else {
        puts "WARN: mrd mailbox failed"
    }
    after 1000
}
puts "MAILBOX:\n$words"
disconnect
exit 0
