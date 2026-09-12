# 06 IPS 决策与动作引擎 (IPS Decision Engine)

## 功能描述
综合流表状态（02模块）与 DPI 命中结果（04模块），对每个报文/流做出
放行(FORWARD) / 丢弃(DROP) / 限速(RATE_LIMIT) / 镜像上送PS(MIRROR_TO_PS) 四选一决策。

## 决策表（简化策略，参数可通过 AXI4-Lite 由 PS 侧配置覆盖）

| flow_state (02模块) | dpi_hit (04模块) | 决策 |
|---|---|---|
| 已阻断(11) | 任意 | DROP |
| 已标记可疑(10) | 命中 | DROP + MIRROR_TO_PS（告警） |
| 已标记可疑(10) | 未命中 | RATE_LIMIT |
| 已放行(01)/新流(00) | 命中 | DROP + MIRROR_TO_PS（首次命中转标记可疑，写回流表） |
| 已放行(01)/新流(00) | 未命中 | FORWARD |

## 接口定义
输入：`flow_state[1:0]`, `dpi_hit`, `valid`
输出：`action[1:0]`（00=FORWARD, 01=DROP, 10=RATE_LIMIT, 11=MIRROR_TO_PS）,
`flow_update_state[1:0]`（回写流表的新状态，供 02 模块更新）

限速（Rate Limit）实现：简单令牌桶（Token Bucket），每流独立计数器，
超出令牌预算的报文降级为 DROP，令牌按固定周期补充。

## 时序/资源预估
- 决策表：组合逻辑 + 1 级流水线寄存，LUT 约 50~100。
- 令牌桶（每流独立，依托 02 模块 BRAM 表项扩展字段）：额外 8bit/表项。

## 验证方式
`tb/simple_tb/tb_ips_decision.sv` 覆盖决策表全部组合（穷举 flow_state x dpi_hit）。
