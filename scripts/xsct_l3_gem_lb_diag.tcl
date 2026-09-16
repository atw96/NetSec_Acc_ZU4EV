# No rst-system / no fpga. GEM PHY BMCR loopback vs wire. Stay on PSU.
set GEM  0xFF0E0000
set NSEC 0x80050000
set BD   0xFFFC0000
set FRM  0xFFFC0100
set RXBD 0xFFFC1000
set RXBUF 0xFFFC2000

proc psu_rd {addr} {
    set s [mrd -force $addr 1]
    if {[regexp {:\s+([0-9A-Fa-f]+)} $s -> hex]} { scan $hex %x val; return $val }
    error "mrd $addr : $s"
}
proc psu_wr {addr val} { mwr -force $addr [format 0x%08X [expr {$val & 0xFFFFFFFF}]] }

proc gem_mdio_idle {} {
    global GEM
    for {set i 0} {$i < 400} {incr i} {
        if {[psu_rd [expr {$GEM + 8}]] & 4} { return 1 }
        after 1
    }
    return 0
}
proc gem_mdio_wr {phy reg val} {
    global GEM
    gem_mdio_idle
    psu_wr [expr {$GEM + 0x34}] [expr {0x50020000 | (($phy & 0x1f)<<23) | (($reg & 0x1f)<<18) | ($val & 0xffff)}]
    gem_mdio_idle
}
proc gem_mdio_rd {phy reg} {
    global GEM
    gem_mdio_idle
    psu_wr [expr {$GEM + 0x34}] [expr {0x60020000 | (($phy & 0x1f)<<23) | (($reg & 0x1f)<<18)}]
    gem_mdio_idle
    return [expr {[psu_rd [expr {$GEM + 0x34}]] & 0xffff}]
}

connect
after 400
catch {configparams force-mem-accesses 1}
targets -set -filter {name =~ "PSU"}
catch {jtag frequency 1000000}
catch {psu_wr 0xFD1A0104 [expr {[psu_rd 0xFD1A0104] | 1}]}
targets -set -filter {name =~ "PSU"}

psu_wr $GEM [expr {[psu_rd $GEM] | 0x10}]
set id1 [gem_mdio_rd 0 2]
set id2 [gem_mdio_rd 0 3]
set bmcr [gem_mdio_rd 0 0]
set bmsr [gem_mdio_rd 0 1]
puts [format "INFO: PHY0 ID=0x%04X%04X BMCR=0x%04X BMSR=0x%04X GEM_REF=0x%08X" \
    $id1 $id2 $bmcr $bmsr [psu_rd 0xFF5E005C]]
puts [format "INFO: PL STATUS=0x%08X CNT_RX=%u GEM TX/RX=%u/%u FCS=%u" \
    [psu_rd [expr {$NSEC+4}]] [psu_rd [expr {$NSEC+0x10}]] \
    [psu_rd [expr {$GEM+0x108}]] [psu_rd [expr {$GEM+0x158}]] \
    [psu_rd [expr {$GEM+0x190}]]]

# Rebuild RX ring + TX BD
for {set i 0} {$i < 8} {incr i} {
    set bd [expr {$RXBD + $i*16}]
    set buf [expr {$RXBUF + $i*1536}]
    set w0 $buf
    if {$i == 7} { set w0 [expr {$buf | 2}] }
    psu_wr $bd $w0
    psu_wr [expr {$bd+4}] 0
    psu_wr [expr {$bd+8}] 0
    psu_wr [expr {$bd+12}] 0
}
psu_wr [expr {$GEM+0x18}] $RXBD
psu_wr [expr {$GEM+0x4D4}] 0
psu_wr 0xFFFC0600 0xFFFC0700
psu_wr 0xFFFC0604 0xC0000000
psu_wr 0xFFFC0608 0
psu_wr 0xFFFC060C 0
psu_wr $GEM 0x10
psu_wr [expr {$GEM+0x1C}] $BD
psu_wr [expr {$GEM+0x440}] 0xFFFC0600
psu_wr $GEM 0x1C

proc gem_statclr {} {
    global GEM
    set nw [psu_rd $GEM]
    psu_wr $GEM [expr {$nw | 0x20}]
    after 2
    psu_wr $GEM [expr {$nw & ~0x20}]
}
proc poke_le {addr bytes} {
    set n [llength $bytes]; set i 0
    while {$i < $n} {
        set w 0
        for {set b 0} {$b < 4} {incr b} {
            if {$i < $n} { set w [expr {$w | (([lindex $bytes $i] & 0xff) << (8*$b))}]; incr i }
        }
        psu_wr $addr $w
        incr addr 4
    }
}
proc gem_tx_one {} {
    global GEM BD FRM
    set bytes {}
    foreach x {0xff 0xff 0xff 0xff 0xff 0xff 0x02 0x00 0x00 0x00 0x00 0xa3 0x08 0x00} { lappend bytes $x }
    while {[llength $bytes] < 64} { lappend bytes 0 }
    poke_le $FRM $bytes
    psu_wr $GEM 0x10
    psu_wr $BD $FRM
    psu_wr [expr {$BD+4}] [expr {0x40008000 | 64}]
    psu_wr [expr {$BD+8}] 0
    psu_wr [expr {$BD+12}] 0
    psu_wr $GEM 0x1C
    psu_wr $GEM [expr {[psu_rd $GEM] | 0x200}]
    for {set i 0} {$i < 200} {incr i} {
        if {[psu_rd [expr {$BD+4}]] & 0x80000000} { break }
        after 1
    }
}

puts "==== GEM PHY BMCR loopback ===="
gem_mdio_wr 0 0 0x4140
after 50
puts [format "  BMCR=0x%04X BMSR=0x%04X" [gem_mdio_rd 0 0] [gem_mdio_rd 0 1]]
gem_statclr
set rx0 [psu_rd [expr {$GEM+0x158}]]
set fcs0 [psu_rd [expr {$GEM+0x190}]]
set oct0 [psu_rd [expr {$GEM+0x150}]]
for {set i 0} {$i < 8} {incr i} { gem_tx_one; after 3 }
after 30
puts [format "  after8 TXCNT=%u RXCNT=%u OCTRX=%u FCS=%u SYMB=%u ALIGN=%u" \
    [psu_rd [expr {$GEM+0x108}]] [psu_rd [expr {$GEM+0x158}]] \
    [psu_rd [expr {$GEM+0x150}]] [psu_rd [expr {$GEM+0x190}]] \
    [psu_rd [expr {$GEM+0x198}]] [psu_rd [expr {$GEM+0x19C}]]]

puts "==== restore AN, wire TX ===="
gem_mdio_wr 0 0 0x1200
after 800
puts [format "  BMCR=0x%04X BMSR=0x%04X PLST=0x%08X" \
    [gem_mdio_rd 0 0] [gem_mdio_rd 0 1] [psu_rd [expr {$NSEC+4}]]]
gem_statclr
psu_wr $NSEC 0x3
after 5
psu_wr [expr {$NSEC+8}] 0
psu_wr $NSEC 0x1
after 10
for {set i 0} {$i < 8} {incr i} { gem_tx_one; after 3 }
after 40
puts [format "  wire TXCNT=%u PL_RX=%u GEM_RX=%u FCS=%u OCTRX=%u" \
    [psu_rd [expr {$GEM+0x108}]] [psu_rd [expr {$NSEC+0x10}]] \
    [psu_rd [expr {$GEM+0x158}]] [psu_rd [expr {$GEM+0x190}]] \
    [psu_rd [expr {$GEM+0x150}]]]

disconnect
exit 0
