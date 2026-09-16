################################################################################
# Wipe project, recreate BD (GEM3), build default clk90off bitstream + XSA
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root scripts create_project.tcl]
source [file join $repo_root scripts build.tcl]
set def [file join $repo_root bitstream_output system_top.bit]
if {[file exists $def]} {
    file copy -force $def [file join $repo_root bitstream_output system_top_clk90off.bit]
    puts "INFO: also copied system_top_clk90off.bit"
}
puts "INFO: recreate_and_build done"
