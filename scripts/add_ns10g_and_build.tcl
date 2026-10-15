set repo_root [file normalize [file join [file dirname [info script]] ..]]
set proj [file join $repo_root vivado_proj netsec_accel_zu4ev.xpr]
open_project $proj
foreach f {
  rtl/crypto/aes/aes128_pipe.sv
  rtl/flow_table/flow_table_uram.sv
  rtl/dpi_engine/dpi_match64.sv
  rtl/top/pkt_gen_inj64.sv
  rtl/top/netsec_dp64.sv
  rtl/top/netsec10g_switch64.sv
} {
  set p [file join $repo_root $f]
  if {[llength [get_files -quiet $p]] == 0} {
    add_files -norecurse $p
    set_property file_type SystemVerilog [get_files $p]
  }
}
source [file join $repo_root scripts build.tcl]
