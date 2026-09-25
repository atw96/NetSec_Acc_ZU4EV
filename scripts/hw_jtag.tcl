################################################################################
# scripts/hw_jtag.tcl
# Program the board and poke netsec_regs via jtag_axi (Hardware Manager).
#
# From Vivado Tcl console (GUI or batch with hw_server running):
#   source scripts/hw_jtag.tcl
#   nsec_connect
#   nsec_program                          ;# default: bitstream_output/system_top_rxdly.bit
#   nsec_dump
#   nsec_l0_test
#   nsec_l1_test
################################################################################

set ::NSEC_BASE 0x80050000

proc nsec_connect {} {
    open_hw_manager
    catch {connect_hw_server}
    foreach t [get_hw_targets -quiet] {
        catch {set_property PARAM.FREQUENCY 1000000 $t}
    }
    open_hw_target
    set devs [get_hw_devices]
    if {[llength $devs] == 0} {
        error "No hw_devices. Check JTAG cable and boot mode (prefer JTAG)."
    }
    # Prefer the PL fabric device (xczu4_0 / xczu*) over ARM DAP
    set fab [lsearch -inline -regexp $devs {xczu|xc7|xck}]
    if {$fab eq ""} {
        set fab [lindex $devs 0]
    }
    current_hw_device $fab
    refresh_hw_device [current_hw_device]
    puts "INFO: current_hw_device = [current_hw_device]"
}

proc nsec_program {{bit ""}} {
    if {$bit eq ""} {
        set repo [file normalize [file join [file dirname [info script]] ..]]
        set bit [file join $repo bitstream_output system_top_rxdly.bit]
        if {![file exists $bit]} {
            set bit [file join $repo bitstream_output system_top.bit]
        }
    }
    if {![file exists $bit]} {
        error "Bitstream not found: $bit"
    }
    set_property PROGRAM.FILE $bit [current_hw_device]
    program_hw_devices [current_hw_device]
    refresh_hw_device [current_hw_device]
    puts "INFO: programmed $bit"
}

proc nsec_axi {} {
    set axi [get_hw_axis -quiet]
    if {[llength $axi] == 0} {
        error "No hw_axi (jtag_axi) cores. Is the bitstream the JTAG-AXI build?"
    }
    return [lindex $axi 0]
}

proc nsec_txn_data {txn} {
    set obj [get_hw_axi_txns $txn]
    # DATA is the write payload; on reads it is stale. Prefer the read value.
    foreach p {OUTPUT.VALUE OUTPUT_VALUE READ_DATA} {
        if {[lsearch -exact [list_property $obj] $p] >= 0} {
            set v [get_property $p $obj]
            if {$v ne ""} { return $v }
        }
    }
    set rpt ""
    catch {set rpt [report_hw_axi_txn $txn]}
    if {[regexp {READ DATA is: ([0-9A-Fa-f]+)} $rpt -> m]} { return $m }
    if {[regexp {([0-9A-Fa-f]{8})} $rpt m]} { return $m }
    return "XXXXXXXX"
}

proc nsec_wr {off val} {
    set addr [format 0x%08X [expr {$::NSEC_BASE + $off}]]
    set txn nsec_w_[clock clicks]
    create_hw_axi_txn $txn [nsec_axi] -type write -address $addr -len 1 -data [format %08X $val]
    run_hw_axi $txn
    delete_hw_axi_txn $txn
}

proc nsec_rd {off} {
    set addr [format 0x%08X [expr {$::NSEC_BASE + $off}]]
    set txn nsec_r_[clock clicks]
    create_hw_axi_txn $txn [nsec_axi] -type read -address $addr -len 1
    run_hw_axi $txn
    set obj [get_hw_axi_txns $txn]
    set data [get_property DATA $obj]
    if {$data eq ""} { set data [nsec_txn_data $txn] }
    delete_hw_axi_txn $txn
    return "0x$data"
}

