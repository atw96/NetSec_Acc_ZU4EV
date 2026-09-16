################################################################################
# PC↔PL L3 arm / dump / DPI / AES / L0
#   vivado -mode batch -source scripts/hw_pc_l3.tcl -tclargs arm
# cmds: arm | dump | dpi_foo | dpi_get | l0 | aes | csum
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root scripts hw_jtag.tcl]

set cmd "arm"
if {[llength $::argv] > 0} { set cmd [lindex $::argv 0] }

proc nsec_hw_open {{mhz 1.0}} {
    set hz [expr {int($mhz * 1e6)}]
    open_hw_manager
    catch {connect_hw_server}
    foreach t [get_hw_targets -quiet] {
        catch {set_property PARAM.FREQUENCY $hz $t}
    }
    if {[catch {open_hw_target} err]} {
        puts "ERROR: $err"
        exit 1
    }
    catch {set_property PARAM.FREQUENCY $hz [current_hw_target]}
    current_hw_device [get_hw_devices xczu4_0]
    catch {set_property PROBES.FILE {} [current_hw_device]}
    catch {refresh_hw_device [current_hw_device]}
}

proc nsec_hw_close {} {
    catch {close_hw_target}
    catch {disconnect_hw_server}
}

set bit [file join $repo_root bitstream_output system_top_rxdly.bit]
if {![file exists $bit]} {
    set bit [file join $repo_root bitstream_output system_top.bit]
}

switch -- $cmd {
    arm {
        nsec_hw_open 0.1
        set_property PROGRAM.FILE $bit [current_hw_device]
        if {[catch {program_hw_devices [current_hw_device]} perr]} {
            puts "ERROR: program $perr"
            exit 2
        }
        after 1500
        catch {close_hw_target}
        nsec_hw_open 1.0
        if {[llength [get_hw_axis -quiet]] == 0} {
            puts "ERROR: no hw_axi after program"
            exit 3
        }
        nsec_wr 0x00 0x3
        after 5
        nsec_wr 0x5C [expr {480 | 0x10000}]
        after 2
        nsec_phy_1g_an 1
        nsec_wr 0x08 0
        nsec_wr 0x00 0x1
        nsec_wait_link 40
        puts "==== BASELINE ===="
        nsec_dump
        nsec_hw_close
        puts "INFO: armed LOOPBACK=0 tap=480. Run pc_traffic_test.py then -tclargs dump"
    }
    dump {
        nsec_hw_open 1.0
        puts "==== DUMP ===="
        nsec_dump
        nsec_hw_close
    }
    dpi_foo {
        nsec_hw_open 1.0
        nsec_wr 0x00 0x3
        after 5
        nsec_wr 0x40 0x464F4F20
        nsec_wr 0x08 0
        nsec_wr 0x00 0x1
        puts "==== DPI_PAT=FOO  counters cleared ===="
        nsec_dump
        nsec_hw_close
    }
    dpi_get {
        nsec_hw_open 1.0
        nsec_wr 0x40 0x47455420
        puts "==== DPI_PAT restored GET ===="
        nsec_dump
        nsec_hw_close
    }
    l0 {
        nsec_hw_open 1.0
        nsec_l0_test
        nsec_hw_close
    }
    board_b {
        nsec_hw_open 0.1
        set_property PROGRAM.FILE $bit [current_hw_device]
        if {[catch {program_hw_devices [current_hw_device]} perr]} {
            puts "ERROR: program $perr"
            exit 2
        }
        after 1500
        catch {close_hw_target}
        nsec_hw_open 1.0
        if {[llength [get_hw_axis -quiet]] == 0} {
            puts "ERROR: no hw_axi after program"
            exit 3
        }
        nsec_wr 0x5C [expr {480 | 0x10000}]
        after 2
        puts "==== L0 ===="
        nsec_l0_test
        puts "==== AES NIST ===="
        nsec_aes_nist
        puts "==== CSUM ===="
        nsec_csum_test
        puts "==== MODEXP ===="
        nsec_modexp_test
        puts "==== AES datapath ===="
        nsec_aes_dp_test
        nsec_hw_close
    }
    aes_dp {
        nsec_hw_open 1.0
        nsec_aes_dp_test
        nsec_hw_close
    }
    aes {
        nsec_hw_open 1.0
        nsec_aes_nist
        nsec_hw_close
    }
    csum {
        nsec_hw_open 1.0
        nsec_csum_test
        nsec_hw_close
    }
    modexp {
        nsec_hw_open 1.0
        nsec_modexp_test
        nsec_hw_close
    }
    default {
        puts "ERROR: unknown cmd $cmd (arm|dump|dpi_foo|dpi_get|l0|aes|csum|modexp|aes_dp|board_b)"
        exit 4
    }
}
exit 0
