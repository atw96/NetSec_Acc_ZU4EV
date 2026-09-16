# Full dual-port L3 is scripts/run_l3_dualport.ps1
#   xsct_fpga_then_l3.tcl  — rst -system, TCK 100 kHz fpga, psu_init (skip DDR), dow
#   hw_l3_dump.tcl         — 1 MHz nsec_dump
# Incremental (PL already up): hw_l3_an_only.tcl then xsct_dow_only.tcl then dump.
source [file join [file dirname [info script]] hw_l3_prep.tcl]
