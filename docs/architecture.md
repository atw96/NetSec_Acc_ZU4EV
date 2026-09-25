# 系统架构说明 (Architecture)

## 1. 总体框图

```
                         ┌─────────────────────────────────────────┐
                         │              PS (ARM Cortex-A53)          │
                         │  控制面：JTAG-AXI / 裸机邮箱（规则、统计）   │
                         └───────────────┬───────────────────────────┘
                                          │ AXI4-Lite @ 0x80050000
┌─────────────────────────────────────────┴─────────────────────────────────────────┐
│                                    PL (FPGA数据面)                                   │
│                                                                                      │
│  铜口 1G：  GEM3(RJ45) ↔ 网线 ↔ JL2121 RGMII MAC → netsec_datapath (swap=1, 2048)     │
│                                                                                      │
│  光口 10G： SFP1 X0Y4 ─┐                                                             │
│             SFP2 X0Y5 ─┴→ sfp10g_wrap (64b ~156 MHz)                                 │
│                           → netsec_axis_bridge (64↔8 CDC, DROP_BAD/OVF)               │
│                           → netsec10g_switch (BIST / INLINE / LOOP)                   │
│                           → 2× netsec_datapath (swap=0, 4096) @ 8-bit 125 MHz         │
│                           0x100[6] 可片上注入 GET（L5c，不经 MAC/G5）                   │
│                                                                                      │
│  共用检测核：[1] Parser [2] Flow table [3] RFC1071 [4] AC-DPI [5] AES/modexp [6] IPS │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

## 2. 目标硬件平台

- 核心板 (SoM)：ALINX **ACU4EV**，芯片 Xilinx Zynq UltraScale+ **XCZU4EV-1SFVC784I**
  （四核 Cortex-A53 + 双核 Cortex-R5）
- 载板 (Carrier)：ALINX **AXU4EVB-P**，提供 2× 千兆以太网(RJ45) +
  2× SFP+ 光口 + PCIe + HDMI/DP + M.2 等外设  
  （引脚权威见 [`board_pinout.md`](board_pinout.md)，来源 `../doc/factory_vivado`）
- **PL 资源（已用官方数据校正，见下方来源说明）**：
  - LUT：87,840　FF：175,680　BRAM(36Kb)：128　UltraRAM：48　DSP48E2：728
  - MMCM：4　GTH 高速收发器：4
  - **重要更正**：原始需求文档中"PL端资源约141K LUT"的数字有误，已用
    ACU4EV 官方器件目录数据（XCZU4EV-1SFVC784I）校正为 87,840 LUT。
- DDR4：核心板自带 4GB(64bit) + 1GB(16bit) DDR4，Vivado 中通过 Zynq PS 硬核 DDR
  控制器接入，通常无需 PL 侧额外 XDC 引脚约束。

### 网络接口（已用 factory XDC + 用户手册核实）

- **网口1（RJ45）**：挂 **PS GEM3**（`MIO64..77`），本工程已启用，供 L3 双口自环（网线直连网口1↔网口2）。
- **网口2（RJ45）**：挂 **PL Bank66 RGMII** ↔ JL2121 PHY（全部引脚见 `eth.xdc` / `board_pinout.md`）。  
  本工程使用开源 MIT `verilog-ethernet` 1G RGMII MAC（**不使用需付费 license 的 TEMAC**）。
- **2× SFP+**：GTH Bank224 Lane0/1（SFP1=`X0Y4`，SFP2=`X0Y5`），参考时钟 **125 MHz** `V6/V5`（SiT9121，不是 156.25 MHz 晶振）。  
  默认 `system_top` 例化双口 10G GT+MAC（`sfp10g_wrap`）以及 `netsec10g_switch`（2×datapath，`0x100` INLINE/LOOP/BIST）。吞吐为 8-bit@125 MHz 降速检。独立 `system_top_sfp10g.bit` 仍可对照 BIST。见 `docs/selftest_loopback.md`。
- **铜口**：单 PL RGMII，数据面仍以环回转发（FORWARD / DROP / MIRROR）验证。**光口 INLINE**：SFP1↔SFP2 光纤交叉可做双口穿透检测（线速帧受 G5 FCS 影响；片上注帧 L5c 已过）。

旧模板 `constraints/axu4ev_template.xdc` **已废弃**（含占位符与错误描述）。

## 3. 数据通路接口约定

所有数据面模块之间统一采用简化的 **AXI4-Stream 风格握手**（`valid/ready/data/last/user`），
其中 `user` 字段用于携带旁路元数据（如流表命中索引、DPI 命中标志），
避免每个模块都重新解析报文头部。

| 信号 | 位宽 | 说明 |
|---|---|---|
| `s_valid/s_ready` | 1 | 上游握手 |
| `s_data` | 8/32/64 (按模块) | 报文字节流或字段 |
| `s_last` | 1 | 报文帧尾标记 |
| `s_user` | 按模块定义 | 元数据旁路总线 |

## 4. 本仓库当前实现状态（诚实说明）

本项目定位为**求职作品集 / 原理验证级(PoC)工程**，而非商用级产品。以下状态表如实标注
"已实现并通过仿真验证" vs "文档级/骨架级"，避免夸大：

| 模块 | 状态 | 验证方式 |
|---|---|---|
| [1] 报文解析引擎 | ✅ RTL 已实现 | Icarus Verilog 自检 Testbench |
| [2] 五元组流表 | ✅ RTL 已实现（Hash+冲突链，简化版） | Icarus Verilog 自检 Testbench |
| [3] TCP/IP 校验和加速 | ✅ RTL 已实现（RFC1071 增量校验和） | Icarus Verilog 自检 Testbench + Python 黄金模型比对 |
| [4] DPI 多模式匹配引擎 | ✅ RTL 已实现（4×4B 可编程 Aho-Corasick，片上重建 goto/fail/trans） | XSim + 上板 L0 GET 命中 |
| [5a] AES-128 加解密 | ✅ RTL 已实现（迭代 10 轮；MMIO + 数据面 CTRL[12]，默认关） | NIST 仿真 + JTAG MMIO/`0xB0` 数据面回读 |
| [5b] RSA 模幂运算 | ⚠️ 32bit Demo（square-and-multiply，非 Montgomery）；AXI 自检已上板 | 仿真 + JTAG `pow()` 回读 |
| [6] IPS 决策引擎 | ✅ RTL 已实现（组合+流水线决策） | Icarus Verilog 自检 Testbench |
| MAC/PCS | ✅ 开源 MIT `verilog-ethernet` RGMII MAC；默认图另含双口 10G `sfp10g_wrap` + `netsec10g_switch`（`NETSEC_ENABLE_SFP10G=1`）。1G PRBS 与 10G 互斥 | 综合/比特流已出；铜口时序见 L2；10G PCS 计数 `0xC0`，检测通路 `0x100` |
| 报文级 UVM 验证环境 | ✅ QuestaSim 2020.4 本机 `vlog` + smoke `run -all`（0 ERROR） | `tb/uvm_env/QUESTA_STATUS.md` |
| Vivado 综合时序/资源报告 | ✅ 已生成 | LUT 60515 (68.89%) / FF 88763 / BRAM 15.5 / DSP 4；**WNS +0.307 ns** / **WHS +0.010 ns**（2026-09-25 含 L5c 注帧）；`docs/timing_report/` |
| 板级环回/上板验证 | ✅ 以 `docs/bringup_log.md` 实测栏为准 | L0(AC)/L3/PC/DPI/AES-DP/CSUM/MODEXP/IBERT 近端已填；10G 光纤互环 lock+RX **PASS**。**L5a PASS**；L5b 部分（G5）；**L5c 片上 GET 注帧 PASS**（RX0=2/DPI=1） |

### 资源映射核对（`flow_table` / 帧缓存）

当前 `HASH_BITS=4`（64 项）下综合结果：

- `u_frame_fifo/mem_reg` → **Block RAM**（RAMB18）
- `u_flow_table/key_mem` → **分布式 LUTRAM**（RAM64M8×60），未进 BRAM
- `age_mem` / `state_mem` → 溶解为寄存器（表深过小）

若需强制流表进 BRAM，增大 `HASH_BITS`（例如 ≥8）并保留 `(* ram_style="block" *)`；当前小表优先 LUTRAM 更省 BRAM、综合更快。

**重要**：上板功能验证仍按 `docs/selftest_loopback.md` 的 L0→L3 分级推进；请勿在简历中声称“已上板验证”直至对应级别实测通过。
仓库中的 `scripts/README_vivado.md` 给出了构建步骤。
