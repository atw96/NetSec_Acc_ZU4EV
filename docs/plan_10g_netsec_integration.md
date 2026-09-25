# 双 SFP+ 10G 光口安全检测通路合入计划（PLAN）

| 项 | 内容 |
|---|---|
| 文档状态 | 计划（未实施） |
| 目标器件 | XCZU4EV-1SFVC784I（ALINX ACU4EV + AXU4EVB-P） |
| 涉及接口 | SFP1（GTH X0Y4）、SFP2（GTH X0Y5），10GBASE-R，refclk 125 MHz SiT9121（V6/V5） |
| 上游现状 | 双口 10G PCS/MAC 已锁定并收发（`sfp10g_wrap`，寄存器 `0xC0`–`0xDC`，2026-09-24 板测 PASS）；10G AXIS **尚未**接入 `netsec_datapath` |
| 关联文档 | [architecture.md](architecture.md) / [selftest_loopback.md](selftest_loopback.md) / [bringup_log.md](bringup_log.md) / [verification_plan.md](verification_plan.md) |

---

## 1. 背景与目标

### 1.1 现状

默认 `system_top`（`NETSEC_ENABLE_SFP10G=1`）中，两套数据面互相独立：

- **铜口 1G 检测通路（已验证）**：RGMII MAC → 8-bit AXIS → `netsec_datapath`
  （报文解析 / 流表 / DPI / IPS 决策 / AES 数据面 / MAC 交换）→ RGMII TX。
  时钟域 `logic_clk` = 125 MHz（200 MHz 晶振 MMCM，与铜口链路状态无关）。
- **双 SFP 10G 通路（仅连通性已验证）**：`sfp10g_wrap` 内 2× `eth_mac_phy_10g`，
  TX 由 `pkt_gen_10g`（BIST 包源）直驱，RX 侧 **AXIS 数据未连接**，仅产生脉冲计数
  （`CNT_TX/RX/BAD` 每口 3 个）。TX 域 `tx_clk`、RX 域 `rx_clk0/rx_clk1` 均为 BUFGCE 门控的 GT 用户时钟（~156 MHz）。

### 1.2 差距

| # | 差距 | 影响 |
|---|------|------|
| G1 | 10G RX AXIS 数据被丢弃，不经过任何安全模块 | 光口无检测能力 |
| G2 | 10G TX 只能发 BIST 帧，无法转发受检帧 | 光口无转发能力 |
| G3 | 位宽/时钟不匹配：64-bit@~156 MHz（门控）vs 8-bit@125 MHz | 需 CDC + 位宽适配 |
| G4 | 单 PL 网口时代"无法做双口穿透"（architecture.md §2）的限制仍在 | 双 SFP 互环硬件已具备，RTL 未利用 |
| G5 | 已知开放问题：RX `BAD≈RX`（bringup_log 2026-09-24，RX 约为对端 TX 一半，几乎每帧标 bad_fcs/bad_frame，STATUS bit13 high_ber 置位） | 坏帧若按规范丢弃，INLINE 模式几乎无有效流量；**必须先行定位** |
| G6 | 寄存器 `0x00–0xDC` 已占用，per-port 安全统计无空间 | 需扩展地址译码 |

### 1.3 目标

**功能目标**：两个 SFP+ 光口各自具备与铜口等价的 netsec 安全能力，并支持双口穿透（inline 网关）形态：

1. 每端口独立实例化完整安全检测链：报文解析 → 流表 → DPI（4×4B Aho-Corasick）→ IPS 决策（FORWARD / DROP / RATE_LIMIT / MIRROR）→（可选）AES 数据面加密 → 转发，附 per-port 统计与 IPv4 头校验和校验。
2. 三种工作模式（寄存器可选）：**INLINE**（SFP1 RX→检测→SFP2 TX；SFP2 RX→检测→SFP1 TX，双口穿透）、**LOOP**（每口收发自成环）、**BIST**（保持现 `pkt_gen_10g` 直驱行为，L4 回归不变）。
3. 铜口 1G 检测通路行为**完全不变**（L0–L3 判据不受影响）。

**非目标（明确排除，写入 README"设计选择"）**：

- 不承诺 10G 线速检测吞吐：阶段一为"线速收 + 降速检 + 线速发"的存储转发形态，持续检测吞吐上限 ≈ 1 Gbps/口（8 bit × 125 MHz），超限流量整帧丢弃并计数（诚实标注，与现有铜口"存储转发一次一帧"的限制同级）。
- 不做多规则集 DPI / TCAM 流表 / AES-GCM 等商用特性（维持仓库 PoC 定位）。
- 10G 线速（64-bit 并行检测通路）列为附录 A 演进路线，不在本计划交付。

### 1.4 总体验收标准

