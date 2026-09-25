################################################################################
# Alias: default build.tcl is already RGMII_TX_USE_CLK90=FALSE.
# Keep this script so older docs still work; it only copies the default bit.
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set def [file join $repo_root bitstream_output system_top.bit]
if {![file exists $def]} {
    set ::NETSEC_GENERICS {NETSEC_ENABLE_SFP=1'b0 NETSEC_ENABLE_SFP10G=1'b1 RGMII_TX_USE_CLK90=FALSE}
    source [file join $repo_root scripts build.tcl]
}
if {[file exists $def]} {
    file copy -force $def [file join $repo_root bitstream_output system_top_clk90off.bit]
    puts "INFO: system_top_clk90off.bit <- system_top.bit (default is clk90off)"
}
