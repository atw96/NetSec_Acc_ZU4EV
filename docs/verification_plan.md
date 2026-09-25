# 验证计划 (Verification Plan)

## 分层验证策略

| 层级 | 工具 | 状态 |
|---|---|---|
| 单元级自检 Testbench | Icarus Verilog (`iverilog`/`vvp`) | ✅ 已在本仓库沙箱环境跑通（见各模块 tb 运行日志，附于 README） |
| Python 黄金模型比对 | Python3 + pycryptodome + scapy | ✅ AES / Checksum / DPI 已建立黄金模型并比对 |
| 报文级 UVM 环境 | QuestaSim / VCS / Xcelium（需商用许可） | ✅ ModelSim SE-64 2020.4 本机编译并跑通 smoke（0 UVM_ERROR），见 `tb/uvm_env/QUESTA_STATUS.md` |
| Vivado 综合/实现 | Vivado 2020.1 | ✅ 2026-09-25 13:17 默认图（含 L5c 注帧）：WNS +0.307 ns，WHS +0.010 ns |
| 板级环回/流量测试 | AXU4EVB-P + Wireshark | L0–L4 见 bringup_log；**L5a PASS**；L5b 部分；**L5c 片上注帧 PASS**（无外部 10G 网卡） |

## UVM 环境扩展说明

本项目沿用作者已有的 `AXI4-Lite UVM 功能验证平台`
(https://github.com/atw96/AXI4-Lite-UVM-Verification-Platform.git) 中的
Driver/Monitor/Scoreboard 分层方法学，将其从"寄存器读写事务级"扩展为
"报文(packet)级"验证：

- **Sequence**：从 `python_model/pcap_gen.py` 生成的 pcap 中读取报文，
  转换为 UVM sequence item 逐字节注入 DUT。
- **Scoreboard**：并行运行 Python 黄金模型（校验和/AES/DPI），
  与 DUT 输出比对，不一致则报 UVM_ERROR。
- **Coverage**：覆盖 (a) 五元组的协议类型分布 (TCP/UDP) (b) DPI 特征命中/未命中
  (c) flow_table 状态迁移的四种决策路径。

由于 Icarus Verilog 默认不包含 UVM 库，单元自检仍用 Icarus；报文级 UVM 已在本机
ModelSim SE-64 2020.4 上编译并跑通 smoke（DPI 使用厂商预编译 `uvm_dpi.dll` + `-nodpiexports`）。
完整 pcap scoreboard / coverage 仍可按下列方法学继续扩展。

## 单元级 Testbench 清单

| Testbench | 覆盖模块 | 检查方式 |
|---|---|---|
| `tb_packet_parser.sv` | 01 | 构造标准以太网+IPv4+TCP报文，检查解析字段是否正确提取 |
| `tb_flow_table.sv` | 02 | 插入多条流，检查查找命中/未命中、老化回收 |
| `tb_checksum.sv` | 03a | 与 Python RFC1071 参考实现逐字节比对 |
| `tb_dpi_engine.sv` | 04 | 注入含特征串的字节流，检查命中向量与预期一致 |
| `tb_aes128.sv` | 05a | NIST FIPS-197 标准测试向量比对 |
| `tb_modexp.sv` | 05b | 小规模模幂运算与 Python `pow(base, exp, mod)` 比对 |
| `tb_ips_decision.sv` | 06 | 穷举决策表全部输入组合 |
| `tb_sfp10g_axis_if.sv` | TB-1 | BIST/EXT TX mux |
| `tb_netsec_axis_bridge.sv` | TB-2 | 64↔8 CDC 桥，好帧通过、坏帧丢弃 |
| `tb_netsec10g_inline.sv` | TB-3 | INLINE 口0 GET → DPI/MIRROR |
| `tb_mac10g_digital_loop.sv` | TB-4 | `eth_mac_phy_10g` 数字 serdes 环，PCS lock |
| `tb_ns10g_regs.sv` | TB-5 | `0x100` 块与 `0x00`–`0xDC` 不串扰 |

2026-09-25 Icarus：TB-1/2/3 PASS；TB-4 PCS lock PASS；TB-5 复位默认值 PASS（AXI 写握手未完全打通，不得当作写通路板级通过）。
