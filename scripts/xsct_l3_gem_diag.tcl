# Quick GEM3 TX diagnosis: clocks, 32-bit DMA, local loopback
set GEM 0xFF0E0000
set BD  0xFFFC0000
set FRM 0xFFFC0100

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
psu_wr 0xFD1A0104 0x00003D0F

puts [format "CRL GEM3_REF  0xFF5E005C = 0x%08X" [psu_rd 0xFF5E005C]]
puts [format "CRL RST_IOU0  0xFF5E0230 = 0x%08X" [psu_rd 0xFF5E0230]]
puts [format "CRL IOPLLCTRL 0xFF5E0020 = 0x%08X" [psu_rd 0xFF5E0020]]
puts [format "CRL PLL_STAT  0xFF5E0044 = 0x%08X" [psu_rd 0xFF5E0044]]
catch {puts [format "IOU GEM_CLK   0xFF180308 = 0x%08X" [psu_rd 0xFF180308]]}

# Re-apply GEM3 125 MHz-ish ref: CLKACT off then on
psu_wr 0xFF5E005C 0x00010800
after 10
psu_wr 0xFF5E005C 0x06010800
set rst [psu_rd 0xFF5E0230]
psu_wr 0xFF5E0230 [expr {$rst & ~0x8}]
after 10
puts [format "CRL GEM3_REF after = 0x%08X RST=0x%08X" [psu_rd 0xFF5E005C] [psu_rd 0xFF5E0230]]

# 32-bit DMA, INCR4, local loopback
psu_wr $GEM 0x0
psu_wr [expr {$GEM + 4}] [expr {0x00200000 | 0x000C0000 | 0x00000400 | 0x00000002}]
psu_wr [expr {$GEM + 0x10}] 0x00180704
psu_wr [expr {$GEM + 0x88}] 0x00000002
psu_wr [expr {$GEM + 0x8C}] 0x0000A300
psu_wr [expr {$GEM + 0x14}] 0xFF
psu_wr [expr {$GEM + 0x2C}] 0xFFFFFFFF

# frame: 64 bytes of broadcast eth
psu_wr $FRM 0xFFFFFFFF
psu_wr [expr {$FRM + 4}] 0x0002FFFF
psu_wr [expr {$FRM + 8}] 0xA3000000
psu_wr [expr {$FRM + 12}] 0x00000008
for {set a [expr {$FRM + 16}]} {$a < $FRM + 64} {incr a 4} { psu_wr $a 0 }

# 2-word BD (32-bit addressing)
psu_wr $BD $FRM
psu_wr [expr {$BD + 4}] [expr {0x40008000 | 64}]
psu_wr 0xFFFC0600 0xFFFC0700
psu_wr 0xFFFC0604 0xC0000000
psu_wr [expr {$GEM + 0x1C}] $BD
psu_wr [expr {$GEM + 0x440}] 0xFFFC0600
psu_wr [expr {$GEM + 0x4C8}] 0

# MDEN | TXEN | LOOPEN
psu_wr $GEM 0x1A
after 5
psu_wr $GEM [expr {[psu_rd $GEM] | 0x200}]

set done 0
for {set i 0} {$i < 300} {incr i} {
    set st [psu_rd [expr {$BD + 4}]]
    if {$st & 0x80000000} { set done 1; break }
    after 1
}
puts [format "LOOPBACK 32bit: done=%d BD=0x%08X TXSR=0x%08X ISR=0x%08X TXCNT=%u NW=0x%08X DMACR=0x%08X" \
    $done [psu_rd [expr {$BD + 4}]] [psu_rd [expr {$GEM + 0x14}]] \
    [psu_rd [expr {$GEM + 0x24}]] [psu_rd [expr {$GEM + 0x108}]] \
    [psu_rd $GEM] [psu_rd [expr {$GEM + 0x10}]]]

# Try 100 Mbps + loopback if still dead
if {!$done} {
    psu_wr $GEM 0x10
    psu_wr [expr {$GEM + 4}] [expr {0x00200000 | 0x000C0000 | 0x00000003}]
    psu_wr $BD $FRM
    psu_wr [expr {$BD + 4}] [expr {0x40008000 | 64}]
    psu_wr [expr {$GEM + 0x1C}] $BD
    psu_wr $GEM 0x1A
    after 5
    psu_wr $GEM [expr {[psu_rd $GEM] | 0x200}]
    for {set i 0} {$i < 300} {incr i} {
        if {[psu_rd [expr {$BD + 4}]] & 0x80000000} { set done 1; break }
        after 1
    }
    puts [format "LOOPBACK 100M: done=%d BD=0x%08X TXSR=0x%08X TXCNT=%u NWCFG=0x%08X" \
        $done [psu_rd [expr {$BD + 4}]] [psu_rd [expr {$GEM + 0x14}]] \
        [psu_rd [expr {$GEM + 0x108}]] [psu_rd [expr {$GEM + 4}]]]
}

disconnect
exit 0
