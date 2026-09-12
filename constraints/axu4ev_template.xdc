################################################################
## axu4ev_template.xdc
## NetSec-Accel-ZU4EV — 约束模板
##
## 硬件: ACU4EV 核心板 (XCZU4EV-1SFVC784I) + AXU4EV-P 载板
## Vivado Part: xczu4ev-sfvc784-1-i
##
## 数据来源与可信度说明：
## - 芯片型号/PL资源(LUT/FF/BRAM/DSP等)/Vivado Part 字符串：
##   来自 ALINX 官方器件目录聚合站点 boards.fpgadeveloper.com，并与用户本人已有
##   开源项目 atw96/EdgeAI-ZU4EV 的 tcl/create_block_design.tcl 中的
##   PART="xczu4ev-sfvc784-1-i" 交叉核对一致（该项目已在真实 ACU4EV 板卡上跑通并
##   生成过可用 bitstream，见其仓库 deploy/cifar10_accel.bit）。
## - 下方 PL_LED / PL_UART / 调试GPIO 的具体引脚(LOC)：
##   直接复用自用户本人 EdgeAI-ZU4EV 仓库的 constraints/acu4ev_constraints.xdc，
##   该文件注明已对照 AXU4EVB-P 载板原理图 PAGE03/PAGE15/PAGE20 与
##   ACU4EV 核心板原理图 PAGE04/PAGE19 核实，可信度高。
## - 下方 RGMII / SFP+ 引脚：**仍为占位符，未经验证**。原因：
##   (a) 本沙箱环境网络策略不包含 alinx.com，无法直接下载官方原理图；
##   (b) 用户本人的 EdgeAI-ZU4EV 项目走 PS 侧 AXI-DMA + PL HLS IP 架构，
##       未使用 PL 侧网络接口，其 XDC 中也没有相关约束可供参考；
##   (c) 根据 AXU4EV-P 载板的公开规格，2路SFP+ 大概率通过 ZU4EV 的 GTH 高速收发器
##       直接驱动（而非 RGMII），若走这条路径，约束方式也与普通 Bank 引脚不同
##       （需要 GTH Transceiver 相关的时钟/参考时钟约束），请以官方参考工程为准。
## 使用前请务必用随板资料或 ALINX 官网的真实原理图核实并替换 RGMII/SFP 部分。
################################################################

################################################################
# 1. 时钟约束
################################################################
# 以下 PL 时钟周期沿用 EdgeAI-ZU4EV 项目中经验证可用的配置 (200MHz/100MHz 双域)，
# 供本工程数据面(200MHz 目标)与控制面(100MHz)参考；具体是否复用取决于你的
# Zynq PS IP 配置。
set pl_clk0_pin [lindex [get_pins -quiet -hier *zynq_ultra_ps_e_0/pl_clk0] 0]
if {$pl_clk0_pin ne "" && [llength [get_clocks -quiet pl_clk0]] == 0} {
    create_clock -name pl_clk0 -period 5.000 $pl_clk0_pin
}
set pl_clk1_pin [lindex [get_pins -quiet -hier *zynq_ultra_ps_e_0/pl_clk1] 0]
if {$pl_clk1_pin ne "" && [llength [get_clocks -quiet pl_clk1]] == 0} {
    create_clock -name pl_clk1 -period 10.000 $pl_clk1_pin
}

# 千兆 RGMII 参考时钟（占位符，需按官方工程核对是否需要单独 create_clock）
# create_clock -period 8.000 -name rgmii_rxc [get_ports rgmii_rxc]

################################################################
# 2. 板载调试用 I/O（已验证，来自用户本人 EdgeAI-ZU4EV 项目实测引脚）
################################################################

# PL LED1  (AXU4EVB-P PAGE20/03 -> ACU4EV PAGE19/04 -> FPGA AE15)
set_property PACKAGE_PIN AE15 [get_ports pl_led1]
set_property IOSTANDARD  LVCMOS33 [get_ports pl_led1]

# PL UART (AXU4EVB-P PAGE15/03: TX->AA11, RX->AA10)
set_property PACKAGE_PIN AA11 [get_ports pl_uart_txd]
set_property IOSTANDARD  LVCMOS33 [get_ports pl_uart_txd]
set_property PACKAGE_PIN AA10 [get_ports pl_uart_rxd]
set_property IOSTANDARD  LVCMOS33 [get_ports pl_uart_rxd]

# 调试用 GPIO（复用相机扩展接口 J23，若外接 MIPI 摄像头模组请勿同时使用这些引脚）
set_property PACKAGE_PIN AE10 [get_ports {pl_status_gpio[0]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {pl_status_gpio[0]}]
set_property PACKAGE_PIN AF10 [get_ports {pl_status_gpio[1]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {pl_status_gpio[1]}]
set_property PACKAGE_PIN Y9  [get_ports {pl_status_gpio[2]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {pl_status_gpio[2]}]
set_property PACKAGE_PIN AA8 [get_ports {pl_status_gpio[3]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {pl_status_gpio[3]}]

################################################################
# 3. 数据面网络接口（占位符，未经验证，需用官方原理图替换）
################################################################
## ---- 2x RJ45 千兆口 (推测经 RGMII 转 PHY，走普通 Bank 引脚) ----
# set_property PACKAGE_PIN <FILL_ME_FROM_OFFICIAL_SCHEMATIC> [get_ports {rgmii_txd[0]}]
# set_property IOSTANDARD LVCMOS18   [get_ports {rgmii_txd[0]}]
# ... rgmii_txd[1:3], rgmii_txc, rgmii_tx_ctl, rgmii_rxd[3:0], rgmii_rxc, rgmii_rx_ctl 同理

## ---- 2x SFP+ (推测直接经 GTH 收发器，非 RGMII，约束方式不同) ----
# set_property PACKAGE_PIN <FILL_ME> [get_ports sfp0_tx_p]
# set_property PACKAGE_PIN <FILL_ME> [get_ports sfp0_rx_p]
# create_clock -period <FILL_ME> [get_ports sfp0_refclk_p]  ;# GTH 参考时钟，速率需与实际SFP模块/IP配置匹配

################################################################
# 4. 时序例外
################################################################
if {[llength [get_clocks -quiet pl_clk0]] > 0 && [llength [get_clocks -quiet pl_clk1]] > 0} {
    set_clock_groups -asynchronous -group [get_clocks pl_clk0] -group [get_clocks pl_clk1]
}
if {[llength [get_clocks -quiet pl_clk0]] > 0} {
    set_output_delay -clock [get_clocks pl_clk0] 0 [get_ports pl_led1]
    set_output_delay -clock [get_clocks pl_clk0] 0 [get_ports {pl_status_gpio[*]}]
}

################################################################
# 5. Bitstream 配置（沿用 EdgeAI-ZU4EV 项目中已验证可正常启动的配置，QSPI 启动）
################################################################
set_property CONFIG_VOLTAGE       1.8              [current_design]
set_property CFGBVS               GND              [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH    4    [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE      85.0 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS       TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN       Pullnone [current_design]

puts "INFO: axu4ev_template.xdc loaded. RGMII/SFP+ pins are PLACEHOLDERS -- replace before synthesis."
