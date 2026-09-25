set repo_root [file normalize [file join [file dirname [info script]] ..]]
set proj [file join $repo_root vivado_proj netsec_accel_zu4ev.xpr]
open_project $proj
foreach f {
  rtl/top/netsec_axis_bridge.sv
  rtl/top/netsec10g_switch.sv
} {
  set p [file join $repo_root $f]
  if {[llength [get_files -quiet $p]] == 0} {
    add_files -norecurse $p
    set_property file_type SystemVerilog [get_files $p]
  }
}
source [file join $repo_root scripts build.tcl]
