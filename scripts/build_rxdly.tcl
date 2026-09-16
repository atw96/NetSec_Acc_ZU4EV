################################################################################
# clk90off + RX IDELAY bitstream → bitstream_output/system_top_rxdly.bit
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set ::NETSEC_GENERICS {NETSEC_ENABLE_SFP=1'b0 RGMII_TX_USE_CLK90=FALSE}
source [file join $repo_root scripts build.tcl]
set impl_bit [file join $repo_root vivado_proj netsec_accel_zu4ev.runs impl_1 system_top.bit]
if {![file exists $impl_bit]} {
    error "impl_1 did not write system_top.bit (bitstream failed)"
}
file copy -force $impl_bit [file join $repo_root bitstream_output system_top.bit]
file copy -force $impl_bit [file join $repo_root bitstream_output system_top_rxdly.bit]
puts "INFO: system_top_rxdly.bit <- impl_1/system_top.bit"
