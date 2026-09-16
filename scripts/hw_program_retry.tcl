# Diagnose / retry PL program at 100 kHz without LTX
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set bits [list \
    [file join $repo_root bitstream_output system_top.bit] \
    [file join $repo_root bitstream_output system_top_clk90off.bit] \
    [file join $repo_root bitstream_output system_top_clk90on.bit] \
]
open_hw_manager
catch {connect_hw_server}
foreach t [get_hw_targets] {
    catch {set_property PARAM.FREQUENCY 100000 $t}
}
open_hw_target
catch {set_property PARAM.FREQUENCY 100000 [current_hw_target]}
current_hw_device [get_hw_devices xczu4_0]
catch {set_property PROBES.FILE {} [current_hw_device]}
puts "INFO: TCK=[get_property PARAM.FREQUENCY [current_hw_target]] device=[current_hw_device]"
foreach bit $bits {
    if {![file exists $bit]} { continue }
    puts "INFO: trying $bit"
    set_property PROGRAM.FILE $bit [current_hw_device]
    if {[catch {program_hw_devices [current_hw_device]} e]} {
        puts "WARN: $e"
    } else {
        puts "INFO: PROGRAM OK $bit"
        catch {refresh_hw_device [current_hw_device]}
        puts "INFO: hw_axi=[get_hw_axis -quiet]"
        exit 0
    }
    after 1000
}
puts "ERROR: all program attempts failed"
exit 3
