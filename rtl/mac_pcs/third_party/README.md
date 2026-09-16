# Third-party: verilog-ethernet (MIT)

- Upstream: https://github.com/alexforencich/verilog-ethernet
- Commit: `77320a9471d19c7dd383914bc049e02d9f4f1ffb` (see `verilog-ethernet/COMMIT.txt`)
- License: MIT (`verilog-ethernet/LICENSE`, originally `COPYING`)
- Vendored subset only: `eth_mac_1g_rgmii_fifo` and its RTL / `lib/axis` dependencies

本仓库自研数据面（parser / flow_table / dpi / ips / crypto）与本开源 MAC **分开标注**：
MAC 仅用于把 JL2121 RGMII 接到 AXI-Stream；安全加速逻辑均为自研。

## UltraScale+ 参数（本工程固定）

| Parameter | Value | Reason |
|-----------|-------|--------|
| `TARGET` | `"XILINX"` | Use Xilinx IDDR/ODDR |
| `IODDR_STYLE` | `"IODDR"` | UltraScale+ uses IDDRE1/ODDRE1 path via IODDR style |
| `CLOCK_INPUT_STYLE` | `"BUFG"` | Ultrascale RX clock buffering |
| `USE_CLK90` | `"TRUE"` | Center-aligned TXC (see RGMII phase note in docs) |
