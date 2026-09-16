# XSim (Vivado 2020.1) for DPI AC + L0 + AES datapath
set repo [file normalize [file join [file dirname [info script]] ..]]
if {![info exists ::env(XILINX_VIVADO)] || $::env(XILINX_VIVADO) eq ""} {
    error "set XILINX_VIVADO to the Vivado install root"
}
set xvlog [file join $::env(XILINX_VIVADO) bin xvlog.bat]
set xelab [file join $::env(XILINX_VIVADO) bin xelab.bat]
set xsim  [file join $::env(XILINX_VIVADO) bin xsim.bat]
cd $repo
file mkdir sim_xsim
cd sim_xsim

proc xv {args} {
    global xvlog
    if {[catch {exec $xvlog -sv {*}$args >@ stdout 2>@ stderr} err]} {
        error "xvlog failed: $err"
    }
}

set r [file join $repo rtl]
set t [file join $repo tb simple_tb]

puts "==== tb_dpi_engine ===="
xv [file join $r dpi_engine dpi_matcher.sv] [file join $t tb_dpi_engine.sv]
exec $xelab tb_dpi_engine -timescale 1ns/1ps >@ stdout 2>@ stderr
exec $xsim tb_dpi_engine -runall >@ stdout 2>@ stderr

puts "==== tb_l0_loopback ===="
xv [file join $r crypto aes aes_sbox_pkg.sv] \
   [file join $r crypto aes aes128_core.sv] \
   [file join $r common sync_fifo.sv] \
   [file join $r packet_parser packet_parser.sv] \
   [file join $r flow_table flow_table.sv] \
   [file join $r dpi_engine dpi_matcher.sv] \
   [file join $r ips_decision ips_decision.sv] \
   [file join $r top pkt_gen_bram.sv] \
   [file join $r top netsec_datapath.sv] \
   [file join $t tb_l0_loopback.sv]
exec $xelab tb_l0_loopback -timescale 1ns/1ps >@ stdout 2>@ stderr
exec $xsim tb_l0_loopback -runall >@ stdout 2>@ stderr

puts "==== tb_aes_datapath ===="
xv [file join $t tb_aes_datapath.sv]
exec $xelab tb_aes_datapath -timescale 1ns/1ps >@ stdout 2>@ stderr
exec $xsim tb_aes_datapath -runall >@ stdout 2>@ stderr

puts "INFO: xsim suite done"
