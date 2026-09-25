# Timing / Resource Reports

由 `scripts/build.tcl` 在本地 Vivado 2020.1 综合/实现后自动导出。

默认上板图是 2026-09-25 `bitstream_output/system_top.bit`（与 `system_top_rxdly.bit` 同内容）：**WNS +0.059 ns / WHS +0.010 ns**，LUT 60515 (68.89%)。`timing_summary.rpt` 里仍报的 WPWS −1.667 ns 是 `u_idelayctrl` REFCLK（200 MHz vs 器件 Max Period 3.333 ns）。历史 CLK90-off 对照图 WNS +1.002 ns。

- `timing_summary.rpt`
- `timing_summary_sfp.rpt` / `timing_summary_sfp10g.rpt`
- `utilization.rpt` / `utilization_synth.rpt`
- `clock_utilization.rpt`

若目录仍为空，说明实现尚未完成；请先：

```bat
vivado -mode batch -source scripts/create_project.tcl
vivado -mode batch -source scripts/build.tcl
```

切勿在简历中编造未经真实综合得出的 LUT/FF/时序数字。
