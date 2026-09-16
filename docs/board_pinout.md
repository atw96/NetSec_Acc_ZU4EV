# AXU4EVB-P / ACU4EV 引脚权威表（NetSec-Accel-ZU4EV）

器件：`xczu4ev-sfvc784-1-i`（无 Vivado BoardPart）。  
信任层级：厂家 factory XDC > 载板用户手册 > 原理图。

**本文件是本仓库唯一引脚权威。**  
[`constraints/axu4ev_template.xdc`](../constraints/axu4ev_template.xdc) 中的 RGMII/SFP **占位符与“2 路 RJ45 均走 RGMII”等旧描述已作废**，请以本表及下列正式 XDC 为准：

- [`constraints/axu4ev_netsec.xdc`](../constraints/axu4ev_netsec.xdc)
- [`constraints/sfp_gth.xdc`](../constraints/sfp_gth.xdc)
- [`constraints/timing_exceptions.xdc`](../constraints/timing_exceptions.xdc)

## 1. PL 侧千兆网口（网口2 / Bank66 / LVCMOS18）

来源：`doc/factory_vivado/board_test.srcs/constrs_1/new/eth.xdc`  
交叉核对：`doc/AXU4EVB-P开发板用户手册.pdf` PAGE37–38（PHY2）。  
PHY：景略 JL2121-N040I，上电默认 PHY 地址 `001`，TX/RX 内部 2 ns 延时均已开启（手册表 3-5-1）。

| Port | PIN | IOSTANDARD | 备注 |
|------|-----|------------|------|
| `rgmii_rxc` | E5 | LVCMOS18 | |
| `rgmii_rx_ctl` | B8 | LVCMOS18 | |
| `rgmii_rd[0]` | A5 | LVCMOS18 | |
| `rgmii_rd[1]` | B5 | LVCMOS18 | |
| `rgmii_rd[2]` | F8 | LVCMOS18 | |
| `rgmii_rd[3]` | C9 | LVCMOS18 | |
| `rgmii_txc` | A7 | LVCMOS18 | |
| `rgmii_tx_ctl` | B9 | LVCMOS18 | |
| `rgmii_td[0]` | E9 | LVCMOS18 | |
| `rgmii_td[1]` | D9 | LVCMOS18 | |
| `rgmii_td[2]` | A9 | LVCMOS18 | |
| `rgmii_td[3]` | A8 | LVCMOS18 | |
| `mdio_mdc` | A6 | LVCMOS18 | |
| `mdio_mdio` | C8 | LVCMOS18 | |
| `phy_reset_n` | D5 | LVCMOS18 | |

## 1b. PS 侧千兆网口（网口1 / GEM3 / MIO Bank2 LVCMOS18）

来源：厂家 `ps_preset.tcl` / `PSU__ENET3__PERIPHERAL__IO`。本工程 **已启用** GEM3，供 L3 双口自环（网线直连网口1↔网口2）。

| 功能 | MIO | 备注 |
|------|-----|------|
| GEM3 RGMII | **MIO 64 .. 75** | TX clk/d/ctl + RX clk/d/ctl |
| GEM3 MDIO | **MIO 76 .. 77** | 独立于 PL MDIO（Bank66） |
| Bank IOSTANDARD | LVCMOS18 | `PSU_BANK_2_IO_STANDARD` |

PL 够不着这些引脚；网口1 只能由 PS GEM3 收发。

## 2. SFP+ 光口（GTH Bank224）

来源：用户手册 PAGE44 + `gt.xdc` + 厂家 `gtwizard_ultrascale_0.xci`（`CHANNEL_ENABLE=X0Y7..X0Y4`，refclk `mgtrefclk1_x0y1`）。

| 功能 | 映射 | 备注 |
|------|------|------|
| SFP1 TX/RX | `224_TX0/RX0` = **GTH X0Y4** | 本工程例化 PCS/PMA |
| SFP2 TX/RX | `224_TX1/RX1` = **GTH X0Y5** | 仅保留约束/端口，不例化 |
| PCIe x2 | `224` Lane2/3 | 勿占用 |
| GT 参考时钟 125 MHz | `mgtrefclk_p/n` = **V6 / V5** | `create_clock -period 8.000` |

### 侧带信号（SOURCE: MANUAL-PAGE44，厂家 XDC 未约束）

Bank45 同组 `edid_scl=F10` 在 `hdmi_in.xdc` 中为 `LVCMOS33`，故侧带按 `LVCMOS33`：

| Port | PIN | IOSTANDARD |
|------|-----|------------|
| `sfp_tx_dis` | D12 | LVCMOS33 |
| `sfp1_los` | B10 | LVCMOS33 |
| `sfp2_los` | C11 | LVCMOS33 |

## 3. 时钟 / 调试 IO

| 功能 | Port | PIN | IOSTANDARD | 来源 |
|------|------|-----|------------|------|
| PL 200 MHz 差分 | `sys_clk_clk_p/n` | AE5 / AF5 | DIFF_SSTL12 | `system.xdc` |
| PL LED1 | `pl_led` | AE15 | LVCMOS33 | `gpio.xdc` |
| PL KEY1 | `pl_key_n` | AE14 | LVCMOS33 | `gpio.xdc` |
| PL UART TX | `pl_uart_tx` | AA11 | LVCMOS33 | `uart.xdc` |
| PL UART RX | `pl_uart_rx` | AA10 | LVCMOS33 | `uart.xdc` |

## 4. 反向冲突检查

上述引脚在厂家全部 `constrs_1/new/*.xdc` 中各自只出现一次；`D12/B10/C11` 未被任何厂家 XDC 占用。勿使用 `AF12/AE12`（HDMI I2C）或 `AH12/AH11`（RS485）充当 GPIO。

## 5. AXI 地址约定

- `M_AXI_HPM0_LPD` → `netsec_regs` @ **0x8005_0000**（64 KB 窗口）
