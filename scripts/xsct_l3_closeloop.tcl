################################################################################
# L3 close-loop (PSU, no A53 halt):
#   rst-system → TCK 100 kHz fpga → psu_init → hold CPU0 only
#   → GEM3 TX+RX → Dir A pkt_gen → Dir B 20 frames
# argv0 = bitstream path (optional; default system_top_rxdly.bit)
################################################################################
set repo [file normalize [file join [file dirname [info script]] ..]]
set bit  [lindex $::argv 0]
if {$bit eq ""} {
    set bit [file join $repo bitstream_output system_top_rxdly.bit]
}
set bit [file normalize $bit]
if {![file exists $bit]} { error "missing $bit" }

set GEM   0xFF0E0000
set NSEC  0x80050000
set BD    0xFFFC0000
set FRM   0xFFFC0100
set RXBD  0xFFFC1000
set RXBUF 0xFFFC2000
set NRX   8

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

proc nsec_dump {{tag ""}} {
    global NSEC
    if {$tag ne ""} { puts "==== $tag ====" }
    foreach {name off} {
        CTRL 0x00 STATUS 0x04 LOOPBACK 0x08
        CNT_RX 0x10 CNT_TX 0x14 CNT_FWD 0x18
        CNT_DROP 0x1C CNT_MIR 0x20 CNT_DPI 0x24
    } {
        puts [format "  %-8s @+%02X = 0x%08X" $name $off [psu_rd [expr {$NSEC + $off}]]]
    }
}

