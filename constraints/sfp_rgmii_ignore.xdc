################################################################
## SFP-only: RGMII pads are unused on system_top_sfp.
## Do not add this file to the default (L0–L3) constraint set.
################################################################
set_false_path -from [get_ports -quiet rgmii_rxc]
set_false_path -from [get_ports -quiet {rgmii_rd[*]}]
set_false_path -from [get_ports -quiet rgmii_rx_ctl]
set_false_path -to   [get_ports -quiet rgmii_txc]
set_false_path -to   [get_ports -quiet {rgmii_td[*]}]
set_false_path -to   [get_ports -quiet rgmii_tx_ctl]
