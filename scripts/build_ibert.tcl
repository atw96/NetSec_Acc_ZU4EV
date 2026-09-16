################################################################################
# Build IBERT bitstream -> bitstream_output/system_top_ibert.bit
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set proj_dir  [file join $repo_root vivado_proj_ibert]

set ex [glob -nocomplain [file join $proj_dir ibert_sfp_ex *ibert*.xpr]]
if {$ex eq ""} {
    set ex [glob -nocomplain [file join $proj_dir *.xpr]]
}
if {$ex eq ""} {
    source [file join $repo_root scripts create_ibert.tcl]
    set ex [glob -nocomplain [file join $proj_dir ibert_sfp_ex *ibert*.xpr]]
}
if {$ex eq ""} { error "no IBERT project — run create_ibert.tcl first" }
open_project [lindex $ex 0]

# Do NOT add sfp_gth.xdc (ports mgtrefclk_* / sfp_* do not exist on IBERT example).
# Board clocks are in imports/example_ibert_sfp.xdc (AE5/AF5 + V6/V5).

catch {reset_run synth_1}
catch {reset_run impl_1}
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set st [get_property STATUS [get_runs synth_1]]
if {[string match "*ERROR*" $st] || [string match "*Failed*" $st]} {
    error "ibert synth failed: $st"
}
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set bits [glob -nocomplain [file join [get_property DIRECTORY [get_runs impl_1]] *.bit]]
if {$bits eq ""} { error "no IBERT bitstream" }
file mkdir [file join $repo_root bitstream_output]
file copy -force [lindex $bits 0] [file join $repo_root bitstream_output system_top_ibert.bit]
puts "INFO: bitstream_output/system_top_ibert.bit"