proc nsec_dump {} {
    puts "CTRL     [nsec_rd 0x00]"
    puts "STATUS   [nsec_rd 0x04]"
    puts "LOOPBACK [nsec_rd 0x08]"
    puts "CNT_RX   [nsec_rd 0x10]"
    puts "CNT_TX   [nsec_rd 0x14]"
    puts "CNT_FWD  [nsec_rd 0x18]"
    puts "CNT_DROP [nsec_rd 0x1C]"
    puts "CNT_MIR  [nsec_rd 0x20]"
    puts "CNT_DPI  [nsec_rd 0x24]"
    puts "MAC_GOOD [nsec_rd 0x28]"
    puts "MAC_FCS  [nsec_rd 0x2C]"
    puts "DPI_PAT0 [nsec_rd 0x40]"
    puts "MDIO_RD  [nsec_rd 0x58]"
    puts "RGMII_DLY [nsec_rd 0x5C]"
    puts "SFP_ST   [nsec_rd 0x60]"
    puts "MAC_BADF [nsec_rd 0x64]"
    puts "MAC_TXG  [nsec_rd 0x68]"
    puts "RGMII_ACT [nsec_rd 0x6C]"
    puts "AES_PT0  [nsec_rd 0x70]"
    puts "AES_CT0  [nsec_rd 0x80]"
    puts "CSUM_R   [nsec_rd 0x94]"
    puts "MX_BASE  [nsec_rd 0x98]"
    puts "MX_RES   [nsec_rd 0xA4]"
    puts "AES_DP0  [nsec_rd 0xB0]"
    puts "AES_DP3  [nsec_rd 0xBC]"
    puts "SFP10G_ST [nsec_rd 0xC0]"
    puts "SFP10G_TX0 [nsec_rd 0xC4]"
    puts "SFP10G_RX0 [nsec_rd 0xC8]"
    puts "SFP10G_BD0 [nsec_rd 0xCC]"
    puts "SFP10G_TX1 [nsec_rd 0xD0]"
    puts "SFP10G_RX1 [nsec_rd 0xD4]"
    puts "SFP10G_BD1 [nsec_rd 0xD8]"
    puts "SFP10G_CTRL [nsec_rd 0xDC]"
}

proc nsec_sfp10g_dump {} {
    puts "SFP10G_ST   [nsec_rd 0xC0]"
    puts "SFP10G_TX0  [nsec_rd 0xC4]"
    puts "SFP10G_RX0  [nsec_rd 0xC8]"
    puts "SFP10G_BAD0 [nsec_rd 0xCC]"
    puts "SFP10G_TX1  [nsec_rd 0xD0]"
    puts "SFP10G_RX1  [nsec_rd 0xD4]"
    puts "SFP10G_BAD1 [nsec_rd 0xD8]"
    puts "SFP10G_CTRL [nsec_rd 0xDC]"
}

# Default system_top image: 10G counters at 0xC0 (not the standalone 0x04/0x10 map).
proc nsec_sfp10g_check {} {
    nsec_wr 0xDC 0x1
    after 2000
    set st  [nsec_rd 0xC0]
    set tx0 [nsec_rd 0xC4]
    set rx0 [nsec_rd 0xC8]
    set bd0 [nsec_rd 0xCC]
    set tx1 [nsec_rd 0xD0]
    set rx1 [nsec_rd 0xD4]
    set bd1 [nsec_rd 0xD8]
    puts "SFP10G t0 ST=$st TX0=$tx0 RX0=$rx0 BAD0=$bd0 TX1=$tx1 RX1=$rx1 BAD1=$bd1"
    after 3000
    set st2  [nsec_rd 0xC0]
    set tx0b [nsec_rd 0xC4]
    set rx0b [nsec_rd 0xC8]
    set bd0b [nsec_rd 0xCC]
    set tx1b [nsec_rd 0xD0]
    set rx1b [nsec_rd 0xD4]
    set bd1b [nsec_rd 0xD8]
    puts "SFP10G t1 ST=$st2 TX0=$tx0b RX0=$rx0b BAD0=$bd0b TX1=$tx1b RX1=$rx1b BAD1=$bd1b"
    set stn 0
    set rx0n 0
    set rx1n 0
    set rx0g 0
    set rx1g 0
    catch {set stn  [expr {$st2}]}
    catch {set rx0n [expr {$rx0b}]}
    catch {set rx1n [expr {$rx1b}]}
    catch {set rx0g [expr {$rx0b - $rx0}]}
    catch {set rx1g [expr {$rx1b - $rx1}]}
    set lock0 [expr {($stn >> 8) & 1}]
    set lock1 [expr {($stn >> 9) & 1}]
    if {$lock0 && $lock1 && $rx0n > 0 && $rx1n > 0 && $rx0g > 0 && $rx1g > 0} {
        puts "PASS: 10G on default system_top (block_lock + RX growing)"
    } else {
        puts "NEED_HW: expect 0xC0 bit8/bit9=1 and 0xC8/0xD4 growing (fiber SFP1<->SFP2)."
    }
}

