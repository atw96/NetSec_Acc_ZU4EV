################################################################
## sfp_gth.xdc
## NetSec-Accel-ZU4EV — SFP+ GTH refclk / channel / sideband
## Authority: docs/board_pinout.md
################################################################

# GT 125 MHz differential refclk
# SOURCE: factory gt.xdc ; schematic PAGE19 SiT9121AI-2B1-33E125.000000
# Do NOT constrain this port as 156.25 MHz. 156.25 MHz is GT TXUSRCLK2 (10.3125/66).
set_property PACKAGE_PIN V6 [get_ports mgtrefclk_p]
set_property PACKAGE_PIN V5 [get_ports mgtrefclk_n]
create_clock -period 8.000 -name mgtrefclk_125m [get_ports mgtrefclk_p]

# SFP1 = BANK224 Lane0 = GTHE4_CHANNEL_X0Y4 (factory gtwizard XDC ch0)
# SFP2 = BANK224 Lane1 = GTHE4_CHANNEL_X0Y5 (factory gtwizard XDC ch1)
# Serial GTH pins have no PACKAGE_PIN (dedicated).
set_property LOC GTHE4_CHANNEL_X0Y4 [get_cells -quiet -hier -filter {REF_NAME == GTHE4_CHANNEL && NAME =~ *gt_sfp_prbs*}]
set_property LOC GTHE4_CHANNEL_X0Y4 [get_cells -quiet -hier -filter {REF_NAME == GTHE4_CHANNEL && NAME =~ *gt_sfp_10g*channel_inst[0]*}]
set_property LOC GTHE4_CHANNEL_X0Y5 [get_cells -quiet -hier -filter {REF_NAME == GTHE4_CHANNEL && NAME =~ *gt_sfp_10g*channel_inst[1]*}]

# L4 wrap only (empty on default system_top)
set_false_path -from [get_cells -quiet -hier -filter {NAME =~ *u_gt/g_gt*}]
set_false_path -to   [get_cells -quiet -hier -filter {NAME =~ *u_gt/g_gt*}]

# Factory gt.xdc false paths (GT Wizard CDC / reset sync)
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *bit_synchronizer*inst/i_in_meta_reg}] -quiet
set_false_path -to [get_pins -filter REF_PIN_NAME=~*D -of_objects [get_cells -hierarchical -filter {NAME =~ *reset_synchronizer*inst/rst_in_meta*}]] -quiet
set_false_path -to [get_pins -filter REF_PIN_NAME=~*PRE -of_objects [get_cells -hierarchical -filter {NAME =~ *reset_synchronizer*inst/rst_in_meta*}]] -quiet
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *gtwiz_userclk_tx_inst/*gtwiz_userclk_tx_active_*_reg}] -quiet
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *gtwiz_userclk_rx_inst/*gtwiz_userclk_rx_active_*_reg}] -quiet

# Sideband (SOURCE: MANUAL-PAGE44 — not present in factory XDC)
# Bank45 peer edid_scl=F10 uses LVCMOS33 in hdmi_in.xdc
set_property PACKAGE_PIN D12 [get_ports sfp_tx_dis]
set_property IOSTANDARD LVCMOS33 [get_ports sfp_tx_dis]
set_property PACKAGE_PIN B10 [get_ports sfp1_los]
set_property IOSTANDARD LVCMOS33 [get_ports sfp1_los]
set_property PACKAGE_PIN C11 [get_ports sfp2_los]
set_property IOSTANDARD LVCMOS33 [get_ports sfp2_los]
