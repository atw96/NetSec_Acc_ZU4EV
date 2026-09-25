################################################################################
# scripts/build.tcl
# Synth / impl / bitstream + export timing & utilization reports
#
# Usage:
#   vivado -mode batch -source scripts/create_project.tcl
#   vivado -mode batch -source scripts/build.tcl
# Or open the project then: source scripts/build.tcl
################################################################################

set repo_root [file normalize [file join [file dirname [info script]] ..]]
set proj_dir  [file normalize [file join $repo_root vivado_proj]]
set proj_xpr  [file join $proj_dir netsec_accel_zu4ev.xpr]
set rpt_dir   [file join $repo_root docs timing_report]
file mkdir $rpt_dir

if {[current_project -quiet] eq ""} {
    if {[file exists $proj_xpr]} {
        open_project $proj_xpr
    } else {
        source [file join $repo_root scripts create_project.tcl]
    }
}

update_compile_order -fileset sources_1
set_property top system_top [current_fileset]
# Default image: copper RGMII + dual-SFP 10G. 1G PRBS (ENABLE_SFP) is mutually exclusive
# with 10G on X0Y4/X0Y5. create_sfp_pcs.tcl latches ENABLE_SFP=1 — keep it 0 here.
if {![info exists ::NETSEC_GENERICS]} {
    # clk90off is the only RGMII phase that echoed on AXU4EVB-P
    set ::NETSEC_GENERICS {NETSEC_ENABLE_SFP=1'b0 NETSEC_ENABLE_SFP10G=1'b1 RGMII_TX_USE_CLK90=FALSE}
}
set_property generic $::NETSEC_GENERICS [current_fileset]
set_property verilog_define {NETSEC_SFP_PORTS} [current_fileset]
source [file join $repo_root scripts create_gt_10g.tcl]

catch {reset_run synth_1}
catch {reset_run impl_1}

launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "INFO: synth_1 status = $synth_status"
if {[string match "*ERROR*" $synth_status] || [string match "*Failed*" $synth_status]} {
    error "synth_1 failed: $synth_status"
}

open_run synth_1
report_utilization -file [file join $rpt_dir utilization_synth.rpt]
close_design

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

open_run impl_1
report_timing_summary -file [file join $rpt_dir timing_summary.rpt]
report_utilization -file [file join $rpt_dir utilization.rpt]
report_clock_utilization -file [file join $rpt_dir clock_utilization.rpt]

# Copy bitstream
set bitfile [get_property FILE_OUT [get_runs impl_1]]
# Prefer common path
set bits [glob -nocomplain [file join $proj_dir netsec_accel_zu4ev.runs impl_1 *.bit]]
foreach b $bits {
    file copy -force $b [file join $repo_root bitstream_output]
    puts "INFO: bitstream -> bitstream_output/[file tail $b]"
}

# Export XSA for Vitis / SDK (OCM firmware). Requires impl design open.
set xsa [file join $repo_root firmware netsec.xsa]
if {[catch {write_hw_platform -fixed -include_bit -force $xsa} xsa_err]} {
    puts "WARNING: write_hw_platform failed: $xsa_err"
} else {
    puts "INFO: XSA -> $xsa"
}

puts "INFO: build complete. Reports in docs/timing_report/"
