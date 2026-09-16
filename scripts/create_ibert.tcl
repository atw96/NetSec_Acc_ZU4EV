################################################################################
# Standalone IBERT GTH project: Quad 224 / X0Y4, MGTREFCLK1 125 MHz (V6/V5)
# Vivado 2020.1 parameter names (not C_PROTOCOL_1_LINERATE).
################################################################################
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set proj_dir  [file join $repo_root vivado_proj_ibert]
file mkdir $proj_dir
create_project ibert_sfp $proj_dir -part xczu4ev-sfvc784-1-i -force

if {[llength [get_ips -quiet ibert_sfp]] == 0} {
    create_ip -name ibert_ultrascale_gth -vendor xilinx.com -library ip -module_name ibert_sfp
}

set ip [get_ips ibert_sfp]
foreach kv {
    {CONFIG.C_PROTOCOL_MAXLINERATE_1 1.25}
    {CONFIG.C_PROTOCOL_REFCLK_FREQUENCY_1 125}
    {CONFIG.C_REFCLK_SOURCE_QUAD_1 MGTREFCLK1_224}
} {
    if {[catch {set_property [lindex $kv 0] [lindex $kv 1] $ip} e]} {
        puts "WARN: ibert set [lindex $kv 0]: $e"
    }
}

generate_target all $ip
catch {open_example_project -force -dir $proj_dir [get_ips ibert_sfp]}
puts "INFO: IBERT IP generated. Patch example XDC then scripts/build_ibert.tcl"
