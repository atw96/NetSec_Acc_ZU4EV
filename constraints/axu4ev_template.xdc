## axu4ev_template.xdc
## AXU4EV (Xilinx Zynq UltraScale+ ZU4EV-2SFVC784) 引脚/时序约束模板
##
## 重要声明：本文件中的引脚编号(LOC)为【占位符/示例格式】，并非从 ALINX 官方参考工程
## 中抓取的真实数据。本沙箱环境无法访问 ALINX 官网/资料（网络策略不含该域名），
## 因此无法验证真实引脚分配。
##
## 使用前必须：
## 1. 从 ALINX 购板附带资料或官网下载 AXU4EV 官方参考工程 (通常包含 *_top.xdc)；
## 2. 将下方 RGMII/SFP/DDR4 相关引脚 LOC 替换为官方 XDC 中的真实值；
## 3. 只保留本工程实际用到的信号，其余按官方工程 IO 标准(IOSTANDARD)配置。
##
## 本文件仅保留结构与时序约束的写法示例，供在官方 XDC 基础上补充数据面时序约束参考。

## ---------------- 时钟约束 ----------------
# 千兆 RGMII 参考时钟 125MHz（示例，需与官方板级时钟树核对）
create_clock -period 8.000 -name rgmii_rxc [get_ports rgmii_rxc]
create_clock -period 8.000 -name sys_clk   [get_ports sys_clk_p]

## ---------------- RGMII 接口（占位符，需替换为官方 LOC） ----------------
# set_property PACKAGE_PIN <FILL_ME> [get_ports {rgmii_txd[0]}]
# set_property IOSTANDARD LVCMOS18   [get_ports {rgmii_txd[0]}]
# ... 其余 rgmii_txd[1:3], rgmii_txc, rgmii_tx_ctl, rgmii_rxd[3:0], rgmii_rxc, rgmii_rx_ctl 同理

## ---------------- SFP 接口（占位符） ----------------
# set_property PACKAGE_PIN <FILL_ME> [get_ports sfp_tx_p]
# set_property PACKAGE_PIN <FILL_ME> [get_ports sfp_rx_p]

## ---------------- 复位/按键/LED（常用于板级调试指示，占位符） ----------------
# set_property PACKAGE_PIN <FILL_ME> [get_ports sys_rst_n]
# set_property IOSTANDARD LVCMOS33   [get_ports sys_rst_n]
# set_property PACKAGE_PIN <FILL_ME> [get_ports {led[0]}]

## ---------------- 时序例外（示例：跨时钟域路径，实际按 CDC 分析结果补充） ----------------
# set_false_path -from [get_clocks rgmii_rxc] -to [get_clocks sys_clk]
# set_max_delay -datapath_only 4.0 -from [get_cells u_cdc_sync/sync_chain_reg[0]*]

## ---------------- 备注 ----------------
## 若使用 Xilinx Ethernet IP (1G/2.5G Ethernet Subsystem 或 Tri-Mode MAC) 二次封装
## MAC/PCS，其自带的 IP 例化模板通常已包含大部分时序约束，本文件只需补充板级引脚。