proc nsec_mdio_read {reg {phy 1}} {
    set ctrl [expr {($phy & 0x1F) | (($reg & 0x1F) << 8) | (0 << 16) | (1 << 17)}]
    nsec_wr 0x50 $ctrl
    after 20
    return [nsec_rd 0x58]
}

proc nsec_mdio_write {reg val {phy 1}} {
    nsec_wr 0x54 $val
    set ctrl [expr {($phy & 0x1F) | (($reg & 0x1F) << 8) | (1 << 16) | (1 << 17)}]
    nsec_wr 0x50 $ctrl
    after 20
    return [nsec_rd 0x58]
}

proc nsec_l0_test {} {
    # keep enable=1 while pulsing soft_reset so enable CDC does not drop
    nsec_wr 0x00 0x3
    after 5
    nsec_wr 0x08 0x1
    after 2
    nsec_wr 0x00 0x101
    after 50
    nsec_dump
    puts "L0: expect CNT_RX=2 CNT_FWD>=1 CNT_TX>=1 CNT_DPI>=1 (GET -> CNT_MIR, not DROP)"
}

proc nsec_l1_test {} {
    nsec_wr 0x00 0x3
    after 5
    nsec_wr 0x08 0x2
    after 2
    nsec_wr 0x00 0x101
    after 50
    nsec_dump
    puts "L1: expect CNT_RX=2 CNT_FWD>=1 CNT_TX>=1; no RGMII TX (ILA-A probe3)"
}

proc nsec_mdio_id {{phy 1}} {
    set id1 [nsec_mdio_read 2 $phy]
    after 5
    set id2 [nsec_mdio_read 3 $phy]
    puts "PHY$phy MDIO ID1=$id1 ID2=$id2  (BMSR [nsec_mdio_read 1 $phy])"
}

proc nsec_phy_1g_an {{phy 1}} {
    # Dual-port cable: both PHYs must auto-negotiate master/slave.
    # Do NOT use BMCR 0x4140 here (force 1000 + AN-off + loopback).
    nsec_mdio_write 0 0x8000 $phy
    after 50
    # Advertisement: no 10/100, keep selector 00001, pause optional
    nsec_mdio_write 4 0x0001 $phy
    # 1000BASE-T control: advertise 1000 full only
    nsec_mdio_write 9 0x0200 $phy
    # BMCR: AN enable + restart
    nsec_mdio_write 0 0x1200 $phy
    after 200
    set bmsr ""
    for {set i 0} {$i < 25} {incr i} {
        set bmsr [nsec_mdio_read 1 $phy]
        # bit5=AN complete, bit2=link (in low 16 of 0x58)
        if {[regexp {([0-9A-Fa-f]{8})} $bmsr m]} {
            scan $m %x w
            if {($w & 0x24) == 0x24} { break }
        }
        after 200
    }
    puts "PHY$phy 1G AN BMSR=$bmsr STATUS=[nsec_rd 0x04]"
}

