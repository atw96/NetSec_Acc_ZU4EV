################################################################################
# rst -system + TCK 100 kHz fpga via existing hw_server (zombie-safe).
# Optional env NSEC_HW_URL (default TCP:127.0.0.1:3121).
# Optional argv: bitstream path.
################################################################################
set repo [file normalize [file join [file dirname [info script]] ..]]
set bit  [file join $repo bitstream_output system_top_rxdly.bit]
if {[llength $argv] >= 1} {
    set bit [lindex $argv 0]
    if {![file exists $bit]} { set bit [file join $repo $bit] }
}
if {![file exists $bit]} { set bit [file join $repo bitstream_output system_top.bit] }
if {![file exists $bit]} {
    puts "ERROR: missing bitstream"; flush stdout; exit 1
}
puts "INFO: bit=$bit size=[file size $bit]"; flush stdout

set url "TCP:127.0.0.1:3121"
if {[info exists ::env(NSEC_HW_URL)] && $::env(NSEC_HW_URL) ne ""} {
    set url $::env(NSEC_HW_URL)
}
puts "INFO: connect -url $url"; flush stdout
if {[catch {connect -url $url} e]} {
    puts "WARN: connect -url failed ($e); trying bare connect"; flush stdout
    if {[catch {connect} e2]} {
        puts "ERROR: connect: $e2"; flush stdout; exit 1
    }
}
after 1500
catch {configparams force-mem-accesses 1}
puts "INFO: connected"; flush stdout
puts "==== targets ====\n[targets]"; flush stdout

if {[catch {targets -set -filter {name =~ "PSU"}} e]} {
    puts "ERROR: no PSU: $e"; flush stdout; catch {disconnect}; exit 1
}
puts "INFO: rst -system"; flush stdout
if {[catch {rst -system} e]} {
    puts "WARN: rst -system: $e"; flush stdout
}
after 2500
puts "INFO: rst done"; flush stdout

if {[catch {
    set jt [jtag targets]
    puts "JTAG:\n$jt"; flush stdout
    if {[regexp {(?n)^\s*(\d+)\s+} $jt -> jid]} { jtag targets $jid }
    jtag frequency 100000
    puts "INFO: jtag frequency 100000"; flush stdout
} e]} { puts "WARN: jtag freq: $e"; flush stdout }

catch {targets -set -filter {name =~ "PL"}}
puts "INFO: fpga programming..."; flush stdout
if {[catch {fpga -f $bit} e]} {
    # some xsct builds want bare fpga
    if {[catch {fpga $bit} e2]} {
        puts "ERROR: fpga: $e / $e2"; flush stdout; catch {disconnect}; exit 1
    }
}
puts "INFO: fpga OK $bit"; flush stdout
catch {jtag frequency 1000000}
after 1000
# Leave hw_server alive for Vivado L5 readback; only disconnect this client.
catch {disconnect}
puts "INFO: xsct_fpga_only done"; flush stdout
exit 0
