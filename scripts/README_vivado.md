# 本地 Vivado + AXU4EV 部署指南

本仓库在当前沙箱环境中完成了**行为级功能仿真验证**（Icarus Verilog + Python 黄金模型），
但**未进行**真实综合、时序收敛与上板验证——这些步骤需要你在本地安装了 Vivado 且
连接实体 AXU4EV 板卡的环境中完成。以下是建议的操作步骤。

## 1. 环境准备
- 安装 Vivado（建议与 ALINX AXU4EV 官方参考工程推荐的版本一致，通常为 2020.x~2023.x 某个版本，
  请以 ALINX 官方资料为准）。
- 从 ALINX 官网/购板附带资料下载 AXU4EV 官方参考工程与 Board Files。

## 2. 新建 Vivado 工程
1. `Create Project` → 选择 `RTL Project` → Part 选择 `xczu4ev-sfvc784-1-e`（或按官方参考工程核对具体 speed grade）。
2. 将本仓库 `rtl/` 目录下所有 `.sv` 文件加入工程（`Add Sources` → `Add or create design sources`）。
   建议按以下顺序添加以避免包(package)依赖报错：
   ```
   rtl/crypto/aes/aes_sbox_pkg.sv   （package，需最先编译）
   rtl/common/*.sv
   rtl/packet_parser/*.sv
   rtl/flow_table/*.sv
   rtl/tcpip_offload/*.sv
   rtl/dpi_engine/*.sv
   rtl/crypto/aes/aes128_core.sv
   rtl/crypto/modexp/*.sv
   rtl/ips_decision/*.sv
   ```
3. 将 `constraints/axu4ev_template.xdc` 加入工程，**并按文件内注释替换为官方真实引脚**。

## 3. MAC/PCS 集成（本仓库未提供 RTL，需在 Vivado IP Integrator 中完成）
- 在 IP Integrator 中例化 `1G/2.5G Ethernet Subsystem` 或 `Tri-Mode Ethernet MAC` IP，
  配置为 RGMII 接口（若走 SFP 走光口则选择对应 PCS/PMA 配置）。
- 将本仓库 `rtl/packet_parser/u_packet_parser` 的 `s_valid/s_data/s_last` 接到
  Ethernet IP 的 RX AXI-Stream 输出（数据位宽需从 8bit 适配，若 IP 输出为 8bit 数据流可直接对接；
  若为更宽位宽，需额外加一级"宽转窄"适配逻辑，本仓库未提供，需自行实现或使用 Xilinx 自带的
  AXIS Data Width Converter IP）。

## 4. Zynq MPSoC PS 端配置
- 在 IP Integrator 中例化 `Zynq UltraScale+ MPSoC` IP，按 ALINX AXU4EV 官方参考工程的
  预设配置导入（通常提供 `.xml`/`.tcl` 预设文件）。
- 为本工程的寄存器接口预留一个 AXI4-Lite 从设备端口，接入 PS 的 `M_AXI_HPM0_FPD` 或
  `M_AXI_HPM1_FPD`。注意：本仓库核心模块（flow_table/ips_decision等）目前只有
  原生信号接口，**AXI4-Lite Slave 包装层需自行补充**（可参考你已有的
  `AXI4-Lite-UVM-Verification-Platform` 项目经验来设计该包装层，形成简历中的
  "复用已有验证方法学"叙事）。

## 5. 综合、实现、生成比特流
```tcl
# 在 Vivado TCL Console 中
launch_runs synth_1 -jobs 8
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
```
完成后：
- `report_timing_summary` 导出到 `docs/timing_report/timing_summary.rpt`
- `report_utilization` 导出到 `docs/timing_report/utilization.rpt`
- 将两份报告中的关键数字（WNS、LUT/FF/BRAM/DSP 占用率）回填到顶层 `README.md`

## 6. 上板验证建议顺序
1. 先只跑通 MAC 环回（发送已知报文，PC 侧 Wireshark 抓包核对），确认物理链路与时钟正确。
2. 再接入 `u_packet_parser`，通过 ILA (Integrated Logic Analyzer) 抓取解析结果字段，
   与已知输入报文核对。
3. 逐步接入 flow_table / dpi_engine / crypto / ips_decision，每接入一个模块用 ILA 或
   PS 端日志验证一次。
4. 最后用 `python_model/pcap_gen.py` 生成的混合流量（通过外部 PC + tcpreplay 或
   PS 端网口回环）做端到端验证，统计实际丢包/放行/告警计数是否符合预期。

## 常见坑（供参考）
- `aes_sbox_pkg.sv` 是 SystemVerilog package，Vivado 综合对 package + import 语法支持良好，
  但顺序很重要：package 文件必须先于引用它的模块被 Vivado 索引到（一般 Vivado 会自动处理依赖，
  若报 "not declared" 错误，检查 Sources 面板中 package 文件是否被正确识别为 SystemVerilog 类型）。
- `u_flow_table` 内部使用了运行时可变下标访问的大数组（`valid_mem[base_idx+w]` 等），
  在 Icarus 仿真中已验证功能正确，但综合到 BRAM 时建议进一步检查 Vivado 综合报告中
  该表是否被正确映射为 Block RAM（而非展开成大量寄存器），必要时加
  `(* ram_style = "block" *)` 综合属性辅助工具推断。
