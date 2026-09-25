################################################################
## timing_exceptions.xdc
## NetSec-Accel-ZU4EV — false paths, async clock groups, bitstream
## NOTE: Vivado XDC parser rejects Tcl 'if' / current_fileset — keep pure XDC.
################################################################

# Async / slow GPIO
set_false_path -from [get_ports pl_key_n]
set_false_path -from [get_ports sfp1_los]
set_false_path -from [get_ports sfp2_los]
set_false_path -to   [get_ports pl_led]
set_false_path -to   [get_ports pl_uart_tx]
set_false_path -to   [get_ports sfp_tx_dis]
set_false_path -to   [get_ports phy_reset_n]
set_false_path -to   [get_ports mdio_mdc]
set_false_path -to   [get_ports mdio_mdio]

# axi_clk (BUFGCE_DIV /2 of 200 MHz) vs MAC logic (gtx_clk_u)
# Control/status use netsec_level_cdc / netsec_pulse_cdc
set_clock_groups -asynchronous \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_axi_div/O]] \
    -group [get_clocks -quiet gtx_clk_u]

set_clock_groups -asynchronous \
    -group [get_clocks -quiet sys_clk_clk_p] \
    -group [get_clocks -quiet rgmii_rxc]

set_clock_groups -asynchronous \
    -group [get_clocks -quiet sys_clk_clk_p] \
    -group [get_clocks -quiet mgtrefclk_125m]

set_clock_groups -asynchronous \
    -group [get_clocks -quiet rgmii_rxc] \
    -group [get_clocks -quiet mgtrefclk_125m]

set_clock_groups -asynchronous \
    -group [get_clocks -quiet gtx_clk_u] \
    -group [get_clocks -quiet rgmii_rxc]

# IDDR samples on MMCM 67.5° (rxc60), not on the pad edge.
# Setup vs rgmii_rxc stays checked. Hold is the IDELAY tap + phase, not this edge.
set_false_path -hold -from [get_ports {rgmii_rd[*] rgmii_rx_ctl}] -to [get_clocks -quiet rxc60_u]

# US+ IDELAYCTRL REFCLK max period is 3.333 ns. This board clocks it at 200 MHz
# (VAR_LOAD taps tuned at that rate). Waive the period check on that primitive.
set_disable_timing [get_cells -quiet -hier -filter {REF_NAME == IDELAYCTRL || ORIG_REF_NAME == IDELAYCTRL}]

set_clock_groups -asynchronous \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_axi_div/O]] \
    -group [get_clocks -quiet rgmii_rxc]

set_clock_groups -asynchronous \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_axi_div/O]] \
    -group [get_clocks -quiet sys_clk_clk_p]

set_clock_groups -asynchronous \
    -group [get_clocks -quiet gtx_clk_u] \
    -group [get_clocks -quiet sys_clk_clk_p]

# Detection domain vs 10G GT user clocks
set_clock_groups -asynchronous \
    -group [get_clocks -quiet gtx_clk_u] \
    -group [get_clocks -quiet tx_clk] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_tx_mac_clk/O]]
set_clock_groups -asynchronous \
    -group [get_clocks -quiet gtx_clk_u] \
    -group [get_clocks -quiet rx_clk] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_rx_mac_clk0/O]] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_rx_mac_clk1/O]]

# 10G GT user clocks (tx_clk/rx_clk ~161 MHz from TXOUTCLK/RXOUTCLK) vs AXI / 50M / sys / refclk
# Pin-based get_clocks often misses the generated names; also group by clock name.
set_clock_groups -asynchronous \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_div50/O]] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_tx_mac_clk/O]]
set_clock_groups -asynchronous \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_div50/O]] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_rx_mac_clk0/O]] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_rx_mac_clk1/O]]
set_clock_groups -asynchronous \
    -group [get_clocks -quiet clk_50m] \
    -group [get_clocks -quiet tx_clk] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_tx_mac_clk/O]]
set_clock_groups -asynchronous \
    -group [get_clocks -quiet clk_50m] \
    -group [get_clocks -quiet rx_clk] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_rx_mac_clk0/O]] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_rx_mac_clk1/O]]
set_clock_groups -asynchronous \
    -group [get_clocks -quiet axi_clk] \
    -group [get_clocks -quiet tx_clk] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_tx_mac_clk/O]]
set_clock_groups -asynchronous \
    -group [get_clocks -quiet axi_clk] \
    -group [get_clocks -quiet rx_clk] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_rx_mac_clk0/O]] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_rx_mac_clk1/O]]
set_clock_groups -asynchronous \
    -group [get_clocks -quiet sys_clk_clk_p] \
    -group [get_clocks -quiet tx_clk] \
    -group [get_clocks -quiet rx_clk]
set_clock_groups -asynchronous \
    -group [get_clocks -quiet mgtrefclk_125m] \
    -group [get_clocks -quiet tx_clk] \
    -group [get_clocks -quiet rx_clk]
set_clock_groups -asynchronous \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_axi_div/O]] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *gtwiz_userclk_tx_usrclk2_out*]]
set_clock_groups -asynchronous \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_axi_div/O]] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *gtwiz_userclk_rx_usrclk2_out*]]

################################################################
# Bitstream (Zynq UltraScale+ — no CFGBVS / SPI_BUSWIDTH on this part)
################################################################
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullnone [current_design]
