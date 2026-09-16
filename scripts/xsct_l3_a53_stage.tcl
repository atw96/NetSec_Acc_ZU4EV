################################################################################
# A53 stage-2: program rxdly bit, psu_init, arm PL, AN, dow ELF, poll mailbox.
# Stage codes (0xFFFEF000): A0 / A1 / 302 / 303 / 304 / 305 / 306 / 307 / E1 / NS3L
# argv0 = bitstream (default system_top_rxdly.bit)
# argv1 = optional tap to load before releasing CPU0
################################################################################
set repo [file normalize [file join [file dirname [info script]] ..]]
set bit  [lindex $::argv 0]
if {$bit eq ""} {
    set bit [file join $repo bitstream_output system_top_rxdly.bit]
}
set bit [file normalize $bit]
if {![file exists $bit]} { error "missing $bit" }
set elf [file join $repo firmware netsec_l3.elf]
if {![file exists $elf]} { error "missing $elf — run scripts/link_ps_app.bat" }
set win_tap ""
if {[llength $::argv] > 1} { set win_tap [lindex $::argv 1] }

set GEM  0xFF0E0000
set NSEC 0x80050000

proc psu_retarget {} {
    targets -set -filter {name =~ "PSU"}
    catch {configparams force-mem-accesses 1}
}
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

proc stage_name {v} {
    switch -- [format 0x%08X $v] {
        0x4E5333A0 { return A0_before_dcache }
        0x4E5333A1 { return A1_after_dcache }
        0x4E533302 { return 302_skip_PL }
        0x4E533318 { return 318_gem_rev }
        0x4E5333EE { return EE_sync_abort }
        0x4E533312 { return 312_cfg_ok }
        0x4E533313 { return 313_bdring_ok }
        0x4E533314 { return 314_start_ok }
        0x4E533316 { return 316_tx_normal_done }
        0x4E533317 { return 317_tx_attack_done }
        0x4E533304 { return 304_phy_found }
        0x4E533305 { return 305_an_done }
        0x4E533306 { return 306_pre_tx }
        0x4E533307 { return 307_post_tx }
        0x4E5333E1 { return E1_gem_setup_fail }
        0x4E53334C { return NS3L_done }
        0x00000000 { return zero }
        default    { return unknown }
    }
}

proc nsec_dump {{tag ""}} {
    global NSEC
    if {$tag ne ""} { puts "==== $tag ====" }
    foreach {name off} {
        CTRL 0x00 STATUS 0x04 CNT_RX 0x10 CNT_FWD 0x18
        CNT_DPI 0x24 CNT_MIR 0x20 MAC_GOOD 0x28 MAC_FCS 0x2C RX_ACT 0x6C
    } {
        puts [format "  %-8s = 0x%08X" $name [psu_rd [expr {$NSEC + $off}]]]
    }
}

proc pl_mdio_wr {phy reg val} {
    global NSEC
    psu_wr [expr {$NSEC + 0x54}] $val
    set ctrl [expr {($phy & 0x1f) | (($reg & 0x1f) << 8) | (1 << 16) | (1 << 17)}]
    psu_wr [expr {$NSEC + 0x50}] $ctrl
    for {set i 0} {$i < 80} {incr i} {
        after 4
        if {[psu_rd [expr {$NSEC + 0x58}]] & 0x20000} { return 1 }
    }
    puts "WARN: PL MDIO wr timeout phy=$phy reg=$reg"
    return 0
}

proc pl_mdio_rd {phy reg} {
    global NSEC
    set ctrl [expr {($phy & 0x1f) | (($reg & 0x1f) << 8) | (1 << 17)}]
    psu_wr [expr {$NSEC + 0x50}] $ctrl
    for {set i 0} {$i < 80} {incr i} {
        after 4
        set st [psu_rd [expr {$NSEC + 0x58}]]
        if {$st & 0x20000} { return [expr {$st & 0xffff}] }
    }
    puts "WARN: PL MDIO rd timeout phy=$phy reg=$reg"
    return 0xffff
}

proc gem_mdio_idle {} {
    global GEM
    for {set i 0} {$i < 400} {incr i} {
        if {[psu_rd [expr {$GEM + 8}]] & 0x4} { return 1 }
        after 1
    }
    return 0
}

