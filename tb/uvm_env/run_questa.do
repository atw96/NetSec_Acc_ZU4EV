# QuestaSim / ModelSim UVM smoke for netsec_datapath
# Run from repo root:
#   C:\modeltech64_2020.4\win64\vsim.exe -c -do tb/uvm_env/run_questa.do
#
# Prebuilt 64-bit uvm_dpi.dll + -nodpiexports avoids compiling export_tramp.dll
# with the system 32-bit MinGW (which cannot assemble x86_64 %rax).

set REPO [pwd]
set MS   "C:/modeltech64_2020.4"
set UVM  "$MS/verilog_src/uvm-1.2"
set DPI  "$MS/uvm-1.2/win64/uvm_dpi"

puts "REPO=$REPO"
if {![file exists "$REPO/rtl/common/sync_fifo.sv"]} {
  puts "ERROR: run from NetSec-Accel-ZU4EV repo root"
  quit -code 1
}

vlib work
vmap work work

vlog -sv +incdir+$UVM/src \
  $UVM/src/uvm_pkg.sv \
  $REPO/rtl/common/sync_fifo.sv \
  $REPO/rtl/packet_parser/packet_parser.sv \
  $REPO/rtl/flow_table/flow_table.sv \
  $REPO/rtl/dpi_engine/dpi_matcher.sv \
  $REPO/rtl/ips_decision/ips_decision.sv \
  $REPO/rtl/top/netsec_datapath.sv \
  $REPO/tb/uvm_env/tb_netsec_uvm.sv

if {[catch {
  vsim -c -nodpiexports -sv_lib $DPI work.tb_netsec_uvm \
    +UVM_TESTNAME=netsec_smoke_test \
    +UVM_NO_RELNOTES
} err]} {
  puts "VSIM error: $err"
  quit -code 2
}
run -all
quit -f
