################################################################################
# L1 on already-programmed FWFT bitstream (no reprogram)
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root scripts hw_jtag.tcl]

open_hw_manager
catch {connect_hw_server}
foreach t [get_hw_targets] {
    catch {set_property PARAM.FREQUENCY 1000000 $t}
}
if {[catch {open_hw_target} err]} {
    puts "ERROR: open_hw_target: $err"
    exit 1
}
current_hw_device [get_hw_devices xczu4_0]
set ltx [file join $repo_root vivado_proj netsec_accel_zu4ev.runs impl_1 system_top.ltx]
if {[file exists $ltx]} {
    set_property PROBES.FILE $ltx [current_hw_device]
}
if {[catch {refresh_hw_device [current_hw_device]} rerr]} {
    puts "WARN: refresh_hw_device: $rerr"
}
if {[llength [get_hw_axis -quiet]] == 0} {
    puts "ERROR: no hw_axi"
    exit 3
}

puts "INFO: pre-L1 dump"
nsec_dump
nsec_l1_test

# ILA-A: look for mac_tx activity (probe3) vs datapath (probe0/1)
set ilas [get_hw_ilas -quiet]
puts "INFO: ilas = $ilas"
if {[llength $ilas] > 0} {
    set ila [lindex $ilas 0]
    catch {set_property CONTROL.TRIGGER_POSITION 0 $ila}
    catch {set_property CONTROL.CAPTURE_MODE BASIC $ila}
    if {[catch {
        run_hw_ila $ila
        after 200
        # fire another start so ILA sees traffic
        nsec_wr 0x00 0x101
        after 50
        wait_on_hw_ila $ila
        upload_hw_ila_data $ila
        set data [get_hw_ila_data ${ila}_data]
        puts "INFO: ILA uploaded [llength [get_hw_probes -of_objects $ila]] probes"
        foreach p [get_hw_probes -of_objects $ila] {
            puts "PROBE $p"
        }
    } ierr]} {
        puts "WARN: ILA capture: $ierr"
    }
}

puts "INFO: opportunistic MDIO (may be BMSR poll, not ID)"
if {[catch {nsec_mdio_id 1} merr]} {
    puts "WARN: nsec_mdio_id: $merr"
}

puts "INFO: L1 script done"
exit 0