proc gem_mdio_wr {phy reg val} {
    global GEM
    gem_mdio_idle
    set mgt [expr {0x50020000 | (($phy & 0x1f) << 23) | (($reg & 0x1f) << 18) | ($val & 0xffff)}]
    psu_wr [expr {$GEM + 0x34}] $mgt
    gem_mdio_idle
}

proc gem_mdio_rd {phy reg} {
    global GEM
    gem_mdio_idle
    set mgt [expr {0x60020000 | (($phy & 0x1f) << 23) | (($reg & 0x1f) << 18)}]
    psu_wr [expr {$GEM + 0x34}] $mgt
    gem_mdio_idle
    return [expr {[psu_rd [expr {$GEM + 0x34}]] & 0xffff}]
}

proc eee_off {wr rd phy} {
    $wr $phy 13 0x0007
    $wr $phy 14 0x003C
    $wr $phy 13 0x4007
    $wr $phy 14 0x0000
}

proc phy_an {wr rd phy tag} {
    $wr $phy 0 0x8000
    after 50
    $wr $phy 4 0x0001
    $wr $phy 9 0x0200
    eee_off $wr $rd $phy
    $wr $phy 0 0x1200
    set bmsr 0
    for {set i 0} {$i < 40} {incr i} {
        after 200
        set bmsr [$rd $phy 1]
        if {($bmsr & 0x0024) == 0x0024} {
            puts [format "INFO: %s PHY%u AN ok BMSR=0x%04X" $tag $phy $bmsr]
            return 1
        }
    }
    puts [format "WARN: %s PHY%u AN timeout BMSR=0x%04X" $tag $phy $bmsr]
    return 0
}

proc find_gem_phy {} {
    for {set a 0} {$a < 32} {incr a} {
        set id1 [gem_mdio_rd $a 2]
        if {$id1 != 0 && $id1 != 0xffff} {
            set id2 [gem_mdio_rd $a 3]
            puts [format "INFO: GEM3 PHY addr=%u ID=0x%04X%04X" $a $id1 $id2]
            return $a
        }
    }
    puts "WARN: GEM3 no PHY on MDIO, try addr 0"
    return 0
}

puts "INFO: bit=$bit elf=$elf tap=$win_tap"
connect
after 800
catch {configparams force-mem-accesses 1}
if {[catch {targets -set -filter {name =~ "PSU"}} e]} {
    puts "ERROR: no PSU: $e"; disconnect; exit 1
}

