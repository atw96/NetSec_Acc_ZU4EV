# No fpga. Re-AN, disable EEE/ALDPS, GEM TX, read PL CNT_RX.
set GEM  0xFF0E0000
set NSEC 0x80050000
set BD   0xFFFC0000
set FRM  0xFFFC0100

proc psu_rd {addr} {
    set s [mrd -force $addr 1]
    if {[regexp {:\s+([0-9A-Fa-f]+)} $s -> hex]} { scan $hex %x val; return $val }
    error "mrd $addr : $s"
}
proc psu_wr {addr val} { mwr -force $addr [format 0x%08X [expr {$val & 0xFFFFFFFF}]] }

proc pl_mdio_wr {phy reg val} {
    global NSEC
    psu_wr [expr {$NSEC + 0x54}] $val
    psu_wr [expr {$NSEC + 0x50}] [expr {($phy & 0x1f) | (($reg & 0x1f)<<8) | (1<<16) | (1<<17)}]
    for {set i 0} {$i < 80} {incr i} {
        after 4
        if {[psu_rd [expr {$NSEC+0x58}]] & 0x20000} { return }
    }
}
proc pl_mdio_rd {phy reg} {
    global NSEC
    psu_wr [expr {$NSEC + 0x50}] [expr {($phy & 0x1f) | (($reg & 0x1f)<<8) | (1<<17)}]
    for {set i 0} {$i < 80} {incr i} {
        after 4
        set st [psu_rd [expr {$NSEC+0x58}]]
        if {$st & 0x20000} { return [expr {$st & 0xffff}] }
    }
    return 0xffff
}
proc gem_mdio_idle {} {
    global GEM
    for {set i 0} {$i < 400} {incr i} {
        if {[psu_rd [expr {$GEM+8}]] & 4} { return }
        after 1
    }
}
proc gem_mdio_wr {phy reg val} {
    global GEM
    gem_mdio_idle
    psu_wr [expr {$GEM+0x34}] [expr {0x50020000 | (($phy&0x1f)<<23) | (($reg&0x1f)<<18) | ($val&0xffff)}]
    gem_mdio_idle
}
proc gem_mdio_rd {phy reg} {
    global GEM
    gem_mdio_idle
    psu_wr [expr {$GEM+0x34}] [expr {0x60020000 | (($phy&0x1f)<<23) | (($reg&0x1f)<<18)}]
    gem_mdio_idle
    return [expr {[psu_rd [expr {$GEM+0x34}]] & 0xffff}]
}

