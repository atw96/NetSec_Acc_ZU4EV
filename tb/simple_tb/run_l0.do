set REPO [pwd]
if {![file exists "$REPO/rtl/common/sync_fifo.sv"]} {
    puts "ERROR: run from repo root"
    quit -code 1
}
vlib work
vmap work work
vlog -sv \
  $REPO/rtl/common/sync_fifo.sv \
  $REPO/rtl/packet_parser/packet_parser.sv \
  $REPO/rtl/flow_table/flow_table.sv \
  $REPO/rtl/dpi_engine/dpi_matcher.sv \
  $REPO/rtl/ips_decision/ips_decision.sv \
  $REPO/rtl/top/pkt_gen_bram.sv \
  $REPO/rtl/top/netsec_datapath.sv \
  $REPO/tb/simple_tb/tb_l0_loopback.sv
vsim -c -nodpiexports -voptargs=+acc tb_l0_loopback -do "run -all; quit -f"