puts "INFO: rst -system"
catch {rst -system}
after 2500
if {[catch {
    set jt [jtag targets]
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
psu_retarget

set psu [file join $repo firmware vitis_ws netsec_plat hw psu_init.tcl]
if {[file exists $psu]} {
    source $psu
    proc psu_ddr_phybringup_data {} { puts "INFO: skip DDR" }
    if {[catch {psu_init} e]} { puts "WARN: psu_init: $e" }
    catch {psu_ps_pl_isolation_removal}
    catch {psu_ps_pl_reset_config}
}
psu_retarget

# Hold CPU0 only, but CLEAR L2 + PWRON0. psu_init leaves 0x3D0E which
# nails L2 (bit8) and ACPU0_PWRON (bit10); `|= 1` then `& ~1` keeps the
# core dead (mailbox stays 0). 0x380F = CPU0-3 ACPU reset, L2/PWRON0 out.
# Never write 0x3D0F.
puts [format "INFO: RST after psu_init=0x%08X" [psu_rd 0xFD1A0104]]
psu_wr 0xFD1A0104 0x0000380F
after 50
psu_retarget
puts [format "INFO: hold CPU0 RST=0x%08X (expect 0x380F)" [psu_rd 0xFD1A0104]]

psu_wr $NSEC 0x3
after 5
psu_wr [expr {$NSEC + 8}] 0
if {$win_tap ne ""} {
    psu_wr [expr {$NSEC + 0x5C}] [expr {([scan $win_tap %d] & 0x1ff) | 0x10000}]
    after 2
}
psu_wr $NSEC 0x1
after 20
nsec_dump "PL armed"

catch {psu_wr 0xFF5E005C 0x06010800}
set iou [psu_rd 0xFF5E0230]
psu_wr 0xFF5E0230 [expr {$iou & ~0x8}]
after 10

# MDEN so GEM MDIO works; firmware owns the rest of GEM.
psu_wr $GEM 0x10
after 5

set st0 [psu_rd [expr {$NSEC + 4}]]
if {($st0 & 0x4) == 0} {
    puts "INFO: PL PHY AN (addr 1)"
    phy_an pl_mdio_wr pl_mdio_rd 1 PL
} else {
    puts "INFO: skip PL PHY AN, link already up"
}

set gphy [find_gem_phy]
set bmsr [gem_mdio_rd $gphy 1]
if {($bmsr & 0x0024) == 0x0024} {
    puts [format "INFO: skip GEM3 PHY AN, BMSR=0x%04X" $bmsr]
} else {
    puts "INFO: GEM3 PHY AN (addr $gphy)"
    phy_an gem_mdio_wr gem_mdio_rd $gphy GEM3
}

set st 0
for {set i 0} {$i < 40} {incr i} {
    set st [psu_rd [expr {$NSEC + 4}]]
    if {$st & 0x4} { break }
    after 200
}
puts [format "INFO: PL STATUS after AN = 0x%08X (link=%d)" $st [expr {($st >> 2) & 1}]]

# Clear mailbox
for {set a 0} {$a < 48} {incr a 4} {
    psu_wr [expr {0xFFFEF000 + $a}] 0
}

catch {psu_wr 0xFD5C0020 [expr {[psu_rd 0xFD5C0020] | 0x1}]}
psu_wr 0xFD5C0040 0xFFFF0000
psu_wr 0xFD5C0044 0

if {[catch {targets -set -filter {name =~ "Cortex-A53 #0"}} e]} {
    puts "ERROR: A53: $e"; disconnect; exit 1
}
catch {stop}
if {[catch {rst -processor -clear-registers} e]} {
    puts "WARN: rst -processor: $e"
    catch {rst -processor}
}
after 400
if {[catch {dow $elf} e]} {
    puts "ERROR: dow: $e"; disconnect; exit 1
}
puts "INFO: dow OK"

# Release ACPU0 + L2 + PWRON0; keep CPU1-3 in reset. Must be PSU target.
psu_retarget
psu_wr 0xFD1A0104 0x0000380E
puts [format "INFO: ACPU0 released RST=0x%08X RVBAR=0x%08X" \
    [psu_rd 0xFD1A0104] [psu_rd 0xFD5C0040]]

if {[catch {targets -set -filter {name =~ "Cortex-A53 #0"}} e]} {
    puts "ERROR: A53 retarget: $e"; disconnect; exit 1
}
puts "INFO: con"
con

set last 0
set hang_stage 0
for {set i 0} {$i < 80} {incr i} {
    after 250
    psu_retarget
    if {[catch {set m0 [psu_rd 0xFFFEF000]} e]} {
        puts "WARN: mailbox: $e"
        continue
    }
    set extra [psu_rd 0xFFFEF024]
    set m1 [psu_rd 0xFFFEF004]
    set m2 [psu_rd 0xFFFEF008]
    set m3 [psu_rd 0xFFFEF00C]
    puts [format "MB %2d: %08X (%s) extra=0x%08X w1=%08X w2=%08X w3=%08X" \
        $i $m0 [stage_name $m0] $extra $m1 $m2 $m3]
    if {$m0 == 0x4E53334C} {
        set hang_stage $m0
        break
    }
    if {$m0 != 0} { set hang_stage $m0 }
    if {$m0 != 0 && $m0 == $last && $i > 12} {
        puts [format "INFO: stage stuck at %s" [stage_name $m0]]
        break
    }
    set last $m0
}

if {$hang_stage != 0x4E53334C && $last != 0x4E53334C} {
    if {![catch {targets -set -filter {name =~ "Cortex-A53 #0"}}]} {
        catch {stop}
        catch {puts "INFO: A53 state=[state]"}
        catch {puts "INFO: A53 regs:\n[rrd]"}
    }
}

psu_retarget
nsec_dump "after A53"
puts [format "  GEM TXCNT  = 0x%08X" [psu_rd [expr {$GEM + 0x108}]]]
puts [format "  GEM TXSR   = 0x%08X" [psu_rd [expr {$GEM + 0x14}]]]
puts [format "  GEM NWCTRL = 0x%08X" [psu_rd $GEM]]
puts [format "  GEM TXQ    = 0x%08X" [psu_rd [expr {$GEM + 0x1C}]]]
puts [format "  GEM TXQ1   = 0x%08X" [psu_rd [expr {$GEM + 0x440}]]]
puts [format "HANG_OR_DONE: 0x%08X %s" $hang_stage [stage_name $hang_stage]]
disconnect
exit 0