- 仿真：新增 TB 全部 PASS（Icarus + XSim 双跑），存量 TB 回归 PASS。
- 时序：默认 `system_top` 实现 WNS ≥ 0。
- 板级：`selftest_loopback.md` 新增 **L5** 分级判据全部有实测数字（L5b 自环级），L5c（外部 10G 打流）允许标注 NEED_HW。
- 文档：README 特性表、architecture.md、bringup_log.md 同步更新，未实测项不得标"通过"。

---

## 2. 现状基线（合入前冻结）

| 项 | 内容 |
|---|---|
| 10G MAC/PCS | `rtl/mac_pcs/sfp10g_wrap.sv`：2× `eth_mac_phy_10g`（DATA_WIDTH=64，含 FCS 插入/校验），GT Wizard `gt_sfp_10g`（64B66B 齿轮箱，TXSEQUENCE 0–32，RX 数据/valid 寄存一拍后 BUFGCE 门控） |
| 10G 时钟域 | `tx_clk`（= `u_tx_mac_clk` BUFGCE 门控）、`rx_clk0` / `rx_clk1`（= `u_rx_mac_clk0/1` 门控），均派生自 GT `tx_clk_gt`/`rx_clk_gt`；`axi_clk` 100 MHz；`logic_clk` 125 MHz（铜口检测域，源为 200 MHz 晶振，**与铜口链路无关，可复用**） |
| 10G 寄存器 | `0xC0` SFP10G_ST、`0xC4/C8/CC` 口 0 TX/RX/BAD、`0xD0/D4/D8` 口 1、`0xDC` SFP10G_CTRL（bit0 tx_enable）。地址译码仅 `addr[7:0]` |
| 安全模块 | `netsec_datapath`（8-bit AXIS，store-and-forward，FRAME_DEPTH=2048，ENABLE_MAC_SWAP=1，AES_OFF=42）：parser / flow_table(HASH_BITS=4) / dpi_matcher / ips_decision / aes128_core 数据面 |
| 三方库 | verilog-ethernet（MIT）已在工程，**`axis_async_fifo.v`、`axis_async_fifo_adapter.v`（异步 FIFO + 位宽适配一体）可直接复用** |
| 板级判据链 | L0→L4 已定义；10G 双口 lock+RX 增长 PASS；RX BAD 异常未闭环（G5） |
| 资源余量 | LUT 25.3% / BRAM 5.9% / DSP 4 / MMCM 2（共 4）——新增 2 套检测通路 + 4 个异步 FIFO 资源充足 |

---

## 3. 目标架构

### 3.1 框图（合入后默认图）

```
                       ┌─────────────────────── netsec_top ────────────────────────────────┐
                       │                                                                    │
 SFP1 (X0Y4) ◄──────── │ ◄─ sfp10g_wrap ── rx0_axis(64b) ─┐                                │
   10GBASE-R  ───────► │ ─ tx0_axis(64b) ◄───────────────┐│                                │
                       │                                 ││                                │
                       │        ┌────────────────────────┘│                                │
                       │        ▼                         ▼                                │
                       │  ┌──────────────────┐   ┌──────────────────┐                      │
                       │  │ bridge_rx0       │   │ bridge_tx1       │                      │
                       │  │ async FIFO       │   │ 8→64 upsize      │                      │
                       │  │ 64→8 + tkeep     │   │ + async FIFO     │                      │
                       │  │ + 坏帧过滤/计数  │   │                  │                      │
                       │  └───────┬──────────┘   └────────▲─────────┘                      │
                       │          │ 8b @ logic_clk(125M)  │ 8b @ logic_clk                 │
                       │          ▼                       │                                │
                       │  ┌──────────────────┐   ┌────────┴─────────┐                      │
                       │  │ netsec_datapath  │   │ netsec_datapath  │   （模式交换         │
                       │  │  port1 (DP_A)    │   │  port2 (DP_B)    │    netsec10g_       │
                       │  │ parser+flow+DPI  │   │ parser+flow+DPI  │    switch 内完成）   │
                       │  │ +IPS(+AES+csum)  │   │ +IPS(+AES+csum)  │                      │
                       │  └────────▲─────────┘   └────────┬─────────┘                      │
                       │           │ 8b                     │ 8b                            │
                       │  ┌────────┴──────────┐   ┌────────▼─────────┐                      │
                       │  │ bridge_tx0        │   │ bridge_rx1       │                      │
                       │  │ 8→64 + async FIFO │   │ async FIFO 64→8  │                      │
                       │  └────────▲──────────┘   └────────▲─────────┘                      │
                       │           │                       │                                │
 SFP2 (X0Y5) ◄──────── │ ─ tx1_axis(64b)   sfp10g_wrap ── rx1_axis(64b) ─┘                 │
   10GBASE-R  ───────► │                                                                    │
                       │  模式（NS10G_CTRL[1:0]）：                                          │
                       │   BIST  ：pkt_gen_10g 直驱 TX（现行为，L4 回归）                     │
                       │   INLINE：DP_A 出→口1 TX，DP_B 出→口0 TX（上图默认，双口穿透）        │
                       │   LOOP  ：DP_A 出→口0 TX，DP_B 出→口1 TX（每口自环）                 │
                       └────────────────────────────────────────────────────────────────────┘
```

