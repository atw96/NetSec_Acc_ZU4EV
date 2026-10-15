# XSim: sfp10g_wrap + gt_sfp_10g, TX serial pins looped to RX.
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set sim_dir [file join $::env(TEMP) gt_loop_sim]
file mkdir $sim_dir
create_project gt_loop_sim [file join $sim_dir proj] -part xczu4ev-sfvc784-1-i -force

set ve [file join $repo_root rtl mac_pcs third_party verilog-ethernet rtl]
add_files [glob -nocomplain [file join $ve *.v]]
add_files [file join $repo_root rtl top pkt_gen_10g.sv]
add_files [file join $repo_root rtl top netsec_cdc.sv]
add_files [file join $repo_root rtl mac_pcs sfp10g_wrap.sv]
set xci [file join $repo_root vivado_proj netsec_accel_zu4ev.srcs sources_1 ip gt_sfp_10g gt_sfp_10g.xci]
add_files $xci
add_files -fileset sim_1 [file join $repo_root tb xsim tb_sfp10g_gt_loop.sv]
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sources_1] *.sv]
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] *.sv]
set_property top tb_sfp10g_gt_loop [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {3ms} -objects [get_filesets sim_1]
launch_simulation
puts "INFO: gt loop simulation launched"
exit 0
