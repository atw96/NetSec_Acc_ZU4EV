# IBERT example extra: enable SFP lasers
# SOURCE: MANUAL-PAGE44
set_property PACKAGE_PIN D12 [get_ports sfp_tx_dis]
set_property IOSTANDARD LVCMOS33 [get_ports sfp_tx_dis]
set_false_path -to [get_ports sfp_tx_dis]
