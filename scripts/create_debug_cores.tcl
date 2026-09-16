################################################################################
# scripts/create_debug_cores.tcl
# Generate ILA IP: ila_logic @ 125 MHz AXIS, ila_rgmii @ rgmii_rxc
################################################################################

proc _netsec_make_ila {name probes widths {depth 1024}} {
    if {[llength [get_ips -quiet $name]] == 0} {
        create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name $name
    }
    set dict_list [list \
        CONFIG.C_NUM_OF_PROBES [llength $probes] \
        CONFIG.C_DATA_DEPTH $depth \
        CONFIG.C_TRIGIN_EN {false} \
        CONFIG.C_TRIGOUT_EN {false} \
        CONFIG.C_INPUT_PIPE_STAGES {1} \
    ]
    set i 0
    foreach w $widths {
        lappend dict_list CONFIG.C_PROBE${i}_WIDTH $w
        incr i
    }
    set_property -dict $dict_list [get_ips $name]
    generate_target all [get_ips $name]
    puts "INFO: ILA $name generated ([llength $probes] probes, depth $depth)"
}

_netsec_make_ila ila_logic \
    {probe0 probe1 probe2 probe3 probe4} \
    {11 11 11 11 16} \
    1024

_netsec_make_ila ila_rgmii \
    {probe0} \
    {5} \
    1024

puts "INFO: debug cores ready"