说明：INLINE 模式即"bump-in-the-wire"明细网关——SFP1 进、SFP2 出（及反向），两方向各自独立检测；这正是 architecture.md §2 中"单 PL 网口无法双口穿透"限制的解除。

### 3.2 每端口安全功能映射（与铜口对齐）

| netsec 能力 | 铜口（现状） | SFP1（本计划） | SFP2（本计划） |
|---|---|---|---|
| 报文解析（L2/L3/L4 五元组） | `u_parser` | DP_A 内 `u_parser` | DP_B 内 `u_parser` |
| 流表匹配（Hash 64 项） | `u_ft` | DP_A 独立实例 | DP_B 独立实例 |
| DPI 4×4B Aho-Corasick | `u_dpi`（全局 4 条特征） | DP_A 实例，**共享同一组 `DPI_PAT0..3`** | DP_B 实例，同左 |
| IPS 决策（FWD/DROP/RL/MIR） | `u_ips` | DP_A 独立实例 + per-port 计数 | DP_B 独立实例 + per-port 计数 |
| AES-128 数据面（帧内偏移 42 起 16B） | CTRL[12] 全局 | NS10G_CTRL[8] 独立使能，CT 可读回 | NS10G_CTRL[9] 独立使能，CT 可读回 |
| RFC1071 校验和 | MMIO（`0x90/0x94`） | MMIO 共用 + **每口 IPv4 头校验和在线校验**（计数） | 同左 |
| 统计/上板 | `0x10–0x24` | `0x108+` per-port | `0x120+` per-port |

### 3.3 帧数据处理约定

- **坏帧（`rx_axis_tuser=1`，FCS/长度错）**：在 bridge RX 侧直接丢弃并计数（`CNT_BADRXn`），不进检测通路（IPS 语义：坏帧即威胁）。
- **超长帧**（> FRAME_DEPTH）：沿用 datapath 现有 abort/drop 行为；bridge 异步 FIFO 采用 FRAME_FIFO 模式整帧丢弃，防溢出撕裂。
- **tkeep**：RX 尾拍非整 8B 时按 tkeep 屏蔽；TX 侧由 8-bit 流重组，尾拍自动生成 tkeep（10G MAC 自行追加 FCS）。
- **MAC 交换**：光口 datapath 实例默认 `ENABLE_MAC_SWAP=0`（透明 inline，转发帧字节不变，便于自环/打流比对）；铜口保持 =1 不动。

---

## 4. 关键设计决策

| # | 决策 | 选项对比 | 结论与理由 |
|---|------|---------|-----------|
| D1 | 检测通路位宽 | (a) 复用 8-bit `netsec_datapath` + CDC/位宽桥；(b) 新写 64-bit 宽通路 | **选 (a)**：PoC 首要目标是"功能合入、每口可检"，(a) 复用已上板验证的 datapath，风险与工作量最小；(b) 线速收益对本仓库验证场景无意义，列附录 A |
| D2 | 检测域时钟 | (a) 复用 `logic_clk` 125 MHz；(b) 新 MMCM 156.25 MHz | **选 (a)**：`logic_clk` 源自 200 MHz 晶振（`rgmii_mac_wrap` 内 MMCM），与铜口 PHY 链路状态无关，零新增时钟域、复位树与 CDC 结构全部沿用；(b) 仅 1G→1.25G 收益，不值一个 MMCM |
| D3 | CDC/位宽适配 | 自研 vs verilog-ethernet `axis_async_fifo_adapter` | **选三方库**（已在工程内，MIT）：一个实例同时完成异步 FIFO + 64↔8 位宽 + tkeep/tlast/tuser 传递；自研仅薄封装 `netsec_axis_bridge`（坏帧过滤、整帧丢弃、计数） |
| D4 | 每端口 datapath 数量 | (a) 每口独立实例；(b) 单实例分时复用 | **选 (a)**：两口完全并行、故障隔离、语义清晰（"每个网口都支持全部功能"）；资源余量充足（预估 +~4k LUT / +~6 BRAM36，见 §8 预估） |
| D5 | 流表归属 | 每口独立 vs 全局共享 | **每口独立**（D4 自然结果）；共享流表列为后续增强（inline 网关通常按方向独立会话表） |
| D6 | 转发拓扑 | 固定 INLINE vs 模式寄存器 | **模式寄存器**（BIST/INLINE/LOOP/DISABLE）：保 L4 回归、覆盖单口自环与双口穿透两形态，上板无光模块/有光纤互环均可测 |
| D7 | 寄存器布局 | 挤 `0xE0–0xFF` vs 扩译码到 `[8:0]` 放 `0x100+` | **扩译码**：需要 ≥26 个新寄存器字（CTRL/ST + 12 计数 + 2×4 AES 读回 + 余量），`0xE0+` 仅 8 字不够；`0x100–0x1FF` 干净整块，`hw_jtag.tcl` 64KB 窗口天然覆盖 |
| D8 | G5（RX BAD≈RX）处置 | 合入后顺带观察 vs 前置专项 | **前置专项（M0/M1）**：根因不除，INLINE 坏帧全丢、判据失真。首选假设 H1：`eth_phy_10g_rx_ber_mon` 在 ~10.25G 实际速率（125 MHz 晶振 vs wizard 声明 125.76 MHz）下误判 high_ber → 反复 `rx_reset_req` → RX 断流丢字 → FCS 错、RX≈TX/2（与实测现象吻合，STATUS bit13 high_ber1=1 已观察到）。验证/缓解见 §8 |

