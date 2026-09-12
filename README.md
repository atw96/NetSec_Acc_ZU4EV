# NetSec-Accel-ZU4EV
### 网络安全方向 FPGA 加速平台（求职作品集 / 原理验证级工程）

目标硬件：ALINX AXU4EV（Xilinx Zynq UltraScale+ ZU4EV-2SFVC784）

> **诚实声明**：本仓库由 AI 编码助手（Claude）在无 Vivado / 无实体开发板的沙箱环境中
> 自动生成骨架、RTL 代码与文档，并使用开源仿真器 **Icarus Verilog** + **Python
> (pycryptodome/scapy)** 完成了行为级功能仿真验证。综合、时序收敛、上板验证
> **尚未进行**，需要你在本地 Vivado + 实体 AXU4EV 环境中完成，具体步骤见
> `scripts/README_vivado.md`。请勿在简历中声称"已上板验证"或引用未经真实综合
> 得出的资源/时序数字。

---

## 1. JD 关键词映射表

| JD 要求 | 工程模块 | 覆盖方式 | 当前状态 |
|---|---|---|---|
| 防火墙/路由/交换产品FPGA设计 | 整体架构 + 流表匹配 + IPS决策引擎 | 最小可用的"内联安全网关"数据通路 | ✅ 仿真验证 |
| RTL编码、行为仿真 | 全部RTL模块 | SystemVerilog + Icarus Verilog 自检仿真 | ✅ 仿真验证 |
| 时序优化、大规模FPGA开发 | 全工程 | Vivado 综合时序/资源报告 | ❌ 待本地完成 |
| TCP/IP协议栈硬件加速 | tcpip_offload | RFC1071 校验和硬件流水线 | ✅ 仿真验证 |
| 对称加解密算法硬件实现 | crypto/aes | AES-128 完整10轮实现 | ✅ **NIST FIPS-197标准向量验证通过** |
| 非对称加解密硬件实现 | crypto/modexp | 32bit Square-and-Multiply Demo | ✅ 仿真验证(原理级，非商用) |
| DPI深度报文检测硬件加速 | dpi_engine | 并行比较器阵列(Aho-Corasick简化替代) | ✅ 仿真验证，与 Python 参考模型逐字节比对无误报 |
| IPS入侵防御系统硬件加速 | ips_decision | 流表状态+DPI命中 → 决策流水线 | ✅ 仿真验证，8种组合穷举通过 |
| 国产FPGA(紫光同创/安路)认知 | 文档 | 见 `docs/architecture.md` 扩展性讨论 | 📄 文档级 |

## 2. 仿真验证结果一览（本仓库沙箱内真实运行，非编造数据）

运行 `bash scripts/run_sim.sh` 可复现以下全部结果：

| Testbench | 结果 | 关键验证点 |
|---|---|---|
| `tb_packet_parser` | ✅ PASS | 标准以太网+IPv4+TCP报文字段解析全部正确 |
| `tb_checksum` | ✅ PASS (3/3) | 与 Python RFC1071 参考实现逐向量比对一致 |
| `tb_aes128` | ✅ PASS (3/3) | 含 **NIST FIPS-197 标准测试向量**，与 pycryptodome 逐bit一致 |
| `tb_dpi_engine` | ✅ PASS (4/4命中, 0误报) | 与 Python 滑动窗口 + Aho-Corasick 双重参考模型一致 |
| `tb_flow_table` | ✅ PASS (4/4) | 新流插入、命中查找、状态回写、多流隔离均正确 |
| `tb_ips_decision` | ✅ PASS (8/8) | 决策表全部输入组合穷举验证 |
| `tb_modexp` | ✅ PASS (4/4) | 与 Python `pow(base,exp,mod)` 一致 |
| `tb_common_smoke` | ✅ PASS | sync_fifo/cdc_sync/reset_sync 基础读写验证 |

## 3. 目录结构

```
NetSec-Accel-ZU4EV/
├── README.md                  # 本文件
├── docs/                      # 架构、模块规格、验证计划文档
├── rtl/                       # SystemVerilog 源码
├── tb/simple_tb/              # 单元级自检 Testbench（Icarus 已验证通过）
├── tb/uvm_env/                # 报文级 UVM 骨架（需商用仿真器，未在沙箱验证）
├── python_model/              # 黄金参考模型 + 测试激励生成脚本
├── constraints/                # XDC 约束模板（占位符引脚，需替换为官方数据）
├── firmware/                  # PS 端寄存器驱动骨架
├── scripts/                   # 仿真运行脚本 + 本地 Vivado 部署指南
└── bitstream_output/           # 综合产物存放目录（当前为空，待本地生成）
```

## 4. 快速开始（复现本仓库的仿真验证）

```bash
sudo apt-get install -y iverilog        # 若尚未安装
pip install pycryptodome scapy --break-system-packages
bash scripts/run_sim.sh
```

## 5. 本地部署到 AXU4EV（后续步骤）

见 `scripts/README_vivado.md`，包含：Vivado 工程搭建、MAC/PCS IP 集成、
Zynq PS 端配置、综合/实现、上板验证建议顺序、常见坑。

## 6. 设计取舍与诚实说明（面试中建议主动提及）

1. **DPI 引擎**：用并行比较器阵列替代完整 Aho-Corasick 自动机（工程量与验证复杂度取舍），
   Python 参考实现中已包含通用 Aho-Corasick 算法，可作为未来升级 RTL 的状态表生成工具。
2. **RSA 模幂**：32bit Square-and-Multiply 原理级 Demo，非 Montgomery、非商用位宽，
   仅用于证明理解非对称密码硬件实现的核心难点。
3. **流表**：简化 4-way Hash 表，非真实 TCAM，存在理论冲突丢弃风险。
4. **AES-128**：迭代型实现（10周期/分组），非满流水线多分组并行，资源与吞吐为
   典型折中，可作为后续优化方向。
5. **MAC/PCS 与真实以太网物理链路**：依赖 Vivado IP 与实体硬件，软件仿真无法还原，
   需上板验证。

## 7. 与真实防火墙/IPS设备架构的差距

本项目是原理验证级(PoC)工程，与商用防火墙/IPS设备相比，在流表规模（数十条 vs
数十万条并发流）、DPI特征库规模（4条示例 vs 数千条规则）、协议覆盖面（仅IPv4/TCP/UDP
vs 完整协议栈+IPv6+隧道协议）、高可用性(无双机热备/无状态同步)等方面均有显著简化。
这些差距在文档中如实列出，是为了体现工程判断力，而非试图掩盖差距。
