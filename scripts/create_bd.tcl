################################################################################
# scripts/create_bd.tcl
# BD: Zynq PS + jtag_axi + SmartConnect, single clock axi_clk_in @ 100 MHz
# M_AXI @ 0x8005_0000 for netsec_regs
################################################################################

set repo_root [file normalize [file join [file dirname [info script]] ..]]

create_bd_design design_1

# PL-generated 100 MHz clock / local POR — PS and JTAG share this domain
create_bd_port -dir I -type clk axi_clk_in
set_property CONFIG.FREQ_HZ {100000000} [get_bd_ports axi_clk_in]
create_bd_port -dir I -type rst axi_aresetn_in
set_property CONFIG.POLARITY {ACTIVE_LOW} [get_bd_ports axi_aresetn_in]
set_property CONFIG.ASSOCIATED_RESET {axi_aresetn_in} [get_bd_ports axi_clk_in]

create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.3 zynq_ultra_ps_e_0
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP2 {1} \
    CONFIG.PSU__USE__M_AXI_GP0 {0} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__USE__FABRIC__RST {1} \
    CONFIG.PSU__UART0__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__UART0__PERIPHERAL__IO {MIO 42 .. 43} \
    CONFIG.PSU_BANK_2_IO_STANDARD {LVCMOS18} \
    CONFIG.PSU__ENET3__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__ENET3__PERIPHERAL__IO {MIO 64 .. 75} \
    CONFIG.PSU__ENET3__GRP_MDIO__ENABLE {1} \
    CONFIG.PSU__ENET3__GRP_MDIO__IO {MIO 76 .. 77} \
    CONFIG.PSU__CRL_APB__GEM3_REF_CTRL__FREQMHZ {125} \
] [get_bd_cells zynq_ultra_ps_e_0]

# Drive HPM0 AXI clock from PL so the interconnect is alive without PS PLL
connect_bd_net [get_bd_ports axi_clk_in] [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_lpd_aclk]

create_bd_cell -type ip -vlnv xilinx.com:ip:jtag_axi:1.2 jtag_axi_0
# PROTOCOL 2 = AXI4-Lite on jtag_axi v1.2 (fallback keeps AXI4; SmartConnect converts)
if {[catch {set_property CONFIG.PROTOCOL {2} [get_bd_cells jtag_axi_0]} err]} {
    puts "INFO: jtag_axi PROTOCOL=2 not applied ($err) — using default"
}

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] [get_bd_cells axi_smc]

connect_bd_net [get_bd_ports axi_clk_in]     [get_bd_pins axi_smc/aclk]
connect_bd_net [get_bd_ports axi_aresetn_in] [get_bd_pins axi_smc/aresetn]
connect_bd_net [get_bd_ports axi_clk_in]     [get_bd_pins jtag_axi_0/aclk]
connect_bd_net [get_bd_ports axi_aresetn_in] [get_bd_pins jtag_axi_0/aresetn]

connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_LPD] [get_bd_intf_pins axi_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins jtag_axi_0/M_AXI]                 [get_bd_intf_pins axi_smc/S01_AXI]

create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M_AXI
set_property -dict [list CONFIG.PROTOCOL {AXI4LITE} CONFIG.ADDR_WIDTH {40} CONFIG.DATA_WIDTH {32}] [get_bd_intf_ports M_AXI]
set_property CONFIG.ASSOCIATED_BUSIF {M_AXI} [get_bd_ports axi_clk_in]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] [get_bd_intf_ports M_AXI]

assign_bd_address -offset 0x80050000 -range 0x00010000 -target_address_space \
    [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs M_AXI/Reg] -force

# jtag_axi address space name differs slightly across revisions
set jtag_spaces [get_bd_addr_spaces -quiet jtag_axi_0/*]
foreach sp $jtag_spaces {
    if {[catch {assign_bd_address -offset 0x80050000 -range 0x00010000 -target_address_space \
            $sp [get_bd_addr_segs M_AXI/Reg] -force} e]} {
        puts "INFO: jtag assign on $sp: $e"
    } else {
        puts "INFO: jtag_axi space $sp -> 0x80050000"
    }
}

if {[catch {validate_bd_design -force} err]} {
    puts "WARNING: validate_bd_design reported: $err (continuing)"
}
save_bd_design

make_wrapper -files [get_files design_1.bd] -top
set wrapper_candidates [concat \
    [glob -nocomplain [file join [get_property DIRECTORY [current_project]] *.srcs sources_1 bd design_1 hdl *_wrapper.v]] \
    [glob -nocomplain [file join [get_property DIRECTORY [current_project]] *.gen sources_1 bd design_1 hdl *_wrapper.v]] \
]
foreach w $wrapper_candidates {
    add_files -norecurse $w
    puts "INFO: added wrapper $w"
}

puts "INFO: BD design_1 created (PS + jtag_axi, axi_clk_in). netsec_regs @ 0x80050000"