proc eee_off {wr rd phy} {
    # Clause-22 MMD 7.60 EEE advertisement = 0
    $wr $phy 13 0x0007
    $wr $phy 14 0x003C
    $wr $phy 13 0x4007
    $wr $phy 14 0x0000
    # ALDPS off: page 0xA43 reg 24 (PHYCR1)
    $wr $phy 31 0xA43
    set cr1 [$rd $phy 24]
    $wr $phy 24 [expr {$cr1 & ~0x0004}]
    $wr $phy 31 0
    puts [format "INFO: PHY%u EEE off PHYCR1 was 0x%04X now 0x%04X" $phy $cr1 [$rd $phy 24]]
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

proc poke_le {addr bytes} {
    set n [llength $bytes]; set i 0
    while {$i < $n} {
        set w 0
        for {set b 0} {$b < 4} {incr b} {
            if {$i < $n} { set w [expr {$w | (([lindex $bytes $i]&0xff)<<(8*$b))}]; incr i }
        }
        psu_wr $addr $w
        incr addr 4
    }
}
proc gem_tx_one {len} {
    global GEM BD FRM
    set b {}
    foreach x {0xff 0xff 0xff 0xff 0xff 0xff 0x02 0x00 0x00 0x00 0x00 0xa3 0x08 0x00} { lappend b $x }
    while {[llength $b] < $len} { lappend b 0 }
    poke_le $FRM $b
    psu_wr $GEM 0x10
    psu_wr $BD $FRM
    psu_wr [expr {$BD+4}] [expr {0x40008000 | ($len & 0x3fff)}]
    psu_wr [expr {$BD+8}] 0
    psu_wr [expr {$BD+12}] 0
    psu_wr $GEM 0x18
    psu_wr $GEM [expr {[psu_rd $GEM] | 0x200}]
    for {set i 0} {$i < 400} {incr i} {
        if {[psu_rd [expr {$BD+4}]] & 0x80000000} {
            psu_wr [expr {$GEM+0x14}] 0xFF
            return 1
        }
        after 1
    }
    puts [format "WARN: TX timeout BD=0x%08X TXSR=0x%08X" [psu_rd [expr {$BD+4}]] [psu_rd [expr {$GEM+0x14}]]]
    return 0
}

connect
after 400
catch {configparams force-mem-accesses 1}
targets -set -filter {name =~ "PSU"}
catch {jtag frequency 1000000}
catch {psu_wr 0xFD1A0104 [expr {[psu_rd 0xFD1A0104]|1}]}
targets -set -filter {name =~ "PSU"}

# GEM clocks + basic TX
catch {psu_wr 0xFF5E005C 0x06010800}
set iou [psu_rd 0xFF5E0230]
psu_wr 0xFF5E0230 [expr {$iou & ~8}]
psu_wr $GEM 0
psu_wr [expr {$GEM+4}] [expr {0x00200000|0x000C0000|0x00000400|0x00000012}]
psu_wr [expr {$GEM+0x10}] 0x40180704
psu_wr [expr {$GEM+0x88}] 0x00000002
psu_wr [expr {$GEM+0x8C}] 0x0000A300
psu_wr [expr {$GEM+0x14}] 0xFF
psu_wr [expr {$GEM+0x20}] 0x0F
psu_wr [expr {$GEM+0x2C}] 0xFFFFFFFF
psu_wr 0xFFFC0400 0xFFFC0502
psu_wr 0xFFFC0404 0
psu_wr 0xFFFC0408 0
psu_wr 0xFFFC040C 0
psu_wr [expr {$GEM+0x18}] 0xFFFC0400
psu_wr 0xFFFC0600 0xFFFC0700
psu_wr 0xFFFC0604 0xC0000000
psu_wr 0xFFFC0608 0
psu_wr 0xFFFC060C 0
psu_wr [expr {$GEM+0x1C}] $BD
psu_wr [expr {$GEM+0x440}] 0xFFFC0600
psu_wr $GEM 0x10

psu_wr [expr {$NSEC+8}] 0
psu_wr $NSEC 0x3
after 5
psu_wr $NSEC 0x1

puts "INFO: re-AN + EEE off"
phy_an pl_mdio_wr pl_mdio_rd 1 PL
phy_an gem_mdio_wr gem_mdio_rd 0 GEM3
set st 0
for {set i 0} {$i < 40} {incr i} {
    set st [psu_rd [expr {$NSEC+4}]]
    if {$st & 4} { break }
    after 200
}
puts [format "INFO: PL STATUS=0x%08X link=%d" $st [expr {($st>>2)&1}]]

psu_wr $NSEC 0x3
after 5
psu_wr $NSEC 0x1
after 20
set ok 0
for {set i 0} {$i < 20} {incr i} {
    if {[gem_tx_one 128]} { incr ok }
    after 2
}
after 80
puts [format "RESULT_B: TXOK=%u/20 PL_RX=%u FWD=%u DPI=%u MIR=%u GEM_TXCNT=%u ST=0x%08X" \
    $ok [psu_rd [expr {$NSEC+0x10}]] [psu_rd [expr {$NSEC+0x18}]] \
    [psu_rd [expr {$NSEC+0x24}]] [psu_rd [expr {$NSEC+0x20}]] \
    [psu_rd [expr {$GEM+0x108}]] [psu_rd [expr {$NSEC+4}]]]

disconnect
exit 0
