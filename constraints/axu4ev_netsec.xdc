################################################################
## axu4ev_netsec.xdc
## NetSec-Accel-ZU4EV — RGMII / sysclk / LED / KEY / UART
## Part: xczu4ev-sfvc784-1-i
## Authority: docs/board_pinout.md
################################################################

################################################################
# 1. PL 200 MHz system clock (factory system.xdc)
################################################################
set_property PACKAGE_PIN AE5 [get_ports sys_clk_clk_p]
set_property PACKAGE_PIN AF5 [get_ports sys_clk_clk_n]
set_property IOSTANDARD DIFF_SSTL12 [get_ports {sys_clk_clk_p sys_clk_clk_n}]
create_clock -period 5.000 -name sys_clk_clk_p -waveform {0.000 2.500} [get_ports sys_clk_clk_p]

################################################################
# 2. PL RGMII + MDIO + PHY reset (factory eth.xdc, Bank66 LVCMOS18)
# SOURCE: doc/factory_vivado/.../eth.xdc ; MANUAL PAGE37-38
################################################################
set_property PACKAGE_PIN E5 [get_ports rgmii_rxc]
set_property PACKAGE_PIN B8 [get_ports rgmii_rx_ctl]
set_property PACKAGE_PIN A5 [get_ports {rgmii_rd[0]}]
set_property PACKAGE_PIN B5 [get_ports {rgmii_rd[1]}]
set_property PACKAGE_PIN F8 [get_ports {rgmii_rd[2]}]
set_property PACKAGE_PIN C9 [get_ports {rgmii_rd[3]}]
set_property PACKAGE_PIN A7 [get_ports rgmii_txc]
set_property PACKAGE_PIN B9 [get_ports rgmii_tx_ctl]
set_property PACKAGE_PIN E9 [get_ports {rgmii_td[0]}]
set_property PACKAGE_PIN D9 [get_ports {rgmii_td[1]}]
set_property PACKAGE_PIN A9 [get_ports {rgmii_td[2]}]
set_property PACKAGE_PIN A8 [get_ports {rgmii_td[3]}]
set_property PACKAGE_PIN A6 [get_ports mdio_mdc]
set_property PACKAGE_PIN C8 [get_ports mdio_mdio]
set_property PACKAGE_PIN D5 [get_ports phy_reset_n]

set_property IOSTANDARD LVCMOS18 [get_ports rgmii_rxc]
set_property IOSTANDARD LVCMOS18 [get_ports rgmii_rx_ctl]
set_property IOSTANDARD LVCMOS18 [get_ports {rgmii_rd[*]}]
set_property IOSTANDARD LVCMOS18 [get_ports rgmii_txc]
set_property IOSTANDARD LVCMOS18 [get_ports rgmii_tx_ctl]
set_property IOSTANDARD LVCMOS18 [get_ports {rgmii_td[*]}]
set_property IOSTANDARD LVCMOS18 [get_ports mdio_mdc]
set_property IOSTANDARD LVCMOS18 [get_ports mdio_mdio]
set_property IOSTANDARD LVCMOS18 [get_ports phy_reset_n]
# factory eth.xdc: MDIO shares HP bank with DDR calibration
set_property UNAVAILABLE_DURING_CALIBRATION TRUE [get_ports mdio_mdio]

# RXC is a 125 MHz RGMII RX clock from PHY (factory TEMAC window).
# IDDR is clocked from an MMCM 67.5° output of this pin (covers the 1.25–2.0 ns gap).
create_clock -period 8.000 -name rgmii_rxc [get_ports rgmii_rxc]
set_input_delay -clock [get_clocks rgmii_rxc] -max -1.000 [get_ports {rgmii_rd[*] rgmii_rx_ctl}]
set_input_delay -clock [get_clocks rgmii_rxc] -min -2.500 [get_ports {rgmii_rd[*] rgmii_rx_ctl}]
set_input_delay -clock [get_clocks rgmii_rxc] -clock_fall -max -1.000 -add_delay [get_ports {rgmii_rd[*] rgmii_rx_ctl}]
set_input_delay -clock [get_clocks rgmii_rxc] -clock_fall -min -2.500 -add_delay [get_ports {rgmii_rd[*] rgmii_rx_ctl}]
set_property SLEW FAST [get_ports {rgmii_td[*] rgmii_tx_ctl rgmii_txc}]

# Keep IDELAYCTRL + IDELAYE3 in one group (also set via RTL IODELAY_GROUP)
set_property IODELAY_GROUP netsec_rgmii_idly [get_cells -quiet -hier -filter {REF_NAME == IDELAYCTRL || ORIG_REF_NAME == IDELAYCTRL}]
set_property IODELAY_GROUP netsec_rgmii_idly [get_cells -quiet -hier -filter {REF_NAME == IDELAYE3 || ORIG_REF_NAME == IDELAYE3}]

################################################################
# 3. PL LED / KEY / UART (factory gpio.xdc / uart.xdc)
################################################################
set_property PACKAGE_PIN AE15 [get_ports pl_led]
set_property IOSTANDARD LVCMOS33 [get_ports pl_led]

set_property PACKAGE_PIN AE14 [get_ports pl_key_n]
set_property IOSTANDARD LVCMOS33 [get_ports pl_key_n]
set_property PULLUP true [get_ports pl_key_n]

set_property PACKAGE_PIN AA11 [get_ports pl_uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports pl_uart_tx]
set_property PACKAGE_PIN AA10 [get_ports pl_uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports pl_uart_rx]
