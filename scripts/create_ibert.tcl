################################################################################
# IBERT GTH: Quad 224, 10.0 Gbps, 125 MHz MGTREFCLK1_224 (V6/V5)
# Vivado 2020.1 IBERT rejects 10.3125G+125 MHz (10.3125/125=82.5).
# 10.0G+125 is exact. 10GBASE-R Ethernet still uses GT Wizard @ 10.3125G.
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set proj_dir  [file join $repo_root vivado_proj_ibert]
set ex_xpr    [file join $proj_dir ibert_sfp_ex ibert_sfp_ex.xpr]
file mkdir $proj_dir

proc nsec_ibert_apply_rate {ip} {
    foreach kv {
        {CONFIG.C_PROTOCOL_MAXLINERATE_1 10.0}
        {CONFIG.C_PROTOCOL_REFCLK_FREQUENCY_1 125}
        {CONFIG.C_REFCLK_SOURCE_QUAD_1 MGTREFCLK1_224}
    } {
        if {[catch {set_property [lindex $kv 0] [lindex $kv 1] $ip} e]} {
            puts "WARN: ibert set [lindex $kv 0]: $e"
        }
    }
}

proc nsec_ibert_write_board_xdc {xdc} {
    set fh [open $xdc w]
    puts $fh {# AXU4EVB-P IBERT board pins — do not replace with stock example locs}
    puts $fh {# sysclk: factory system.xdc AE5/AF5 200 MHz DIFF_SSTL12}
    puts $fh {# MGTREFCLK1_224: factory gt.xdc V6/V5, SiT9121 125.000 MHz}
    puts $fh {create_clock -name D_CLK -period 5.000 [get_ports gth_sysclkp_i]}
    puts $fh {set_clock_groups -group [get_clocks D_CLK -include_generated_clocks] -asynchronous}
    puts $fh {set_property C_CLK_INPUT_FREQ_HZ 200000000 [get_debug_cores dbg_hub]}
    puts $fh {set_property C_ENABLE_CLK_DIVIDER true [get_debug_cores dbg_hub]}
    puts $fh {set_property PACKAGE_PIN Y6 [get_ports {gth_refclk0p_i[0]}]}
    puts $fh {set_property PACKAGE_PIN Y5 [get_ports {gth_refclk0n_i[0]}]}
    puts $fh {set_property PACKAGE_PIN V6 [get_ports {gth_refclk1p_i[0]}]}
    puts $fh {set_property PACKAGE_PIN V5 [get_ports {gth_refclk1n_i[0]}]}
    puts $fh {create_clock -name gth_refclk0_1 -period 8.000 [get_ports {gth_refclk0p_i[0]}]}
    puts $fh {create_clock -name gth_refclk1_1 -period 8.000 [get_ports {gth_refclk1p_i[0]}]}
    puts $fh {set_clock_groups -group [get_clocks gth_refclk0_1 -include_generated_clocks] -asynchronous}
    puts $fh {set_clock_groups -group [get_clocks gth_refclk1_1 -include_generated_clocks] -asynchronous}
    puts $fh {set_property PACKAGE_PIN AE5 [get_ports gth_sysclkp_i]}
    puts $fh {set_property PACKAGE_PIN AF5 [get_ports gth_sysclkn_i]}
    puts $fh {set_property IOSTANDARD DIFF_SSTL12 [get_ports gth_sysclkp_i]}
    puts $fh {set_property IOSTANDARD DIFF_SSTL12 [get_ports gth_sysclkn_i]}
    puts $fh {# Cage TX_DISABLE — SOURCE: MANUAL-PAGE44}
    puts $fh {set_property PACKAGE_PIN D12 [get_ports sfp_tx_dis]}
    puts $fh {set_property IOSTANDARD LVCMOS33 [get_ports sfp_tx_dis]}
    puts $fh {set_false_path -to [get_ports sfp_tx_dis]}
    close $fh
    puts "INFO: wrote board IBERT XDC $xdc"
}

proc nsec_ibert_patch_txdis {vfile} {
    if {![file exists $vfile]} {
        puts "WARN: IBERT example Verilog missing: $vfile"
        return
    }
    set fh [open $vfile r]
    set txt [read $fh]
    close $fh
    if {[string first "sfp_tx_dis" $txt] >= 0} {
        puts "INFO: $vfile already has sfp_tx_dis"
        return
    }
    set old "  input  \[`C_GTH_REFCLKS_USED-1:0\]      gth_refclk1n_i\n);"
    set new "  input  \[`C_GTH_REFCLKS_USED-1:0\]      gth_refclk1n_i,\n  output                               sfp_tx_dis\n);\n  assign sfp_tx_dis = 1'b0;"
    set out [string map [list $old $new] $txt]
    if {$out eq $txt} {
        puts "WARN: could not patch sfp_tx_dis into $vfile"
        return
    }
    set fh [open $vfile w]
    puts -nonewline $fh $out
    close $fh
    puts "INFO: patched sfp_tx_dis into $vfile"
}

if {[file exists $ex_xpr]} {
    open_project $ex_xpr
    set ip [get_ips ibert_sfp]
    nsec_ibert_apply_rate $ip
    generate_target all $ip
    set xdc [file join $proj_dir ibert_sfp_ex imports example_ibert_sfp.xdc]
    if {[file exists $xdc]} {
        nsec_ibert_write_board_xdc $xdc
    }
    set ex_v [file join $proj_dir ibert_sfp_ex imports example_ibert_sfp.v]
    nsec_ibert_patch_txdis $ex_v
    puts "INFO: reused $ex_xpr @ 10.0G / 125 MHz"
} else {
    create_project ibert_sfp $proj_dir -part xczu4ev-sfvc784-1-i -force
    if {[llength [get_ips -quiet ibert_sfp]] == 0} {
        create_ip -name ibert_ultrascale_gth -vendor xilinx.com -library ip -module_name ibert_sfp
    }
    set ip [get_ips ibert_sfp]
    nsec_ibert_apply_rate $ip
    generate_target all $ip
    catch {open_example_project -force -dir $proj_dir [get_ips ibert_sfp]}
    set xdc [file join $proj_dir ibert_sfp_ex imports example_ibert_sfp.xdc]
    if {[file exists $xdc]} {
        nsec_ibert_write_board_xdc $xdc
    }
    set ex_v [file join $proj_dir ibert_sfp_ex imports example_ibert_sfp.v]
    nsec_ibert_patch_txdis $ex_v
    puts "INFO: IBERT example created @ 10.0G / 125 MHz"
}
puts "INFO: next: scripts/build_ibert.tcl"