---

## 5. 详细设计

### 5.1 `sfp10g_wrap` 接口开放（改造 `rtl/mac_pcs/sfp10g_wrap.sv`）

新增端口（全部为 GT MAC 域信号，不新增时钟）：

| 端口 | 方向 | 说明 |
|---|---|---|
| `tx0_axis_tdata[63:0]/tkeep[7:0]/tvalid/tready/tlast/tuser` | in/out | 口 0（SFP1）TX 客户端接口（`tx_clk` 域） |
| `rx0_axis_tdata[63:0]/tkeep[7:0]/tvalid/tready/tlast/tuser` | out/in | 口 0 RX 客户端接口（`rx_clk0` 域）；**连接 `eth_mac_phy_10g` 现悬空的 `rx_axis_tkeep`** |
| 口 1 同上（`tx1_*` / `rx1_*`） | | `tx_clk` / `rx_clk1` 域 |
| `tx_src[1:0]` | in | 每口 TX 源选择：`0`=BIST（内部 `pkt_gen_10g`，现行为），`1`=外部 AXIS |

内部改动：

1. TX mux：`axis_tdata[i] = tx_src[i] ? txN_axis_tdata : gen_tdata[i]`（valid/keep/last/user 同 mux；`pkt_gen` 的 `m_tready` 接 mux 后 ready）。BIST 模式寄存器默认值保持 `tx_src=0`，L4 流程不变。
2. RX：`rxN_axis_*` 直连 MAC 输出；现有 `pulse_rx/pulse_bad` 计数逻辑保留（`0xC0–0xD8` 读数不受影响）；`rx_axis_tready` 由外部 bridge 提供（bridge 常置 1，背压由异步 FIFO 满通过 FRAME_FIFO 丢帧语义承担）。
3. `nearend_loopback`（GT 近端 PMA 环回）保留——它是 G5 定位的关键手段。
4. 独立 `system_top_sfp10g` 调试图同步增加等价直连（保持隔离对照能力）。

### 5.2 CDC 与位宽适配（新模块 `rtl/top/netsec_axis_bridge.sv`）

每端口两方向各一个子实例，模块顶层封装：

```
netsec_axis_bridge #(.DEPTH(1024)) u_br0 (
  .rx_mac_clk(rx_clk0), .rx_rst_n(rst_rx0_n),        // 64b in (rx_clk0 域)
  .rx_mac_tdata/tkeep/tvalid/tready/tlast/tuser,
  .tx_mac_clk(tx_clk),  .tx_rst_n(rst_tx_n),         // 64b out (tx_clk 域)
  .tx_mac_tdata/tkeep/tvalid/tready/tlast/tuser,
  .logic_clk(logic_clk), .logic_rst_n(rst_n_logic),  // 8b 检测域
  .s_tdata[7:0]/s_tvalid/s_tready/s_tlast,           // → datapath 入口
  .m_tdata[7:0]/m_tvalid/m_tready/m_tlast,           // ← datapath 出口
  .cnt_badrax, cnt_rx_ovf, ...                       // 坏帧/溢出丢帧脉冲
```

实现要点：

