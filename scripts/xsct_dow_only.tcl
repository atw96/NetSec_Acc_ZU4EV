# Dow ELF only. Requires PL programmed and a prior psu_init (no rst -system).
set repo [file normalize [file join [file dirname [info script]] ..]]
set elf  [file join $repo firmware netsec_l3.elf]
connect
after 1000
puts "==== targets ====\n[targets]"
if {[catch {
    set jt [jtag targets]
    if {[regexp {(?n)^\s*(\d+)\s+} $jt -> jid]} { jtag targets $jid }
    jtag frequency 1000000
} e]} { puts "WARN: $e" }

if {[catch {targets -set -filter {name =~ "Cortex-A53 #0"}} e]} {
    puts "ERROR: A53: $e"; disconnect; exit 1
}
catch {stop}
after 200
if {[catch {rst -processor -clear-registers} e]} {
    puts "WARN: rst: $e"
    catch {rst -processor}
}
after 500
if {[catch {dow $elf} e]} {
    puts "ERROR: dow: $e"; disconnect; exit 1
}
puts "INFO: dow OK"
con
set words ""
for {set i 0} {$i < 30} {incr i} {
    after 1000
    catch {stop}
    if {![catch {set words [mrd 0xFFFEF000 12]}]} {
        puts "MB $i: $words"
        if {[string match -nocase *4E53334C* $words]} { break }
    }
    catch {con}
}
puts "MAILBOX:\n$words"
disconnect
exit 0
