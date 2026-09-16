################################################################################
# L3 close-loop without A53: PSU programs GEM3 + both PHYs, then TX 20 frames.
# Assumes PL bitstream already resident (no rst -system / no fpga).
################################################################################
set GEM  0xFF0E0000
set NSEC 0x80050000
set BD   0xFFFC0000
set FRM  0xFFFC0100

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

proc poke_le {addr bytes} {
    set n [llength $bytes]
    set i 0
    while {$i < $n} {
        set w 0
        for {set b 0} {$b < 4} {incr b} {
            if {$i < $n} {
                set w [expr {$w | (([lindex $bytes $i] & 0xff) << (8 * $b))}]
                incr i
            }
        }
        psu_wr $addr $w
        incr addr 4
    }
}

proc nsec_dump {} {
    global NSEC
    foreach {name off} {
        CTRL 0x00 STATUS 0x04 LOOPBACK 0x08
        CNT_RX 0x10 CNT_TX 0x14 CNT_FWD 0x18
        CNT_DROP 0x1C CNT_MIR 0x20 CNT_DPI 0x24
    } {
        puts [format "  %-8s @+%02X = 0x%08X" $name $off [psu_rd [expr {$NSEC + $off}]]]
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

proc phy_an {wr rd phy tag} {
    $wr $phy 0 0x8000
    after 50
    $wr $phy 4 0x0001
    $wr $phy 9 0x0200
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
    puts "WARN: GEM3 no PHY on MDIO, try addr 1"
    return 1
}

proc build_frame {attack idx} {
    set b {}
    foreach x {0xff 0xff 0xff 0xff 0xff 0xff 0x02 0x00 0x00 0x00 0x00 0xa3 0x08 0x00} {
        lappend b $x
    }
    # IPv4 header-ish (len=80), proto=6
    lappend b 0x45 0x00 0x00 80 0x00 0x00 0x40 0x00 64 6
    if {$attack} {
        lappend b 10 0 0 5
    } else {
        lappend b 192 168 1 2
    }
    lappend b 192 168 1 100
    lappend b [expr {0x30 + (($idx >> 8) & 0xff)}] [expr {$idx & 0xff}] 0x00 80
    # skip to payload offset 54: we are at offset 38 after ports
    # 14 eth + 20 ip + 4 ports = 38; pad 16 bytes then payload
    for {set i 0} {$i < 16} {incr i} { lappend b 0 }
    if {$attack} {
        foreach x {0x47 0x45 0x54 0x20 0x2f} { lappend b $x }
    } else {
        foreach x {0x70 0x69 0x6e 0x67} { lappend b $x }
    }
    while {[llength $b] < 128} { lappend b 0 }
    return $b
}

proc gem_tx_one {bytes} {
    global GEM BD FRM
    poke_le $FRM $bytes
    # Do not rewrite queue bases here — gem_arm_queues owns Q0/Q1.
    # Only toggle TXEN so the hardware reloads QPTR from the programmed base.
    set nw [psu_rd $GEM]
    psu_wr $GEM [expr {$nw & ~0x08}]
    psu_wr $BD $FRM
    psu_wr [expr {$BD + 4}] [expr {0x40008000 | ([llength $bytes] & 0x3fff)}]
    psu_wr [expr {$BD + 8}] 0
    psu_wr [expr {$BD + 12}] 0
    psu_wr $GEM [expr {($nw & ~0x08) | 0x18}]
    set nw [psu_rd $GEM]
    psu_wr $GEM [expr {$nw | 0x200}]
    for {set i 0} {$i < 400} {incr i} {
        set st [psu_rd [expr {$BD + 4}]]
        if {$st & 0x80000000} {
            psu_wr [expr {$GEM + 0x14}] 0xFF
            return 1
        }
        after 1
    }
    set txsr [psu_rd [expr {$GEM + 0x14}]]
    set qbase [psu_rd [expr {$GEM + 0x1C}]]
    puts [format "WARN: TX timeout BD=0x%08X TXSR=0x%08X QBASE=0x%08X NW=0x%08X" \
        [psu_rd [expr {$BD + 4}]] $txsr $qbase [psu_rd $GEM]]
    psu_wr [expr {$GEM + 0x14}] 0xFF
    return 0
}

connect
after 800
catch {configparams force-mem-accesses 1}
if {[catch {targets -set -filter {name =~ "PSU"}} e]} {
    puts "ERROR: no PSU: $e"; disconnect; exit 1
}

# DAP was wedged (sctlr_el3). rst-system + re-fpga is the recovery path.
puts "INFO: rst -system (recover DAP)"
catch {rst -system}
after 2500
if {[catch {
    set jt [jtag targets]
    puts "JTAG:\n$jt"
    if {[regexp {(?n)^\s*(\d+)\s+} $jt -> jid]} { jtag targets $jid }
    jtag frequency 100000
} e]} { puts "WARN: jtag freq: $e" }
set bit [file join [file dirname [info script]] .. bitstream_output system_top.bit]
set bit [file normalize $bit]
catch {targets -set -filter {name =~ "PL"}}
if {[catch {fpga $bit} e]} {
    puts "ERROR: fpga: $e"; disconnect; exit 1
}
puts "INFO: fpga OK"
catch {jtag frequency 1000000}
after 500
targets -set -filter {name =~ "PSU"}
catch {configparams force-mem-accesses 1}

# Re-run PS clocks/MIO/interconnect (skip DDR). psu_init releases A53 — hold it after.
set repo [file normalize [file join [file dirname [info script]] ..]]
set psu [file join $repo firmware vitis_ws netsec_plat hw psu_init.tcl]
if {[file exists $psu]} {
    source $psu
    proc psu_ddr_phybringup_data {} { puts "INFO: skip DDR" }
    if {[catch {psu_init} e]} { puts "WARN: psu_init: $e" }
    catch {psu_ps_pl_isolation_removal}
    catch {psu_ps_pl_reset_config}
}

# Freeze CPU0 only (never write 0x3D0F — those high bits pin L2 / whole APU)
set rst [psu_rd 0xFD1A0104]
psu_wr 0xFD1A0104 [expr {$rst | 0x1}]
after 50
targets -set -filter {name =~ "PSU"}
catch {configparams force-mem-accesses 1}

puts "INFO: hold A53, dump PL before AN"
if {[catch {nsec_dump} e]} {
    puts "ERROR: PL regs unreachable: $e"
    disconnect
    exit 1
}

# Keep datapath in L3 wire mode. Soft-reset only if link is down
# (reset bounces PHYs and wastes the already-up cable link).
set st0 [psu_rd [expr {$NSEC + 4}]]
psu_wr [expr {$NSEC + 8}] 0x0
psu_wr $NSEC 0x1
if {($st0 & 0x4) == 0} {
    psu_wr $NSEC 0x3
    after 5
    psu_wr $NSEC 0x1
    puts "INFO: PL PHY AN (addr 1) — link was down"
    phy_an pl_mdio_wr pl_mdio_rd 1 PL
} else {
    puts "INFO: skip PL PHY AN, link already up"
}

# GEM3 clock + out of reset (idempotent)
catch {psu_wr 0xFF5E005C 0x06010800}
set rst [psu_rd 0xFF5E0230]
psu_wr 0xFF5E0230 [expr {$rst & ~0x8}]
after 10

# GEM3 basic bring-up (TXEN=0 while programming queues)
psu_wr $GEM 0x0
psu_wr [expr {$GEM + 4}] [expr {0x00200000 | 0x000C0000 | 0x00000400 | 0x00000012}]
# 64-bit AXI + RXBUF=24 + RX/TX size + INCR4 (OCM 不一定吃得下 INCR16)
psu_wr [expr {$GEM + 0x10}] 0x40180704
psu_wr [expr {$GEM + 0x88}] 0x00000002
psu_wr [expr {$GEM + 0x8C}] 0x0000A300
psu_wr [expr {$GEM + 0x14}] 0xFF
psu_wr [expr {$GEM + 0x20}] 0x0F
psu_wr [expr {$GEM + 0x2C}] 0xFFFFFFFF
# Dummy RX BD so version>2 GEM has a valid queue
psu_wr 0xFFFC0400 0xFFFC0502
psu_wr 0xFFFC0404 0
psu_wr 0xFFFC0408 0
psu_wr 0xFFFC040C 0
psu_wr [expr {$GEM + 0x18}] 0xFFFC0400
psu_wr [expr {$GEM + 0x4D4}] 0
# Dummy TX BD (USED|WRAP) so the unused queue cannot DMA from address 0
psu_wr 0xFFFC0600 0xFFFC0700
psu_wr 0xFFFC0604 0xC0000000
psu_wr 0xFFFC0608 0
psu_wr 0xFFFC060C 0
psu_wr [expr {$GEM + 0x1C}] $BD
psu_wr [expr {$GEM + 0x440}] 0xFFFC0600
psu_wr [expr {$GEM + 0x4C8}] 0
psu_wr $GEM 0x10
after 5
puts [format "INFO: DMACR=0x%08X ISR=0x%08X Q0=0x%08X Q1=0x%08X" \
    [psu_rd [expr {$GEM + 0x10}]] [psu_rd [expr {$GEM + 0x24}]] \
    [psu_rd [expr {$GEM + 0x1C}]] [psu_rd [expr {$GEM + 0x440}]]]

puts [format "INFO: GEM3 NWCTRL=0x%08X NWCFG=0x%08X NWSR=0x%08X" \
    [psu_rd $GEM] [psu_rd [expr {$GEM + 4}]] [psu_rd [expr {$GEM + 8}]]]

set gphy [find_gem_phy]
set bmsr [gem_mdio_rd $gphy 1]
if {($bmsr & 0x0024) == 0x0024} {
    puts [format "INFO: skip GEM3 PHY AN, BMSR=0x%04X" $bmsr]
} else {
    puts "INFO: GEM3 PHY AN (addr $gphy)"
    phy_an gem_mdio_wr gem_mdio_rd $gphy GEM3
}

# Wait PL link
set st 0
for {set i 0} {$i < 40} {incr i} {
    set st [psu_rd [expr {$NSEC + 4}]]
    if {$st & 0x4} { break }
    after 200
}
puts [format "INFO: PL STATUS after AN wait = 0x%08X (link=%d)" $st [expr {($st >> 2) & 1}]]

# Probe: Q0 live + Q1 dummy, then swap if Q0 does not complete
proc gem_arm_queues {liveq} {
    global GEM BD
    psu_wr $GEM 0x10
    after 1
    if {$liveq == 0} {
        psu_wr [expr {$GEM + 0x1C}] $BD
        psu_wr [expr {$GEM + 0x440}] 0xFFFC0600
    } else {
        psu_wr [expr {$GEM + 0x1C}] 0xFFFC0600
        psu_wr [expr {$GEM + 0x440}] $BD
    }
    psu_wr [expr {$GEM + 0x4C8}] 0
}

puts "INFO: probe TX on Q0"
gem_arm_queues 0
set probe 0
if {[gem_tx_one [build_frame 0 0]]} { set probe 0 } else {
    puts "INFO: probe TX on Q1"
    gem_arm_queues 1
    if {[gem_tx_one [build_frame 0 0]]} { set probe 1 } else { set probe -1 }
}
puts [format "INFO: probe queue=%d ISR=0x%08X TXCNT=%u" $probe \
    [psu_rd [expr {$GEM + 0x24}]] [psu_rd [expr {$GEM + 0x108}]]]

set ok 0
if {$probe >= 0} {
    gem_arm_queues $probe
    for {set i 0} {$i < 16} {incr i} {
        if {[gem_tx_one [build_frame 0 $i]]} { incr ok }
        after 2
    }
    for {set i 0} {$i < 4} {incr i} {
        if {[gem_tx_one [build_frame 1 $i]]} { incr ok }
        after 2
    }
}
after 100

puts "INFO: GEM TX completed $ok/20"
puts [format "INFO: GEM TXCNT=%u TXSR=0x%08X" [psu_rd [expr {$GEM + 0x108}]] [psu_rd [expr {$GEM + 0x14}]]]
puts "==== PL after inject ===="
nsec_dump

set rx [psu_rd [expr {$NSEC + 0x10}]]
set fwd [psu_rd [expr {$NSEC + 0x18}]]
set dpi [psu_rd [expr {$NSEC + 0x24}]]
set mir [psu_rd [expr {$NSEC + 0x20}]]
puts [format "RESULT: RX=%u FWD=%u DPI=%u MIR=%u (want ~20 / ~16 / ~4 / ~4)" $rx $fwd $dpi $mir]
if {$rx >= 16 && $fwd >= 12} {
    puts "INFO: L3 datapath counters look closed"
} else {
    puts "WARN: L3 not closed yet"
}
disconnect
exit 0
