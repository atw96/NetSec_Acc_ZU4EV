################################################################################
# Re-attach JTAG after xsct and dump PL counters.
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo_root scripts hw_jtag.tcl]
nsec_connect
nsec_dump
exit 0