- **RX 方向**：`axis_async_fifo_adapter`（IN：64b/KEEP_ENABLE=1，OUT：8b，`FRAME_FIFO=1, DROP_OVERSIZE_FRAME=1, DROP_BAD_FRAME=1`）直接完成"rx_clkN → logic_clk + 64→8 + tkeep 剥离 + 坏帧/超长帧整帧丢弃"。深度 1024×64b（8 KB，≈3 个 36Kb BRAM）。
- **TX 方向**：`axis_async_fifo_adapter`（IN：8b，OUT：64b/KEEP，`FRAME_FIFO=1`）完成"logic_clk → tx_clk + 8→64 重组 + 尾拍 tkeep 生成"。深度同上。
- 门控时钟（BUFGCE `tx_clk/rx_clkN`）作异步 FIFO 端口时钟是安全的（格雷指针 CDC 与时钟占空比无关）；XDC 已有时钟组，新增 `logic_clk(gtx_clk_u) ↔ tx_clk/rx_clk` 异步组即可（§5.6）。
- 溢出语义：`FRAME_FIFO+DROP_OVERSIZE` 下写满整帧丢弃，输出 `drop_frame` 脉冲进 per-port 计数；**不产生撕裂帧**。
- 统计脉冲（badrx/ovf/rx/tx）经 `netsec_pulse_cdc` 到 `axi_clk` 域计数（复用现有 CDC 单元）。

### 5.3 光口检测交换（新模块 `rtl/top/netsec10g_switch.sv`）

职责：模式 mux + 2× `netsec_datapath` 实例 + per-port 统计汇聚。

```
mode[1:0]: 00 BIST / 01 INLINE / 10 LOOP / 11 DISABLE
dp_en[1:0]: 每口检测使能（=0 时该口 bridge RX 直通 TX，绕过 datapath，用于 A/B 对照）
```

| mode | bridge_rx0 → | bridge_rx1 → | 说明 |
|---|---|---|---|
| BIST | 丢弃（计数） | 丢弃 | TX 由 wrap 内 pkt_gen 直驱，等价现行为 |
| INLINE | DP_A → tx1 | DP_B → tx0 | 双口穿透（默认演示形态） |
| LOOP | DP_A → tx0 | DP_B → tx1 | 每口自环 |
| DISABLE | 丢弃 | 丢弃 | 静默 |

- DP_A/DP_B = `netsec_datapath #(.FRAME_DEPTH(4096), .ENABLE_MAC_SWAP(0))`（4096 容纳 1518B MTU + 余量；如综合显示 BRAM 压力可回落 2048）。
- 共享输入：`dpi_pat0..3`（axi 域 CDC 到 logic 域，沿用现有 `netsec_level_cdc`，两实例并联同一份）。
- 每口独立：`aes_key` 共用一把（简化密钥管理；per-port key 列为可选增强）、`aes_dp_en` 独立（NS10G_CTRL[8]/[9]）、`aes_dp_ct/done` 独立输出至寄存器读回。
- **IPv4 头校验和在线校验（新增小逻辑，随 DP 实例内联或 switch 侧旁挂）**：捕获阶段对 IP 头 20B（IHL=5）做 16bit 反码累加，帧尾不为 0xFFFF 则 `cnt_csum_errN` 脉冲。每口一个计数器，作为"TCP/IP offload 能力覆盖每口"的可观测证据。
- IPS 行为语义与铜口完全一致（首次 DPI 命中 MIRROR、流表状态迁移等），L5 判据直接复用 L0 的行为模型。

### 5.4 寄存器扩展（`rtl/top/netsec_regs.sv`）

地址译码 `addr[7:0]` → `addr[8:0]`；新增 `0x100` 块（全部清零于 reset / soft_reset）：

| 偏移 | 名称 | 位定义 |
|---|---|---|
| 0x100 | NS10G_CTRL | `[1:0]` mode（0=BIST 默认，1=INLINE，2=LOOP，3=DISABLE）；`[2]` dp_en0；`[3]` dp_en1；`[4]` mac_swap0（默认 0）；`[5]` mac_swap1；`[8]` aes_dp0_en；`[9]` aes_dp1_en |
| 0x104 | NS10G_ST | `[1:0]` last_action0；`[3:2]` last_action1；`[8]` aes_dp0_done（粘滞）；`[9]` aes_dp1_done；`[16]` csum_err0 粘滞；`[17]` csum_err1 |
| 0x108 / 0x10C / 0x110 / 0x114 / 0x118 / 0x11C | 口 0 计数 | CNT_RX0 / TX0 / FWD0 / DROP0 / MIR0 / DPI0 |
| 0x120 – 0x13C | 口 1 计数 | CNT_RX1 / TX1 / FWD1 / DROP1 / MIR1 / DPI1（同序） |
| 0x140 | CNT_BADRX0 | RX 坏帧（tuser）丢弃 |
| 0x144 | CNT_BADRX1 | 同上口 1 |
| 0x148 | CNT_OVF0 | RX FIFO 溢出整帧丢弃 |
| 0x14C | CNT_OVF1 | 同上口 1 |
| 0x150 | CNT_CSUM_ERR0 | 口 0 IPv4 头校验和错帧 |
| 0x154 | CNT_CSUM_ERR1 | 同上口 1 |
| 0x158–0x16C | AES_DP0_CT[127:0] | 口 0 AES 数据面密文读回（4 字，RO） |
| 0x170–0x17C | AES_DP1_CT[127:0] | 口 1 同上（4 字，RO） |
| 0x180+ | 预留 | |