proc nsec_l2_test {} {
    # Single-port PHY loopback ONLY. Dual-port cable must use nsec_phy_1g_an.
    # IEEE BMCR: 1000 Mbps, AN off, PHY loopback (bit14)
    nsec_mdio_write 0 0x4140
    after 20
    nsec_wr 0x00 0x3
    after 5
    nsec_wr 0x08 0x3
    after 2
    nsec_wr 0x00 0x101
    after 50
    nsec_dump
    puts "L2: PHY BMCR=0x4140 LOOPBACK=3; RGMII OK if CNT_RX>=4 after reset (2 gen + 2 echo)"
}

proc nsec_l3_monitor {} {
    nsec_wr 0x08 0x0
    nsec_wr 0x00 0x1
    nsec_dump
    puts "L3: LOOPBACK=0. Drive PS GEM3 or PC traffic; re-run nsec_dump."
}

proc nsec_l4_test {} {
    nsec_wr 0x08 0x0
    nsec_wr 0x00 0x1
    nsec_wr 0xDC 0x1
    after 20
    set st [nsec_rd 0xC0]
    nsec_sfp10g_dump
    nsec_dump
    puts "L4: default image 10G fiber (LOOPBACK=0). SFP10G_ST=$st bit8/9=block_lock. Near-end PMA is LOOPBACK=4."
}

proc nsec_wait_link {{tries 40}} {
    for {set i 0} {$i < $tries} {incr i} {
        set st [nsec_rd 0x04]
        if {[regexp {([0-9A-Fa-f]{8})} $st m]} {
            scan $m %x w
            if {($w & 0x4) != 0} {
                puts "INFO: phy_link=1 STATUS=$st"
                return 1
            }
        }
        after 250
    }
    puts "WARN: phy_link not set STATUS=[nsec_rd 0x04]"
    return 0
}

proc nsec_aes_nist {} {
    # FIPS-197 Appendix B; keep enable=1, pulse CTRL[9]
    nsec_wr 0x3C 0x00010203
    nsec_wr 0x38 0x04050607
    nsec_wr 0x34 0x08090a0b
    nsec_wr 0x30 0x0c0d0e0f
    nsec_wr 0x7C 0x00112233
    nsec_wr 0x78 0x44556677
    nsec_wr 0x74 0x8899aabb
    nsec_wr 0x70 0xccddeeff
    nsec_wr 0x00 0x201
    after 20
    set st  [nsec_rd 0x04]
    set ct0 [nsec_rd 0x80]
    set ct1 [nsec_rd 0x84]
    set ct2 [nsec_rd 0x88]
    set ct3 [nsec_rd 0x8C]
    puts "AES STATUS=$st"
    puts "AES CT $ct3 $ct2 $ct1 $ct0"
    puts "AES expect 0x69c4e0d8 0x6a7b0430 0xd8cdb780 0x70b4c55a  STATUS bit5=1"
}

proc nsec_csum_test {} {
    nsec_wr 0x00 0x401
    after 2
    nsec_wr 0x90 0x80001234
    after 5
    set st [nsec_rd 0x04]
    set r  [nsec_rd 0x94]
    puts "CSUM STATUS=$st RESULT=$r  expect 0x0000edcb  STATUS bit6=1"
}

proc nsec_modexp_test {} {
    # Python pow(7,560,561)==1 ; pow(123,45,2027)==668
    nsec_wr 0x98 7
    nsec_wr 0x9C 560
    nsec_wr 0xA0 561
    nsec_wr 0x00 0x801
    after 20
    set st [nsec_rd 0x04]
    set r  [nsec_rd 0xA4]
    puts "MODEXP vec0 STATUS=$st RESULT=$r  expect 0x00000001  STATUS bit7=1"
    nsec_wr 0x98 123
    nsec_wr 0x9C 45
    nsec_wr 0xA0 2027
    nsec_wr 0x00 0x801
    after 20
    set st2 [nsec_rd 0x04]
    set r2  [nsec_rd 0xA4]
    puts "MODEXP vec1 STATUS=$st2 RESULT=$r2  expect 0x0000029c  STATUS bit7=1"
}

