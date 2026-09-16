# After GEM TX works: see whether PL datapath / PL TX / PL RX are alive.
# No rst-system. Stay on PSU.
set GEM  0xFF0E0000
set NSEC 0x80050000
set BD   0xFFFC0000
set FRM  0xFFFC0100

proc psu_rd {addr} {
    set s [mrd -force $addr 1]
    if {[regexp {:\s+([0-9A-Fa-f]+)} $s -> hex]} { scan $hex %x val; return $val }
    error "mrd $addr failed: $s"
}
proc psu_wr {addr val} { mwr -force $addr [format 0x%08X [expr {$val & 0xFFFFFFFF}]] }

proc nsec_dump {{tag ""}} {
    global NSEC
    puts "==== $tag ===="
    foreach {name off} {CTRL 0x00 STATUS 0x04 LB 0x08 RX 0x10 TX 0x14 FWD 0x18 DROP 0x1C MIR 0x20 DPI 0x24} {
        puts [format "  %-4s 0x%08X" $name [psu_rd [expr {$NSEC + $off}]]]
    }
    puts [format "  GEM TXCNT=%u RXCNT=%u" [psu_rd [expr {$::GEM + 0x108}]] [psu_rd [expr {$::GEM + 0x158}]]]
}

proc pl_mdio_wr {phy reg val} {
    global NSEC
    psu_wr [expr {$NSEC + 0x54}] $val
    psu_wr [expr {$NSEC + 0x50}] [expr {($phy & 0x1f) | (($reg & 0x1f) << 8) | (1 << 16) | (1 << 17)}]
    after 8
}
proc pl_mdio_rd {phy reg} {
    global NSEC
    psu_wr [expr {$NSEC + 0x50}] [expr {($phy & 0x1f) | (($reg & 0x1f) << 8) | (1 << 17)}]
    after 8
    return [expr {[psu_rd [expr {$NSEC + 0x58}]] & 0xffff}]
}

connect
after 400
catch {configparams force-mem-accesses 1}
targets -set -filter {name =~ "PSU"}
catch {jtag frequency 1000000}

# Keep A53 out of the way without the 0x3D0F hammer
catch {psu_wr 0xFD1A0104 [expr {[psu_rd 0xFD1A0104] | 0x1}]}
targets -set -filter {name =~ "PSU"}

psu_wr [expr {$NSEC + 8}] 0x0
psu_wr $NSEC 0x1
nsec_dump "before"

# L0-style inject into datapath (should bump CNT_RX by 2)
psu_wr $NSEC 0x101
after 30
nsec_dump "after pkt_gen"

# Dump PL PHY regs 0..8, 9, 10, 17, 18, 1c, 1e, 1f
puts "PL PHY regs:"
foreach r {0 1 2 3 4 5 9 10 17 18 19 27 28} {
    puts [format "  reg%02d=0x%04X" $r [pl_mdio_rd 1 $r]]
}

# RTL8211E-style: page 7, ext 0xa4, reg 0x1c bits 2=RXDLY 1=TXDLY
# Try RX delay OFF (keep TX on) then re-send from GEM
proc rtl8211e_dly {rx tx} {
    pl_mdio_wr 1 0x1f 0x0007
    pl_mdio_wr 1 0x1e 0x00a4
    set v [pl_mdio_rd 1 0x1c]
    set v [expr {($v & ~0x6) | (($rx & 1) << 2) | (($tx & 1) << 1)}]
    pl_mdio_wr 1 0x1c $v
    pl_mdio_wr 1 0x1f 0x0000
    puts [format "INFO: RTL-style dly rx=%d tx=%d reg1c=0x%04X" $rx $tx $v]
}

# GEM TX one 64B frame (Q0 already programmed if previous inject ran)
proc gem_kick {} {
    global GEM BD FRM
    psu_wr $FRM 0xFFFFFFFF
    psu_wr [expr {$FRM + 4}] 0x0002FFFF
    psu_wr [expr {$FRM + 8}] 0xA3000000
    psu_wr [expr {$FRM + 12}] 0x00450008
    psu_wr $BD $FRM
    psu_wr [expr {$BD + 4}] 0x40008040
    set nw [psu_rd $GEM]
    psu_wr $GEM [expr {$nw & ~8}]
    psu_wr [expr {$GEM + 0x1C}] $BD
    psu_wr $GEM [expr {($nw & ~8) | 0x18}]
    psu_wr $GEM [expr {[psu_rd $GEM] | 0x200}]
    after 5
}

foreach {rx tx name} {1 1 id  0 1 txid  1 0 rxid  0 0 node} {
    rtl8211e_dly $rx $tx
    after 20
    set rx0 [psu_rd [expr {$NSEC + 0x10}]]
    for {set i 0} {$i < 4} {incr i} { gem_kick }
    after 20
    set rx1 [psu_rd [expr {$NSEC + 0x10}]]
    puts [format "TUNE %s CNT_RX %u -> %u  GEM TXCNT=%u RXCNT=%u" \
        $name $rx0 $rx1 [psu_rd [expr {$GEM + 0x108}]] [psu_rd [expr {$GEM + 0x158}]]]
}

nsec_dump "final"
disconnect
exit 0