约束：`0xC0–0xDC` 原样保留；铜口 CTRL[12]（AES 数据面）语义不变、只作用于铜口实例。

### 5.5 时钟与复位

- **零新增时钟**。新逻辑分布于三个既有域：`logic_clk`（检测/交换）、`tx_clk`/`rx_clkN`（bridge 端口侧）、`axi_clk`（寄存器/统计）。
- 复位：bridge 端口侧用 wrap 内既有 `rst_tx_n/rst_rxN_n`；logic 侧 `rst_n_logic`（含 soft_reset）；统计脉冲 CDC 延用 `axi_por_n`。
- GT 复位链（`rx_dp_reset/slip_hold`）不动；若 G5 定位需干预 `rx_reset_req`，只在 wrap 内加门控参数并记录。

### 5.6 时序约束增补（`constraints/timing_exceptions.xdc`）

```tcl
# 新增：检测域 logic_clk(gtx_clk_u) 与 10G GT 用户时钟互为异步
set_clock_groups -asynchronous \
    -group [get_clocks -quiet gtx_clk_u] \
    -group [get_clocks -quiet tx_clk] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_tx_mac_clk/O]]
set_clock_groups -asynchronous \
    -group [get_clocks -quiet gtx_clk_u] \
    -group [get_clocks -quiet rx_clk] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_rx_mac_clk0/O]] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet -hier *u_rx_mac_clk1/O]]
```

（与现有条目风格一致；具体 get_clocks 写法以实现后 `report_clocks` 实际名为准。）

### 5.7 脚本与工程清单改动

- `scripts/create_project.tcl`：加 `rtl/top/netsec_axis_bridge.sv`、`rtl/top/netsec10g_switch.sv`。
- `scripts/build.tcl`：不变（默认 generic 已含 `NETSEC_ENABLE_SFP10G=1'b1`）。
- `scripts/hw_jtag.tcl`：新增 `nsec_ns10g_dump`、`nsec_l5_test`（§7.2）。
- `tb/simple_tb/`：新增 §7.1 所列 TB；`run_sim.sh` 增补文件列表。

---

## 6. 实施里程碑

> 每个 M 完成即提交一次可回归点；M0/M1 可与 M2 并行推进。

### M0 — 基线冻结 + G5（RX BAD）专项定位
- 任务：
  1. 跑通全部存量仿真（`bash scripts/run_sim.sh`）与板级 BIST（`nsec_sfp10g_check`），冻结基线数字。
  2. G5 假设检验（按序）：
     - H1 BER 监视器误复位：ILA/计数观察 `rx_reset_req`（wrap 内 `slip_hold` 触发频率）；临时屏蔽 `rx_reset_req → rx_dp_reset`（参数化）重测 BAD 占比。
     - H2 门控时钟丢拍：GT 近端 PMA 环回（`nearend_loopback=1`，已有引脚）下 BIST：若近环 BAD=0 而光纤环 BAD 高 → 光模块/信道；若近环也高 → 齿轮箱/BUFGCE 门控。
     - H3 MAC 配置：数字仿真 MAC 层环回（TX AXIS→RX AXIS 直连，见 TB-4）验证 FCS 链路自身无配置错误。
- 涉及文件：`sfp10g_wrap.sv`（仅加观察参数）、`scripts/hw_jtag.tcl`（计数 dump 扩展）、新 TB。
- 验收：BAD/RX 比值从 ~1 降到可解释水平，或明确根因 + 缓解合入（如 ber_mon 门控），结论写入 bringup_log。

### M1 — `sfp10g_wrap` 接口开放（§5.1）
- 任务：AXIS 端口引出、`tx_src` mux、`rx_axis_tkeep` 连接；BIST 默认行为位不变。
- 验收：`tb` 级 smoke（TB-1）；默认图综合通过、WNS≥0；板级 `nsec_sfp10g_check` 数字与基线一致（BIST 不回归）。

### M2 — CDC/位宽桥（§5.2）
- 任务：`netsec_axis_bridge.sv`（基于 `axis_async_fifo_adapter`）+ 坏帧/溢出计数。
- 验收：TB-2 全过（tkeep 边界、跨域、坏帧、整帧丢弃）；资源增量符合预估（§8）。

