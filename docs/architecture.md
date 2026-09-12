# 系统架构说明 (Architecture)

## 1. 总体框图

```
                         ┌─────────────────────────────────────────┐
                         │              PS (ARM Cortex-A53)          │
                         │  Linux / 裸机控制面：规则下发、日志上送、  │
                         │  统计采集、密钥管理、AXI-Lite寄存器配置    │
                         └───────────────┬───────────────────────────┘
                                          │ AXI4-Lite (配置) / AXI4-Stream (旁路日志)
┌─────────────────────────────────────────┴─────────────────────────────────────────┐
│                                    PL (FPGA数据面)                                   │
│                                                                                      │
│  RGMII/SFP PHY → MAC/PCS → [1] 报文解析引擎(L2/L3/L4 Parser)                          │
│                                   │                                                  │
│                                   ▼                                                  │
│                  [2] 五元组流表匹配 (Flow Table, Hash)                                │
│                                   │                                                  │
│                    ┌──────────────┼──────────────────┐                              │
│                    ▼              ▼                  ▼                              │
│         [3] TCP/IP协议栈    [4] DPI深度报文检测   [5] 加解密引擎                        │
│         硬件加速             (多模式匹配引擎)       AES-128/256 (对称)                  │
│                    │              │           模幂运算Demo (非对称/RSA原理级)           │
│                    └──────────────┼──────────────────┘                              │
│                                   ▼                                                  │
│                  [6] IPS决策与动作引擎                                                │
│                  (放行/丢弃/限速/镜像上送PS日志)                                       │
│                                   │                                                  │
│                                   ▼                                                  │
│                        MAC/PCS → RGMII/SFP PHY (转发出口)                             │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

## 2. 目标硬件平台

- 核心板 (SoM)：ALINX **ACU4EV**，芯片 Xilinx Zynq UltraScale+ **XCZU4EV-1SFVC784I**
  （四核 Cortex-A53 + 双核 Cortex-R5）
- 载板 (Carrier)：ALINX **AXU4EV-P**，提供 2× 千兆以太网(RJ45, 经RGMII转PHY) +
  2× SFP+ 光口 + PCIe + HDMI/DP + M.2 等外设
- **PL 资源（已用官方数据校正，见下方来源说明）**：
  - LUT：87,840　FF：175,680　BRAM(36Kb)：128　UltraRAM：48　DSP48E2：728
  - MMCM：4　GTH 高速收发器：4
  - **重要更正**：原始需求文档中"PL端资源约141K LUT"的数字有误，已用
    ACU4EV 官方器件目录数据（XCZU4EV-1SFVC784I）校正为 87,840 LUT。
- DDR4：核心板自带 4GB(64bit) + 1GB(16bit) DDR4，Vivado 中通过 Zynq PS 硬核 DDR
  控制器接入，通常无需 PL 侧额外 XDC 引脚约束。

### 关于网络接口的重要架构说明（首版文档曾有简化，此处更正）

AXU4EV-P 载板上的 2 路千兆 RJ45 与 2 路 SFP+ **物理层实现方式不同**：
- **2× RJ45 千兆口**：大概率通过 RGMII 总线连接外部千兆 PHY 芯片，PL 侧需要
  Xilinx GMII-to-RGMII / Tri-Mode MAC 等软核 IP + 普通 HP/HD Bank 引脚，
  与本仓库原始设计假设一致。
- **2× SFP+ 光口**：SFP+ 速率(可达10G/25G等)通常直接由 ZU4EV 的 **GTH 高速收发器**
  驱动，走的是 10G/25G Ethernet Subsystem 或自定义 SerDes 逻辑，**不经过 RGMII**，
  也不是普通 Bank 引脚约束（而是走 GTH 专用的 Transceiver 约束方式）。
  若希望本项目支持 SFP+ 口，需要额外集成对应速率的 Xilinx Ethernet IP
  （如 10G/25G Ethernet Subsystem），当前仓库尚未包含该部分，作为后续可扩展方向。

**数据来源说明**：以上型号/资源数据来自 ALINX 官方器件目录聚合站点
(boards.fpgadeveloper.com 的 ACU4EV / AXU4EV-P Carrier 条目)，芯片型号与用户本人
已有开源项目 `EdgeAI-ZU4EV`（`tcl/create_block_design.tcl` 中 `PART =
"xczu4ev-sfvc784-1-i"`，已实际生成过 bitstream）交叉印证一致，可信度较高；
但**具体到 RGMII/SFP+ 信号的引脚编号(LOC)**，本沙箱环境无法访问 ALINX 官网/
原理图 PDF，也未在用户已有开源项目中找到（该项目走 PS 侧 AXI-DMA + PL HLS IP
架构，未使用 PL 侧网络接口，因此其 XDC 里没有 RGMII/SFP 相关约束），
故 `constraints/axu4ev_template.xdc` 中这部分仍为占位符，需要你从随板附带的
官方资料或 ALINX 官网下载真实原理图确认。

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
| [4] DPI 多模式匹配引擎 | ✅ RTL 已实现（并行比较器阵列，简化版 Aho-Corasick 替代方案，见 04 号文档说明取舍） | Icarus Verilog 自检 Testbench |
| [5a] AES-128 加解密 | ✅ RTL 已实现（10 轮流水线） | Icarus Verilog + Python(pycryptodome) 黄金向量比对，**功能仿真通过** |
| [5b] RSA 模幂运算 | ⚠️ 简化 Demo 级（小位宽 square-and-multiply，非 Montgomery），仅体现原理 | 基础功能仿真 |
| [6] IPS 决策引擎 | ✅ RTL 已实现（组合+流水线决策） | Icarus Verilog 自检 Testbench |
| MAC/PCS | 📄 文档级（依赖 Xilinx Ethernet IP 二次封装，需在 Vivado 中集成，无法在软件仿真中还原真实 PHY 行为） | 需上板验证 |
| 报文级 UVM 验证环境 | 📄 骨架级（类结构已给出，需在具备 UVM 库的商用仿真器 QuestaSim/VCS/Xcelium 中编译运行；Icarus 默认不含 UVM） | 未在本沙箱验证 |
| Vivado 综合时序/资源报告 | ❌ 未生成（本环境无 Vivado，需本地 Vivado 完成） | 需用户本地综合 |
| 板级环回/上板验证 | ❌ 未验证（本环境无实体 AXU4EV 板卡） | 需用户本地上板 |

**重要**：本工程可在本地 Vivado + AXU4EV 上继续推进综合、时序收敛与上板验证，
仓库中的 `scripts/README_vivado.md` 给出了具体操作步骤。