proc nsec_aes_dp_test {} {
    # NIST key; L0 frame0 bytes 42-57 = FIPS-197 PT; CTRL[12] encrypts on FORWARD
    nsec_wr 0x3C 0x00010203
    nsec_wr 0x38 0x04050607
    nsec_wr 0x34 0x08090a0b
    nsec_wr 0x30 0x0c0d0e0f
    nsec_wr 0x00 0x3
    after 5
    nsec_wr 0x08 0x1
    nsec_wr 0x00 0x1001
    after 2
    nsec_wr 0x00 0x1101
    after 40
    set st  [nsec_rd 0x04]
    set ct0 [nsec_rd 0xB0]
    set ct1 [nsec_rd 0xB4]
    set ct2 [nsec_rd 0xB8]
    set ct3 [nsec_rd 0xBC]
    puts "AES_DP STATUS=$st  bit10=aes_dp_done"
    puts "AES_DP CT $ct3 $ct2 $ct1 $ct0"
    puts "AES_DP expect 0x69c4e0d8 0x6a7b0430 0xd8cdb780 0x70b4c55a"
    nsec_dump
}

proc nsec_ns10g_dump {} {
    puts "NS10G_CTRL [nsec_rd 0x100]"
    puts "NS10G_ST   [nsec_rd 0x104]"
    puts "N0_RX/TX/FWD/DROP/MIR/DPI [nsec_rd 0x108] [nsec_rd 0x10C] [nsec_rd 0x110] [nsec_rd 0x114] [nsec_rd 0x118] [nsec_rd 0x11C]"
    puts "N1_RX/TX/FWD/DROP/MIR/DPI [nsec_rd 0x120] [nsec_rd 0x124] [nsec_rd 0x128] [nsec_rd 0x12C] [nsec_rd 0x130] [nsec_rd 0x134]"
    puts "BADRX0/1 OVF0/1 CSUM0/1 [nsec_rd 0x140] [nsec_rd 0x144] [nsec_rd 0x148] [nsec_rd 0x14C] [nsec_rd 0x150] [nsec_rd 0x154]"
}

proc nsec_l5_test {} {
    nsec_wr 0xDC 0x1
    nsec_wr 0x100 0x5
    nsec_wr 0x00 0x101
    after 2000
    nsec_sfp10g_dump
    nsec_ns10g_dump
    puts "L5: INLINE+dp_en. Expect 0xC0 lock and 0x108/0x120 growing if fiber is crossed."
}

# L5c without external 10G NIC: on-chip GET inject into DP_A (0x100[6] W1C).
proc nsec_l5c_test {} {
    nsec_wr 0xDC 0x1
    nsec_wr 0x00 0x3
    after 5
    nsec_wr 0x100 0x5
    after 10
    set rx0a [nsec_rd 0x108]
    set dpi0a [nsec_rd 0x11C]
    set mir0a [nsec_rd 0x118]
    nsec_wr 0x100 0x45
    after 200
    set rx0b [nsec_rd 0x108]
    set dpi0b [nsec_rd 0x11C]
    set mir0b [nsec_rd 0x118]
    set fwd0b [nsec_rd 0x110]
    puts "L5c t0 RX0=$rx0a DPI0=$dpi0a MIR0=$mir0a"
    puts "L5c t1 RX0=$rx0b DPI0=$dpi0b MIR0=$mir0b FWD0=$fwd0b CTRL=[nsec_rd 0x100]"
    set rxg 0
    set dpig 0
    catch {set rxg  [expr {$rx0b - $rx0a}]}
    catch {set dpig [expr {$dpi0b - $dpi0a}]}
    if {$rxg >= 1 && $dpig >= 1} {
        puts "PASS: L5c on-chip GET inject (no external 10G NIC)"
    } else {
        puts "NEED_HW: L5c expect 0x108/0x11C grow after 0x100=0x45 (needs inj RTL image)"
    }
}

puts "INFO: hw_jtag.tcl loaded. nsec_connect / nsec_program / nsec_dump / nsec_l0_test / nsec_sfp10g_check / nsec_l5_test / nsec_l5c_test"
