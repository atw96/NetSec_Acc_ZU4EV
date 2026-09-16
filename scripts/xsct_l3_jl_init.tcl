# JL2XX1 vendor init (page 0xA43 / 2627, reg 25 = 0x1801) then AN + GEM TX + pkt_gen
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
    psu_wr [expr {$NSEC + 0x50}] [expr {($phy & 0x1f) | (($reg & 0x1f) << 8) | (1 << 16) | (1 << 17)}]
    after 10
}
proc pl_mdio_rd {phy reg} {
    global NSEC
    psu_wr [expr {$NSEC + 0x50}] [expr {($phy & 0x1f) | (($reg & 0x1f) << 8) | (1 << 17)}]
    after 10
    return [expr {[psu_rd [expr {$NSEC + 0x58}]] & 0xffff}]
}
proc gem_mdio_idle {} {
    global GEM
    for {set i 0} {$i < 200} {incr i} {
        if {[psu_rd [expr {$GEM + 8}]] & 4} { return }
        after 1
    }
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

proc jl_init {wr phy} {
    $wr $phy 31 2627
    $wr $phy 25 0x1801
    $wr $phy 31 0
    $wr $phy 0 0x8000
    after 80
    $wr $phy 4 0x0001
    $wr $phy 9 0x0200
    $wr $phy 0 0x1200
}

connect
after 400
catch {configparams force-mem-accesses 1}
targets -set -filter {name =~ "PSU"}
catch {jtag frequency 1000000}
catch {psu_wr 0xFD1A0104 [expr {[psu_rd 0xFD1A0104] | 1}]}
targets -set -filter {name =~ "PSU"}

puts [format "before STATUS=0x%08X RX=%u GEM TX/RX=%u/%u" \
    [psu_rd [expr {$NSEC+4}]] [psu_rd [expr {$NSEC+0x10}]] \
    [psu_rd [expr {$GEM+0x108}]] [psu_rd [expr {$GEM+0x158}]]]

puts "INFO: JL init PL PHY1"
jl_init pl_mdio_wr 1
puts "INFO: JL init GEM PHY0"
# GEM MDIO needs MDEN
psu_wr $GEM [expr {[psu_rd $GEM] | 0x10}]
jl_init gem_mdio_wr 0

set st 0
for {set i 0} {$i < 40} {incr i} {
    set st [psu_rd [expr {$NSEC+4}]]
    if {$st & 4} { break }
    after 200
}
puts [format "INFO: after JL+AN STATUS=0x%08X PL BMSR=0x%04X GEM BMSR=0x%04X" \
    $st [pl_mdio_rd 1 1] [gem_mdio_rd 0 1]]

psu_wr [expr {$NSEC+8}] 0
psu_wr $NSEC 1
# pkt_gen
psu_wr $NSEC 0x101
after 40
puts [format "pkt_gen RX=%u TX=%u FWD=%u GEM RXCNT=%u" \
    [psu_rd [expr {$NSEC+0x10}]] [psu_rd [expr {$NSEC+0x14}]] \
    [psu_rd [expr {$NSEC+0x18}]] [psu_rd [expr {$GEM+0x158}]]]

# GEM TX 8 frames
psu_wr $FRM 0xFFFFFFFF
psu_wr [expr {$FRM+4}] 0x0002FFFF
psu_wr [expr {$FRM+8}] 0xA3000000
psu_wr [expr {$FRM+12}] 0x00450008
for {set i 0} {$i < 8} {incr i} {
    psu_wr $BD $FRM
    psu_wr [expr {$BD+4}] 0x40008040
    set nw [psu_rd $GEM]
    psu_wr $GEM [expr {$nw & ~8}]
    psu_wr [expr {$GEM+0x1C}] $BD
    psu_wr $GEM [expr {($nw & ~8) | 0x18}]
    psu_wr $GEM [expr {[psu_rd $GEM] | 0x200}]
    after 4
}
after 30
puts [format "after GEM TX  CNT_RX=%u FWD=%u GEM TXCNT=%u RXCNT=%u STATUS=0x%08X" \
    [psu_rd [expr {$NSEC+0x10}]] [psu_rd [expr {$NSEC+0x18}]] \
    [psu_rd [expr {$GEM+0x108}]] [psu_rd [expr {$GEM+0x158}]] \
    [psu_rd [expr {$NSEC+4}]]]

# 100 Mbps forced on both PHYs — RGMII 25 MHz is far more timing-tolerant
puts "INFO: force 100M FDX both PHYs"
pl_mdio_wr 1 0 0x2100
gem_mdio_wr 0 0 0x2100
# GEM speed 100 + FD, drop 1000
psu_wr [expr {$GEM + 4}] [expr {0x002C0000 | 0x00000013}]
after 1500
puts [format "100M STATUS=0x%08X PL BMSR=0x%04X GEM BMSR=0x%04X" \
    [psu_rd [expr {$NSEC+4}]] [pl_mdio_rd 1 1] [gem_mdio_rd 0 1]]
set rx0 [psu_rd [expr {$NSEC+0x10}]]
for {set i 0} {$i < 8} {incr i} {
    psu_wr $BD $FRM
    psu_wr [expr {$BD+4}] 0x40008040
    set nw [psu_rd $GEM]
    psu_wr $GEM [expr {$nw & ~8}]
    psu_wr [expr {$GEM+0x1C}] $BD
    psu_wr $GEM [expr {($nw & ~8) | 0x18}]
    psu_wr $GEM [expr {[psu_rd $GEM] | 0x200}]
    after 4
}
after 40
puts [format "100M GEM TX  CNT_RX %u -> %u  GEM TXCNT=%u RXCNT=%u" \
    $rx0 [psu_rd [expr {$NSEC+0x10}]] \
    [psu_rd [expr {$GEM+0x108}]] [psu_rd [expr {$GEM+0x158}]]]
disconnect
exit 0
