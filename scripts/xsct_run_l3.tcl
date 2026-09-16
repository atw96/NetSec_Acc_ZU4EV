################################################################################
# xsct: psu_init (skip DDR) → dow. Does NOT rst -system (would wipe PL).
# Program PL first via xsct_fpga_then_l3.tcl or hw_l3_prep.tcl (TCK 100 kHz).
################################################################################
set repo [file normalize [file join [file dirname [info script]] ..]]
set elf  [file join $repo firmware netsec_l3.elf]
if {![file exists $elf]} { error "missing $elf — run scripts/link_ps_app.bat" }

connect
after 1500
puts "==== xsct targets ====\n[targets]"

if {[catch {
    set jt [jtag targets]
    puts "JTAG:\n$jt"
    if {[regexp {(?n)^\s*(\d+)\s+} $jt -> jid]} { jtag targets $jid }
    jtag frequency 1000000
    puts "INFO: jtag frequency [jtag frequency]"
} e]} { puts "WARN: jtag frequency: $e" }

if {[catch {targets -set -filter {name =~ "PSU"}} e]} {
    puts "ERROR: no PSU: $e"; disconnect; exit 1
}
catch {stop}

set psu [file join $repo firmware vitis_ws netsec_plat hw psu_init.tcl]
if {[file exists $psu]} {
    puts "INFO: sourcing $psu"
    source $psu
    proc psu_ddr_phybringup_data {} { puts "INFO: skip DDR PHY bringup (OCM-only)" }
    if {[catch {psu_init} e]} { puts "WARN: psu_init: $e" }
    catch {psu_post_config}
    if {[catch {psu_ps_pl_isolation_removal} e]} { puts "WARN: isolation: $e" }
}

if {[catch {targets -set -filter {name =~ "Cortex-A53 #0"}} e]} {
    puts "ERROR: A53: $e"; disconnect; exit 1
}
catch {stop}
if {[catch {rst -processor -clear-registers} e]} {
    puts "WARN: rst -processor: $e"
    catch {rst -processor}
}
after 800
if {[catch {dow $elf} e]} {
    puts "ERROR: dow: $e"; disconnect; exit 1
}
con

set words ""
for {set i 0} {$i < 30} {incr i} {
    after 1000
    catch {stop}
    if {![catch {set words [mrd 0xFFFEF000 12]}]} {
        puts "MB poll $i: $words"
        if {[string match -nocase *4E53334C* $words] || [string match -nocase *4E533301* $words]} {
            if {[string match -nocase *4E53334C* $words]} { break }
        }
    }
    catch {con}
}
puts "MAILBOX:\n$words"
disconnect
exit 0
