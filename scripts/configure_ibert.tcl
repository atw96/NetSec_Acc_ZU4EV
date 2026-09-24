# Patch example IBERT IP to 10.3125G / 125 MHz / MGTREFCLK1 bank 224
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set xpr [file join $repo_root vivado_proj_ibert ibert_sfp_ex ibert_sfp_ex.xpr]
open_project $xpr
set ip [get_ips ibert_sfp]
foreach {k v} {
    CONFIG.C_PROTOCOL_MAXLINERATE_1 10.0
    CONFIG.C_PROTOCOL_REFCLK_FREQUENCY_1 125
    CONFIG.C_REFCLK_SOURCE_QUAD_1 MGTREFCLK1_224
} {
    if {[catch {set_property $k $v $ip} e]} { puts "WARN: $k: $e" }
}
generate_target all $ip
puts "INFO: IBERT reconfigured to 10.3125G / 125 MHz"
