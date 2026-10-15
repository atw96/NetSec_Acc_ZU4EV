# Expand the GT Wizard example so the 64B66B stimulus/checker can be read.
# Output stays outside the repo.
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set ex_dir [file join $::env(TEMP) gt_sfp_10g_ex]
file mkdir $ex_dir
open_project [file join $repo_root vivado_proj netsec_accel_zu4ev.xpr]
set ip [get_ips gt_sfp_10g]
if {$ip eq ""} { puts "NEED_IP"; exit 2 }
open_example_project -force -dir $ex_dir $ip
puts "INFO: example at $ex_dir"
exit 0