proc gem_rx_dump {{tag "GEM RX"}} {
    global GEM
    puts "==== $tag ===="
    foreach {name off} {
        OCTRXL 0x150 RXCNT 0x158 RXBCAST 0x15C
        UNDR 0x184 OVR 0x188 JAB 0x18C
        FCS 0x190 LENERR 0x194 SYMB 0x198
        ALIGN 0x19C RESERR 0x1A0 OR 0x1A4
        TXCNT 0x108 TXSR 0x14 NWCTRL 0x00
    } {
        puts [format "  %-8s @+%03X = 0x%08X" $name $off [psu_rd [expr {$GEM + $off}]]]
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
    $wr $phy 31 0xA43
    set cr1 [$rd $phy 24]
    $wr $phy 24 [expr {$cr1 & ~0x0006}]
    $wr $phy 31 0
    puts [format "INFO: PHY%u ALDPS/EEE off PHYCR1=0x%04X" $phy $cr1]
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

proc gem_statclr {} {
    global GEM
    set nw [psu_rd $GEM]
    psu_wr $GEM [expr {$nw | 0x20}]
    after 2
    psu_wr $GEM [expr {$nw & ~0x20}]
}

proc gem_setup_rx_ring {} {
    global GEM RXBD RXBUF NRX
    for {set i 0} {$i < $NRX} {incr i} {
        set bd  [expr {$RXBD + $i * 16}]
        set buf [expr {$RXBUF + $i * 1536}]
        set w0  $buf
        if {$i == ($NRX - 1)} { set w0 [expr {$buf | 0x2}] }
        psu_wr $bd $w0
        psu_wr [expr {$bd + 4}] 0
        psu_wr [expr {$bd + 8}] 0
        psu_wr [expr {$bd + 12}] 0
    }
    psu_wr [expr {$GEM + 0x18}] $RXBD
    psu_wr [expr {$GEM + 0x4D4}] 0
}

proc gem_arm_tx {{nwmask 0x1C}} {
    global GEM BD
    # 2020.1 BSP: word0=addr, word1=stat (USED/WRAP/LAST/len), word2=addr_hi
    psu_wr 0xFFFC0600 0xFFFC0700
    psu_wr 0xFFFC0604 0xC0000000
    psu_wr 0xFFFC0608 0
    psu_wr 0xFFFC060C 0
    psu_wr $GEM 0x10
    after 2
    psu_wr [expr {$GEM + 0x1C}] $BD
    psu_wr [expr {$GEM + 0x440}] 0xFFFC0600
    psu_wr [expr {$GEM + 0x4C8}] 0
    psu_wr $GEM $nwmask
}

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

proc gem_enable {} {
    global GEM
    psu_wr $GEM 0x1C
}

# JL2121 is RTL8211F pin-compatible. RGMII delay: page 0xD08.
proc jl_rgmii_rxdly {wr rd phy enable} {
    $wr $phy 31 0x0D08
    set v [$rd $phy 0x15]
    if {$enable} { set v [expr {$v | 0x8}] } else { set v [expr {$v & ~0x8}] }
    $wr $phy 0x15 $v
    $wr $phy 31 0
    return $v
}

proc jl_rgmii_txdly {wr rd phy enable} {
    $wr $phy 31 0x0D08
    set v [$rd $phy 0x11]
    if {$enable} { set v [expr {$v | 0x100}] } else { set v [expr {$v & ~0x100}] }
    $wr $phy 0x11 $v
    $wr $phy 31 0
    return $v
}

proc jl_a43_reg25 {wr phy val} {
    $wr $phy 31 2627
    $wr $phy 25 $val
    $wr $phy 31 0
}

proc jl_dump_dly {wr rd phy tag} {
    $wr $phy 31 0x0D08
    set r11 [$rd $phy 0x11]
    set r15 [$rd $phy 0x15]
    $wr $phy 31 2627
    set r25 [$rd $phy 25]
    $wr $phy 31 0
    puts [format "INFO: %s PHY%u d08.11=0x%04X d08.15=0x%04X a43.25=0x%04X" \
        $tag $phy $r11 $r15 $r25]
}

proc gem_reinit_mac {} {
    global GEM
    # Hard-reset GEM3 so a prior RX DMA cannot leave TX wedged.
    set iou [psu_rd 0xFF5E0230]
    psu_wr 0xFF5E0230 [expr {$iou | 0x8}]
    after 5
    psu_wr 0xFF5E0230 [expr {$iou & ~0x8}]
    after 10
    psu_wr $GEM 0x0
    psu_wr [expr {$GEM + 4}] [expr {0x00200000 | 0x000C0000 | 0x00000400 | 0x00000012}]
    psu_wr [expr {$GEM + 0x10}] 0x40180704
    psu_wr [expr {$GEM + 0x88}] 0x00000002
    psu_wr [expr {$GEM + 0x8C}] 0x0000A300
    psu_wr [expr {$GEM + 0x14}] 0xFF
    psu_wr [expr {$GEM + 0x20}] 0x0F
    psu_wr [expr {$GEM + 0x2C}] 0xFFFFFFFF
    psu_wr $GEM 0x10
}

proc build_frame {attack idx} {
    set b {}
    foreach x {0xff 0xff 0xff 0xff 0xff 0xff 0x02 0x00 0x00 0x00 0x00 0xa3 0x08 0x00} {
        lappend b $x
    }
    lappend b 0x45 0x00 0x00 80 0x00 0x00 0x40 0x00 64 6
    if {$attack} {
        lappend b 10 0 0 5
    } else {
        lappend b 192 168 1 2
    }
    lappend b 192 168 1 100
    lappend b [expr {0x30 + (($idx >> 8) & 0xff)}] [expr {$idx & 0xff}] 0x00 80
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
    # Verified PSU path: TXEN off → rewrite BD → MDEN|TXEN (0x18) → STARTTX
    psu_wr $GEM 0x10
    psu_wr $BD $FRM
    psu_wr [expr {$BD + 4}] [expr {0x40008000 | ([llength $bytes] & 0x3fff)}]
    psu_wr [expr {$BD + 8}] 0
    psu_wr [expr {$BD + 12}] 0
    psu_wr $GEM 0x18
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
    puts [format "WARN: TX timeout BD=0x%08X TXSR=0x%08X Q0=0x%08X Q1=0x%08X NW=0x%08X" \
        [psu_rd [expr {$BD + 4}]] [psu_rd [expr {$GEM + 0x14}]] \
        [psu_rd [expr {$GEM + 0x1C}]] [psu_rd [expr {$GEM + 0x440}]] [psu_rd $GEM]]
    psu_wr [expr {$GEM + 0x14}] 0xFF
    return 0
}

puts "INFO: bit=$bit"
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

# Hold CPU0 only — never write 0x3D0F
set rst [psu_rd 0xFD1A0104]
psu_wr 0xFD1A0104 [expr {$rst | 0x1}]
after 50
psu_retarget
puts [format "INFO: hold CPU0 RST=0x%08X" [psu_rd 0xFD1A0104]]

# Arm PL wire mode
psu_wr $NSEC 0x3
after 5
psu_wr [expr {$NSEC + 8}] 0x0
psu_wr $NSEC 0x1
after 20
nsec_dump "PL after arm"

set st0 [psu_rd [expr {$NSEC + 4}]]
if {($st0 & 0x4) == 0} {
    puts "INFO: PL PHY AN (addr 1)"
    phy_an pl_mdio_wr pl_mdio_rd 1 PL
} else {
    puts "INFO: skip PL PHY AN, link already up"
}

# GEM3 clock + out of reset
catch {psu_wr 0xFF5E005C 0x06010800}
set iou [psu_rd 0xFF5E0230]
psu_wr 0xFF5E0230 [expr {$iou & ~0x8}]
after 10

psu_wr $GEM 0x0
psu_wr [expr {$GEM + 4}] [expr {0x00200000 | 0x000C0000 | 0x00000400 | 0x00000012}]
psu_wr [expr {$GEM + 0x10}] 0x40180704
psu_wr [expr {$GEM + 0x88}] 0x00000002
psu_wr [expr {$GEM + 0x8C}] 0x0000A300
psu_wr [expr {$GEM + 0x14}] 0xFF
psu_wr [expr {$GEM + 0x20}] 0x0F
psu_wr [expr {$GEM + 0x2C}] 0xFFFFFFFF
psu_wr $GEM 0x10
after 5

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

# Dummy RX (USED|WRAP) + TX queues. Dir B first — same path as xsct_l3_psu_inject.
psu_wr 0xFFFC0400 0xFFFC0502
psu_wr 0xFFFC0404 0
psu_wr 0xFFFC0408 0
psu_wr 0xFFFC040C 0
psu_wr [expr {$GEM + 0x18}] 0xFFFC0400
psu_wr [expr {$GEM + 0x4D4}] 0
gem_arm_tx 0x10
after 5
puts [format "INFO: GEM NWCTRL=0x%08X DMACR=0x%08X RXQ=0x%08X TXQ=0x%08X" \
    [psu_rd $GEM] [psu_rd [expr {$GEM + 0x10}]] \
    [psu_rd [expr {$GEM + 0x18}]] [psu_rd [expr {$GEM + 0x1C}]]]

# -------- Dir B: GEM TX 20 frames → PL counters (before RXEN) --------
puts "INFO: probe TX on Q0"
gem_arm_queues 0
set probe 0
if {[gem_tx_one [build_frame 0 0]]} {
    set probe 0
} else {
    puts "INFO: probe TX on Q1"
    gem_arm_queues 1
    if {[gem_tx_one [build_frame 0 0]]} { set probe 1 } else { set probe -1 }
}
puts [format "INFO: DirB live queue=%d" $probe]

jl_dump_dly pl_mdio_wr pl_mdio_rd 1 PL
jl_dump_dly gem_mdio_wr gem_mdio_rd $gphy GEM3

# Sweep PL RX / PS TX 2ns delay (RTL8211F page 0xD08) if the first path is silent.
proc dirb_probe_n {n} {
    global NSEC
    psu_wr $NSEC 0x3
    after 5
    psu_wr [expr {$NSEC + 8}] 0
    psu_wr $NSEC 0x1
    after 10
    for {set i 0} {$i < $n} {incr i} {
        gem_tx_one [build_frame 0 $i]
        after 2
    }
    after 40
    return [psu_rd [expr {$NSEC + 0x10}]]
}

set best_rx -1
set best_rxn 0
if {$probe >= 0} {
    set n0 [dirb_probe_n 2]
    puts [format "INFO: DirB default CNT_RX=%u" $n0]
    if {$n0 == 0} {
        foreach {plrx pstx name} {
            1 1 plrx1_pstx1
            0 1 plrx0_pstx1
            1 0 plrx1_pstx0
            0 0 plrx0_pstx0
        } {
            jl_rgmii_rxdly pl_mdio_wr pl_mdio_rd 1 $plrx
            jl_rgmii_txdly gem_mdio_wr gem_mdio_rd $gphy $pstx
            after 20
            set n [dirb_probe_n 4]
            puts [format "INFO: TUNE %s CNT_RX=%u" $name $n]
            if {$n > $best_rxn} {
                set best_rxn $n
                set best_rx [list $plrx $pstx $name]
            }
        }
        if {$best_rxn == 0} {
            foreach val {0x1801 0x0801 0x1001 0x0001 0x1C01 0x1401} {
                jl_a43_reg25 pl_mdio_wr 1 $val
                after 20
                set n [dirb_probe_n 4]
                puts [format "INFO: TUNE a43.25=0x%04X CNT_RX=%u" $val $n]
                if {$n > $best_rxn} {
                    set best_rxn $n
                    set best_rx [list a43 $val]
                }
            }
        }
        if {$best_rxn > 0} {
            puts [format "INFO: DirB delay winner %s CNT_RX=%u" $best_rx $best_rxn]
            if {[llength $best_rx] == 3} {
                jl_rgmii_rxdly pl_mdio_wr pl_mdio_rd 1 [lindex $best_rx 0]
                jl_rgmii_txdly gem_mdio_wr gem_mdio_rd $gphy [lindex $best_rx 1]
            }
        } else {
            puts "WARN: DirB delay sweep all CNT_RX=0"
        }
    }
}

psu_wr $NSEC 0x3
after 5
psu_wr [expr {$NSEC + 8}] 0
psu_wr $NSEC 0x1
after 20

set ok 0
for {set i 0} {$i < 16} {incr i} {
    if {[gem_tx_one [build_frame 0 $i]]} { incr ok }
    after 2
}
for {set i 0} {$i < 4} {incr i} {
    if {[gem_tx_one [build_frame 1 $i]]} { incr ok }
    after 2
}
after 100
nsec_dump "DirB after GEM TX"
set cnt_rx  [psu_rd [expr {$NSEC + 0x10}]]
set cnt_fwd [psu_rd [expr {$NSEC + 0x18}]]
set cnt_dpi [psu_rd [expr {$NSEC + 0x24}]]
set cnt_mir [psu_rd [expr {$NSEC + 0x20}]]
set txcnt   [psu_rd [expr {$GEM + 0x108}]]
set verdict_b "B_FAIL"
if {$cnt_rx >= 16 && $cnt_fwd >= 12} { set verdict_b "B_PASS" }
puts [format "RESULT_B: verdict=%s RX=%u FWD=%u DPI=%u MIR=%u TXOK=%u/%u GEM_TXCNT=%u" \
    $verdict_b $cnt_rx $cnt_fwd $cnt_dpi $cnt_mir $ok 20 $txcnt]

# -------- Dir A: PL pkt_gen → cable → GEM RX stats --------
gem_setup_rx_ring
psu_wr $GEM 0x1C
after 5
gem_statclr
after 5
psu_wr $NSEC 0x101
after 80
set octrx  [psu_rd [expr {$GEM + 0x150}]]
set rxcnt  [psu_rd [expr {$GEM + 0x158}]]
set fcs    [psu_rd [expr {$GEM + 0x190}]]
set symb   [psu_rd [expr {$GEM + 0x198}]]
set align  [psu_rd [expr {$GEM + 0x19C}]]
set reserr [psu_rd [expr {$GEM + 0x1A0}]]
set undr   [psu_rd [expr {$GEM + 0x184}]]
set orun   [psu_rd [expr {$GEM + 0x1A4}]]
nsec_dump "DirA after pkt_gen"
gem_rx_dump "DirA GEM stats"

set verdict_a "A_UNKNOWN"
if {$rxcnt > 0} {
    set verdict_a "A_PASS"
} elseif {$reserr > 0} {
    set verdict_a "A_BD_ERR"
} elseif {$octrx == 0 && $fcs == 0 && $symb == 0 && $align == 0} {
    set verdict_a "A_NO_SIGNAL"
} elseif {$octrx > 0 || $fcs > 0 || $symb > 0 || $align > 0} {
    set verdict_a "A_SKEW"
}
puts [format "RESULT_A: verdict=%s OCTRX=%u RXCNT=%u FCS=%u SYMB=%u ALIGN=%u RESERR=%u UNDR=%u OR=%u" \
    $verdict_a $octrx $rxcnt $fcs $symb $align $reserr $undr $orun]

# Replay the GEM-received frame back toward PL (known-good on-wire bytes).
if {$rxcnt > 0} {
    set rx0 [psu_rd $RXBD]
    set rxs [psu_rd [expr {$RXBD + 4}]]
    set rlen [expr {$rxs & 0x1fff}]
    if {$rlen < 64} { set rlen 64 }
    if {$rlen > 1518} { set rlen 128 }
    puts [format "INFO: replay RXBD w0=0x%08X stat=0x%08X len=%u" $rx0 $rxs $rlen]
    psu_wr $NSEC 0x3
    after 5
    psu_wr [expr {$NSEC + 8}] 0
    psu_wr $NSEC 0x1
    after 15
    gem_arm_queues 0
    psu_wr $GEM 0x10
    psu_wr $BD $RXBUF
    psu_wr [expr {$BD + 4}] [expr {0x40008000 | ($rlen & 0x3fff)}]
    psu_wr [expr {$BD + 8}] 0
    psu_wr [expr {$BD + 12}] 0
    psu_wr $GEM 0x18
    psu_wr $GEM [expr {[psu_rd $GEM] | 0x200}]
    after 40
    puts [format "INFO: replay PL_RX=%u GEM_TXCNT=%u BD=0x%08X" \
        [psu_rd [expr {$NSEC + 0x10}]] [psu_rd [expr {$GEM + 0x108}]] \
        [psu_rd [expr {$BD + 4}]]]
}

set pass 0
if {$cnt_rx >= 16 && $cnt_fwd >= 12 && $cnt_dpi >= 3 && $cnt_mir >= 3 && $rxcnt > 0} {
    set pass 1
}
puts [format "PASS: %d  bit=%s" $pass [file tail $bit]]

disconnect
exit 0
