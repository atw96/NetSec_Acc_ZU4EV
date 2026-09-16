# Timing / Resource Reports

由 `scripts/build.tcl` 在本地 Vivado 2020.1 综合/实现后自动导出。

注意：`build_clk90off.tcl` 会覆盖本目录为 **CLK90-off** 图（最近一次 WNS +1.002 ns）。默认上板图仍是 `bitstream_output/system_top_clk90on.bit`（WNS +0.909 ns）。README 资源表以 clk90on 为准。

- `timing_summary.rpt`
- `utilization.rpt` / `utilization_synth.rpt`
- `clock_utilization.rpt`

若目录仍为空，说明实现尚未完成；请先：

```bat
vivado -mode batch -source scripts/create_project.tcl
vivado -mode batch -source scripts/build.tcl
```

切勿在简历中编造未经真实综合得出的 LUT/FF/时序数字。
