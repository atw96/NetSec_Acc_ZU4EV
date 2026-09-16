connect
after 400
catch {configparams force-mem-accesses 1}
targets -set -filter {name =~ "PSU"}
if {[catch {puts [mrd -force 0x80050004 1]} e]} {
    puts "PING_FAIL $e"
    disconnect
    exit 1
}
puts "PING_OK"
disconnect
exit 0
