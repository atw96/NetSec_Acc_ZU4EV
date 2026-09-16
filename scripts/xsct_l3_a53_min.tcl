# Load freestanding GEM TX stub at 0xFFFF0000 and release ACPU0
set repo [file normalize [file join [file dirname [info script]] ..]]
set bin  [file join $repo firmware l3_gem_min.bin]
if {![file exists $bin]} { error "missing $bin" }

proc psu_rd {addr} {
    set s [mrd -force $addr 1]
    if {[regexp {:\s+([0-9A-Fa-f]+)} $s -> hex]} {
        scan $hex %x val
        return $val
    }
    error "mrd $addr failed: $s"
}
proc psu_wr {addr val} {
    mwr -force $addr [format 0x%08X [expr {$val & 0xFFFFFFFF}]]
}

connect
after 500
catch {configparams force-mem-accesses 1}
targets -set -filter {name =~ "PSU"}
catch {jtag frequency 1000000}

set psu [file join $repo firmware vitis_ws netsec_plat hw psu_init.tcl]
if {[file exists $psu]} {
    source $psu
    proc psu_ddr_phybringup_data {} { puts "INFO: skip DDR" }
    if {[catch {psu_init} e]} { puts "WARN: psu_init: $e" }
    catch {psu_ps_pl_isolation_removal}
    catch {psu_ps_pl_reset_config}
}
puts "==== after psu_init ====\n[targets]"

puts [format "APU CFG  0xFD5C0020 = 0x%08X" [psu_rd 0xFD5C0020]]
puts [format "APU RVBAR0 0xFD5C0040 = 0x%08X" [psu_rd 0xFD5C0040]]
puts [format "RST_FPD  0xFD1A0104 = 0x%08X" [psu_rd 0xFD1A0104]]
# Hold CPU0 only — do not write 0x3D0F (those high bits pin L2 and the whole APU)
set rst [psu_rd 0xFD1A0104]
psu_wr 0xFD1A0104 [expr {$rst | 0x1}]
after 100
puts [format "INFO: hold CPU0 RST=0x%08X" [psu_rd 0xFD1A0104]]

set fp [open $bin r]
fconfigure $fp -translation binary
set raw [read $fp]
close $fp
set n [string length $raw]
set addr 0xFFFF0000
set i 0
while {$i + 4 <= $n} {
    binary scan [string range $raw $i [expr {$i + 3}]] iu w
    psu_wr $addr $w
    incr i 4
    incr addr 4
}
puts [format "INFO: loaded %d bytes @ FFFF0000 word0=0x%08X" $n [psu_rd 0xFFFF0000]]

# Clear mailbox
psu_wr 0xFFFEF000 0
psu_wr 0xFFFEF004 0
psu_wr 0xFFFEF008 0
psu_wr 0xFFFEF00C 0

# AA64nAA32 for CPU0 if this is APU CONFIG
catch {psu_wr 0xFD5C0020 [expr {[psu_rd 0xFD5C0020] | 0x1}]}
psu_wr 0xFD5C0040 0xFFFF0000
psu_wr 0xFD5C0044 0
# Release CPU0 only
set rst [psu_rd 0xFD1A0104]
psu_wr 0xFD1A0104 [expr {$rst & ~0x1}]
puts [format "INFO: ACPU0 released RST=0x%08X RVBAR=0x%08X" [psu_rd 0xFD1A0104] [psu_rd 0xFD5C0040]]
puts "==== targets ====\n[targets]"
# `targets` can steal the current target onto A53 — force PSU before any mrd
targets -set -filter {name =~ "PSU"}
catch {configparams force-mem-accesses 1}
after 2000

for {set k 0} {$k < 20} {incr k} {
    if {[catch {
        set m0 [psu_rd 0xFFFEF000]
        set m1 [psu_rd 0xFFFEF004]
        set m2 [psu_rd 0xFFFEF008]
        puts [format "MB %d: %08X %08X %08X" $k $m0 $m1 $m2]
    } e]} {
        puts "WARN: mailbox mrd: $e"
        targets -set -filter {name =~ "PSU"}
        catch {configparams force-mem-accesses 1}
        set m0 0
    }
    if {$m0 == 0x4E53334C || $m0 == 0x4E5333A0} { break }
    after 200
}

puts [format "PL STATUS=0x%08X RX=%u TX=%u FWD=%u DPI=%u MIR=%u" \
    [psu_rd 0x80050004] [psu_rd 0x80050010] [psu_rd 0x80050014] \
    [psu_rd 0x80050018] [psu_rd 0x80050024] [psu_rd 0x80050020]]
disconnect
exit 0