### M3 — 光口检测交换 + 每口安全通路（§5.3）
- 任务：`netsec10g_switch.sv`；DP_A/DP_B 实例化（含 per-port AES、IPv4 csum 校验）；DPI 特征共享 CDC；`netsec_top.sv` 集成连线。
- 验收：TB-3 全过（INLINE/LOOP/BYPASS 三模式行为与 1G datapath 黄金行为一致）；全量仿真回归 PASS。

### M4 — 寄存器与主机工具（§5.4）
- 任务：`netsec_regs.sv` 译码扩 `[8:0]`、0x100 块；`hw_jtag.tcl` 新过程。
- 验收：寄存器读写 smoke（TB-5）；`nsec_ns10g_dump` 输出格式评审。

### M5 — 仿真收敛
- 任务：TB 全清单（§7.1）Icarus + XSim 双跑；存量回归。
- 验收：0 FAIL；关键用例（DPI 命中→MIRROR、流表迁移→DROP、AES CT 读回、csum 错帧计数）有打印证据。

### M6 — 综合实现与时序
- 任务：默认 `system_top` 全实现；XDC 增补（§5.6）；资源/时序报告归档 `docs/timing_report/`。
- 验收：WNS ≥ 0（目标 ≥ +0.5 ns 余量）；BRAM/LUT 增量 ≤ 预估 ×1.5；ILA 保留（可裁剪 probe 换深度）。

### M7 — 板级 L5 + 文档同步
- 任务：L5a/L5b 上板（§7.2）；L5c 视硬件标注；README/architecture/selftest/bringup 四处文档更新。
- 验收：L5b 判据表全部有实测数字；README 状态表只按实测更新。

---

## 7. 验证计划

### 7.1 仿真 TB 清单（`tb/simple_tb/`，Icarus + XSim）

| TB | 覆盖 | 关键用例 |
|---|---|---|
| TB-1 `tb_sfp10g_axis_if.sv` | wrap 接口开放 | BIST 模式回归（pkt_gen→TX 计数）；EXT 模式注入 64b 帧回读 RX（GT 用行为级直连模型，MAC 数字环回） |
| TB-2 `tb_netsec_axis_bridge.sv` | CDC/位宽桥 | 63/64/65/1518/4600B 帧；尾拍 tkeep 任意值；坏帧丢弃；满 FIFO 整帧丢弃不撕裂；跨时钟相位扫描（125M↔156M 错频） |
| TB-3 `tb_netsec10g_inline.sv` | switch + 2×datapath | INLINE：口 0 注 GET 攻击帧 → 口 1 出 MIRROR/计数；流表状态迁移后 DROP；LOOP 模式口内回环；dp_en=0 旁路对照；AES 数据面 CT 比对 NIST 向量；csum 错帧计数 |
| TB-4 `tb_mac10g_digital_loop.sv` | G5-H3 | `eth_mac_phy_10g` TX AXIS→RX AXIS 同域直连，验证 FCS 插入/校验链路（含 64/65/1518B） |
| TB-5 `tb_ns10g_regs.sv` | 寄存器 0x100 块 | 读写/清零/粘滞位；地址译码不串扰 0x00–0xDC |
| 存量回归 | 全部 | `run_sim.sh` 原清单不变必须 PASS |

### 7.2 板级 L5 判据（写入 `selftest_loopback.md` 新章节）

**L5a — BIST 回归（无需改动）**
`nsec_sfp10g_check`：双口 `block_lock=1`、RX 计数增长，与 L4 基线一致（证明接口开放未破坏原通路）。

**L5b — INLINE 光纤双交自环（核心判据）**

光纤保持 SFP1 TX↔SFP2 RX 双向交叉；配置 INLINE + dp_en=11：

```
nsec_wr 0xDC 0x1        ;# tx_enable
nsec_wr 0x100 0x5       ;# INLINE + 双口检测使能 (mode=01, dp_en=11)
nsec_wr 0x00 0x101      ;# 全局 enable + pkt_gen_start（作注帧源）
```

帧路径：pkt_gen→TX0→SFP1→光纤→SFP2 RX→DP_B 检测→SFP2 TX→光纤→SFP1 RX→DP_A 检测→SFP1 TX→…（每绕一圈两口各计一次）。

| 检查 | 期望 |
|---|---|
| `0x104` last_action0/1 | 非 DISABLE，两方向均在动作 |
| CNT_RX0 / CNT_RX1 | 同步持续增长（INLINE 双向都有流量） |
| CNT_DPI0 / CNT_DPI1 | `>0` 且随绕圈增长（**每口都检到同一特征**） |
| CNT_FWD→(MIR/DROP) 演化 | 与 IPS/流表状态机预期一致（首命中 MIRROR，状态迁移后转 DROP，循环自终止为可接受的通过形态） |
| CNT_BADRXn | 低位/不随 FWD 等比增长（G5 已缓解的证据） |
| CNT_TX0/TX1 | 与对应 RX 对端关系符合拓扑 |

