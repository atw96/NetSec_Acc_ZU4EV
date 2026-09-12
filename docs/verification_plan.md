# 验证计划 (Verification Plan)

## 分层验证策略

| 层级 | 工具 | 状态 |
|---|---|---|
| 单元级自检 Testbench | Icarus Verilog (`iverilog`/`vvp`) | ✅ 已在本仓库沙箱环境跑通（见各模块 tb 运行日志，附于 README） |
| Python 黄金模型比对 | Python3 + pycryptodome + scapy | ✅ AES / Checksum / DPI 已建立黄金模型并比对 |
| 报文级 UVM 环境 | QuestaSim / VCS / Xcelium（需商用许可） | 📄 骨架已给出（`tb/uvm_env/`），**未在本仓库沙箱验证**，需用户本地环境编译运行 |
| Vivado 综合仿真 (xsim) | Vivado 本地安装 | ❌ 待用户本地执行 |
| 板级环回/流量测试 | AXU4EV 实板 + Wireshark | ❌ 待用户本地执行 |

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

由于 Icarus Verilog 默认不包含 UVM 库（需要额外的 `uvm-verilog` 移植版本，
兼容性/稳定性在开源社区中仍有已知限制），本仓库中的 UVM 代码为**可读的骨架代码**，
用于面试中展示验证方法学设计能力；建议使用者在具备 QuestaSim/VCS 授权的环境
（如学校/公司实验室）中实际编译运行，作为进一步加分项。

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
