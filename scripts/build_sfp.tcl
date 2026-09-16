################################################################################
# L4-only bitstream: system_top_sfp (GT Wizard PRBS, near-end PMA)
# Does not replace bitstream_output/system_top.bit
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set proj_dir  [file normalize [file join $repo_root vivado_proj]]
set proj_xpr  [file join $proj_dir netsec_accel_zu4ev.xpr]
if {![file exists $proj_xpr]} { error "No project" }
open_project $proj_xpr

source [file join $repo_root scripts create_gt_prbs.tcl]

set sfp_xdc [file join $repo_root constraints sfp_rgmii_ignore.xdc]
if {[llength [get_files -quiet -of_objects [get_filesets constrs_1] $sfp_xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse $sfp_xdc
}

set_property top system_top_sfp [current_fileset]
set_property verilog_define {NETSEC_SFP_PORTS} [current_fileset]
update_compile_order -fileset sources_1

catch {reset_run synth_1}
catch {reset_run impl_1}
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {[string match "*ERROR*" $synth_status] || [string match "*Failed*" $synth_status]} {
    error "synth_1 failed: $synth_status"
}
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set rpt_dir [file join $repo_root docs timing_report]
file mkdir $rpt_dir
if {![catch {open_run impl_1}]} {
    report_timing_summary -file [file join $rpt_dir timing_summary_sfp.rpt]
    close_design
}

set bits [glob -nocomplain [file join $proj_dir netsec_accel_zu4ev.runs impl_1 *.bit]]
foreach b $bits {
    file copy -force $b [file join $repo_root bitstream_output system_top_sfp.bit]
    puts "INFO: L4 bitstream -> bitstream_output/system_top_sfp.bit"
}

# Restore default top so later L0–L3 builds are not stuck on SFP
set_property top system_top [current_fileset]
set_property verilog_define {} [current_fileset]
catch {remove_files -fileset constrs_1 $sfp_xdc}
puts "INFO: build_sfp complete"