**L5c — 外部 10G 打流（NEED_HW，可选）**
需 10G 光网卡 + 两个 10G SFP+ 模块/DAC：外部仪表 → SFP1 → INLINE → SFP2 → 抓包口，验证受检转发内容正确、DPI 特征触发。无硬件时保留标注，不算失败。

---

## 8. 风险与开放问题

| # | 风险/问题 | 等级 | 缓解 |
|---|---|---|---|
| R1 | G5 RX BAD≈RX 根因未知 | **高**（阻断 L5b 判读） | M0 专项（H1/H2/H3 三假设按序验证）；H1 概率最大（high_ber→反复 RX 复位与 RX≈TX/2 现象吻合）；最坏缓解：门控 ber_mon + 承担可解释的残余误码 |
| R2 | 门控时钟（BUFGCE）上异步 FIFO 的时序收敛 | 中 | 三方 async FIFO 已被上游广泛用于 GT 域；XDC 时钟组按 §5.6 增补；M6 盯 `report_clock_interaction` |
| R3 | 检测吞吐 1G 上限导致 10G 打流丢帧被误读为 bug | 中 | NS10G 计数区分 `CNT_OVF`（容量丢弃）与 `CNT_DROP`（IPS 丢弃）；README/文档显式标注吞吐语义（§1.3 非目标） |
| R4 | 逻辑域到 tx_clk 的回程 bridge 在 INLINE 下双方向相互追赶（正反馈循环） | 低 | L5b 判据按"演化到稳态/自终止"读数；必要时 DISABLE 模式静态注入 |
| R5 | 资源/时序回归（ILA probe 增多、BRAM 增量） | 低 | 预估：+~4–5k LUT（2×datapath）、+~10–12 个 36Kb BRAM（4 bridge FIFO + 2×4096×9 frame FIFO + AES 读回）、MMCM +0；远低于器件容量；ILA 可裁 probe |
| R6 | `axis_async_fifo_adapter` 8↔8 之外的组合在 Vivado 2020.1 综合异常 | 低 | TB-2 前置覆盖；必要时退化为 `axis_async_fifo` + `axis_adapter` 两级级联（同库） |
| R7 | 无外部 10G 打流源 | 中 | L5b 自环形态不依赖外部硬件即可证明"每口都检"；L5c 标注 NEED_HW |

**资源预估汇总**（M6 以实现报告校准）：LUT ~26–28k（<32%），BRAM36 ~20（<16%），MMCM 2，DSP 4+2（datapath AES 用 LUT 实现，无 DSP 增量）。

---

## 9. 仓库与文档更新清单（随 M7 收尾）

| 文件 | 更新 |
|---|---|
| `README.md` | 特性表加"双光口 inline 安全检测"；§7 增吞吐限制说明；状态列仅按 L5b 实测更新 |
| `docs/architecture.md` | §1 框图加入 10G inline 分支；§2 删除/修订"单 PL 网口无法双口穿透"表述；§4 状态表更新 |
| `docs/selftest_loopback.md` | 新增 L5 章节（§7.2 判据表 + 操作脚本） |
| `docs/bringup_log.md` | M0 G5 结论 + L5a/b 实测数字 |
| `docs/verification_plan.md` | TB 清单追加 TB-1…TB-5 |
| 本文档 | 各里程碑标注完成状态，收敛后归档 |

---

## 附录 A — 10G 线速演进路线（不在本计划交付）

若后续要求线速检测（10.3125Gbps 持续吞吐）：

1. `netsec_datapath` 参数化 `WIDTH=64`：parser 改"头部窗口"（前 2 拍 128B 覆盖全部 L2–L4 头，逐字节 lane 状态机，仅头部区降速无碍）；flow table/IPS 接口不变（元数据级）。
2. DPI 多字节步进：4×4B 特征可并行 8 个单字节 AC 实例按 lane 偏移预激后合并（PoC 特征集规模下可行），或改为 multi-stride AC。
3. 检测域迁至 156.25 MHz 新 MMCM（与 GT 用户时钟同频名义值），bridge 退化为纯 async FIFO（无位宽转换）。
4. 预估再 +8–12k LUT，仍在 ZU4EV 容量内。

## 附录 B — 缩略语

DP_A/DP_B：光口 0/1 检测 datapath 实例；BIST：内建自测（`pkt_gen_10g`）；INLINE：双口穿透模式；BAD：`rx_error_bad_fcs|bad_frame` 计数；GTH：GT 高速收发器；AC：Aho-Corasick。
