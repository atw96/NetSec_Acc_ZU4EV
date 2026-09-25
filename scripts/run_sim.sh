#!/usr/bin/env bash
# 使用 Icarus Verilog 运行本仓库全部单元级自检 Testbench。
# 依赖: iverilog, vvp (sudo apt-get install iverilog)
set -e
cd "$(dirname "$0")/.."

run() {
    name=$1; shift
    echo "=============================================="
    echo ">>> Running $name"
    echo "=============================================="
    iverilog -g2012 -o /tmp/sim_${name}.vvp "$@"
    vvp /tmp/sim_${name}.vvp
    echo ""
}

run packet_parser rtl/packet_parser/packet_parser.sv tb/simple_tb/tb_packet_parser.sv
run checksum      rtl/tcpip_offload/checksum_rfc1071.sv tb/simple_tb/tb_checksum.sv
run aes128         rtl/crypto/aes/aes_sbox_pkg.sv rtl/crypto/aes/aes128_core.sv tb/simple_tb/tb_aes128.sv
run dpi            rtl/dpi_engine/dpi_matcher.sv tb/simple_tb/tb_dpi_engine.sv
run flow_table     rtl/flow_table/flow_table.sv tb/simple_tb/tb_flow_table.sv
run ips_decision   rtl/ips_decision/ips_decision.sv tb/simple_tb/tb_ips_decision.sv
run modexp         rtl/crypto/modexp/modexp_demo.sv tb/simple_tb/tb_modexp.sv
run common_smoke   rtl/common/sync_fifo.sv rtl/common/cdc_sync.sv tb/simple_tb/tb_common_smoke.sv
run l0_loopback    rtl/crypto/aes/aes_sbox_pkg.sv rtl/crypto/aes/aes128_core.sv rtl/common/sync_fifo.sv rtl/packet_parser/packet_parser.sv rtl/flow_table/flow_table.sv rtl/dpi_engine/dpi_matcher.sv rtl/ips_decision/ips_decision.sv rtl/top/pkt_gen_bram.sv rtl/top/netsec_datapath.sv tb/simple_tb/tb_l0_loopback.sv
run aes_datapath   rtl/crypto/aes/aes_sbox_pkg.sv rtl/crypto/aes/aes128_core.sv rtl/common/sync_fifo.sv rtl/packet_parser/packet_parser.sv rtl/flow_table/flow_table.sv rtl/dpi_engine/dpi_matcher.sv rtl/ips_decision/ips_decision.sv rtl/top/pkt_gen_bram.sv rtl/top/netsec_datapath.sv tb/simple_tb/tb_aes_datapath.sv
VE=rtl/mac_pcs/third_party/verilog-ethernet
run sfp10g_axis_if rtl/top/pkt_gen_10g.sv tb/simple_tb/tb_sfp10g_axis_if.sv
run axis_bridge    $VE/lib/axis/rtl/axis_adapter.v $VE/lib/axis/rtl/axis_async_fifo.v $VE/lib/axis/rtl/axis_async_fifo_adapter.v rtl/top/netsec_axis_bridge.sv tb/simple_tb/tb_netsec_axis_bridge.sv
run ns10g_inline   rtl/crypto/aes/aes_sbox_pkg.sv rtl/crypto/aes/aes128_core.sv rtl/common/sync_fifo.sv rtl/packet_parser/packet_parser.sv rtl/flow_table/flow_table.sv rtl/dpi_engine/dpi_matcher.sv rtl/ips_decision/ips_decision.sv rtl/top/pkt_gen_bram.sv rtl/top/netsec_datapath.sv rtl/top/netsec10g_switch.sv tb/simple_tb/tb_netsec10g_inline.sv
run mac10g_loop    $VE/rtl/lfsr.v $VE/rtl/axis_baser_rx_64.v $VE/rtl/axis_baser_tx_64.v $VE/rtl/xgmii_baser_dec_64.v $VE/rtl/xgmii_baser_enc_64.v $VE/rtl/axis_xgmii_rx_64.v $VE/rtl/axis_xgmii_tx_64.v $VE/rtl/eth_phy_10g_rx_ber_mon.v $VE/rtl/eth_phy_10g_rx_frame_sync.v $VE/rtl/eth_phy_10g_rx_watchdog.v $VE/rtl/eth_phy_10g_rx_if.v $VE/rtl/eth_phy_10g_tx_if.v $VE/rtl/eth_phy_10g_rx.v $VE/rtl/eth_phy_10g_tx.v $VE/rtl/eth_phy_10g.v $VE/rtl/eth_mac_phy_10g_rx.v $VE/rtl/eth_mac_phy_10g_tx.v $VE/rtl/eth_mac_phy_10g.v rtl/top/pkt_gen_10g.sv tb/simple_tb/tb_mac10g_digital_loop.sv
run ns10g_regs     rtl/top/netsec_regs.sv tb/simple_tb/tb_ns10g_regs.sv

echo "=============================================="
echo "All testbenches executed. Review PASS/FAIL lines above."
echo "=============================================="
