################################################################
## debug_hub.xdc — implementation only
## Do NOT connect_debug_port here: a missed net leaves dbg_hub/clk
## open and opt_design fails (Chipscope 16-213). Vivado auto-connects
## dbg_hub from the ILA clocks (logic_clk / rgmii_rxc).
################################################################
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
