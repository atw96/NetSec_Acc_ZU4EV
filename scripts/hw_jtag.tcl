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
    foreach p {DATA OUTPUT.VALUE OUTPUT_VALUE READ_DATA} {
        if {[lsearch -exact [list_property $obj] $p] >= 0} {
            set v [get_property $p $obj]
            if {$v ne ""} { return $v }
        }
    }
    set rpt [report_hw_axi_txn -quiet -return_string $txn]
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
    set data [nsec_txn_data $txn]
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
    nsec_wr 0x08 0x4
    nsec_wr 0x00 0x1
    after 20
    set st [nsec_rd 0x60]
    nsec_dump
    puts "L4: LOOPBACK=4 SFP_STATUS=$st (bit0 nearend/enable; link in [1] when GT image)"
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

puts "INFO: hw_jtag.tcl loaded. nsec_connect / nsec_program / nsec_dump / nsec_l0_test"
