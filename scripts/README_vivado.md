# 本地 Vivado 2020.1 + AXU4EVB-P 部署指南

## 快速构建

```bat
cd NetSec-Accel-ZU4EV
vivado -mode batch -source scripts/create_project.tcl
vivado -mode batch -source scripts/build.tcl
```

- Part：`xczu4ev-sfvc784-1-i`
- 工程目录：`vivado_proj/`
- 比特流：`bitstream_output/`
- 报告：`docs/timing_report/`

## 关键文件

| 脚本 | 作用 |
|------|------|
| `create_project.tcl` | 建工程、加 RTL/XDC、建 BD |
| `create_bd.tcl` | 最小 PS + **jtag_axi** + SmartConnect，时钟来自 PL `axi_clk_in` |
| `create_debug_cores.tcl` | ILA：`ila_logic` / `ila_rgmii` |
| `hw_jtag.tcl` | Hardware Manager 读写 `0x80050000` |
| `ps_preset.tcl` | 厂家完整 PS 预设（**批处理勿直接 apply**，DDR 校验失败；GUI 导入用） |
| `extract_ps_preset.py` | 从 factory `design_1.bd` 再生 `ps_preset.tcl` |
| `build.tcl` | synth → impl → bitstream + 报告 |
| `create_sfp_pcs.tcl` | 可选 1000BASE-X PCS/PMA |
| `create_ibert.tcl` / `build_ibert.tcl` | IBERT @ **10.0G / 125 MHz**（X0Y4+X0Y5；IBERT 不能配 10.3125+125） |
| `hw_ibert_optical_10g.tcl` | 双光口光纤外环 PRBS31，测完烧回 rxdly |
| `create_gt_10g.tcl` | 双口 10G GT Wizard（`build.tcl` / `create_project.tcl` 默认会 source） |
| `build.tcl` | 默认 `system_top`：铜口 + 双光口 10G |
| `build_sfp10g.tcl` | 可选独立 top → `system_top_sfp10g.bit` |
| `hw_sfp10g.tcl` | 独立图互环读计数；默认图用 `nsec_sfp10g_check` |
| `hw_l5_bringup.tcl` | 默认图烧写 + L5a/L5b/L5c |
| `hw_jtag.tcl` | `nsec_sfp10g_check` / `nsec_l5_test` / `nsec_l5c_test` |

## PS / DDR 注意

批处理使用**最小 PS 配置**（PL0 100 MHz、HPM0_LPD、UART0）。完整 AXU4EVB-P DDR/GEM/USB 配置请从  
`doc/factory_vivado/board_test.xpr` GUI 导出后替换 BD 中的 PS。

## 自测

见 [`docs/selftest_loopback.md`](../docs/selftest_loopback.md)。默认 `LOOPBACK=1`（L0）。

## 引脚

见 [`docs/board_pinout.md`](../docs/board_pinout.md)。`constraints/axu4ev_template.xdc` 已废弃。
