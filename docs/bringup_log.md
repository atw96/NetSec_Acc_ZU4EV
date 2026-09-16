# 上板实测记录（AXU4EVB-P）

本文件是“上板验证通过”的唯一证据簿。未填实测值的级别不得在 README 标 ✅。

设备：`xczu4ev-sfvc784-1-i` / Vivado 2020.1 / 默认比特流 `bitstream_output/system_top_rxdly.bit`（与 `system_top.bit` 同内容）。

## 环境

| 项 | 值 |
|----|----|
| 日期 | 2026-09-12 |
| 启动模式 | JTAG |
| 电缆 | Digilent `210512180081`（TCK 1 MHz） |
| 比特流时间戳 | 2026-09-16 21:48 `system_top_rxdly.bit`（AES 数据面 + Aho-Corasick DPI，WNS +0.832 ns） |

## B0 — JTAG 通路 / MMCM / LED

| 检查 | 期望 | 实测 | 通过 |
|------|------|------|------|
| LED 心跳 | 可见闪烁 | 2026-09-15 目视确认一直在闪。`STATUS` bit1 MMCM=1，LED 挂 `axi_clk`，与心跳一致 | 是 |
| STATUS `0x04` | bit1=1 | `0x0000001b`（bit0 ready, bit1 MMCM, bit3/4 SFP LOS） | 是 |
| CTRL `0x00` 回读 | 0x1 | `0x00000001` | 是 |
| `get_hw_axis` | 非空 | `hw_axi_1`（另有 `hw_ila_1/2`） | 是 |

备注：默认 15 MHz TCK 会 `Xicom 50-38`；必须 `PARAM.FREQUENCY 1000000`。CONFIG_STATUS.BIT5_DONE 本器件无此属性。

## L0

| 检查 | 期望 | 实测 | 通过 |
|------|------|------|------|
| CNT_RX | 2 | `2` | 是 |
| CNT_FWD | ≥1 | `1`（另 CNT_TX=`1`） | 是 |
| CNT_DPI | ≥1 | `1`（CNT_MIR=`1`，首次命中走 MIRROR） | 是 |
| soft_reset 后可重复 | 是 | 本轮 `nsec_l0_test` 含 soft_reset 后一次通过 | 是 |

STATUS 回读 `0x0003001b`（`last_action=MIRROR`）。旧 bit 曾卡在 ST_REPLAY（RX=1/TX=0）；FIFO 改为 FWFT 后与 Questa `tb_l0_loopback` 一致。

ILA-A 截图：

## L1

| 检查 | 期望 | 实测 | 通过 |
|------|------|------|------|
| 连续 N 次 start → CNT_RX | +2N | 一次 start 后 `CNT_RX=2` `CNT_FWD=2` `CNT_TX=2` `LOOPBACK=2` | 是 |
| RGMII TX 活动 | 无 | RTL L1 `mac_tx_tvalid=0`；ILA-A (`hw_ila_1`) 已触发，probe3=`probe_tx` | 是 |

备注：L1 与 L0 一样发出 2 帧；`CNT_TX` 计的是 datapath 回放，不是 RGMII pad。MDIO 在旧 bit 上 ID1/ID2/BMSR 均回 `0x00027949`（BMSR 轮询覆盖，待新 bit 锁存修复）。

## MDIO / PHY ID

| 检查 | 期望 | 实测 | 通过 |
|------|------|------|------|
| PHY addr | 1 | 1（与厂家 `C_PHYADDR` 一致） | 是 |
| ID 0x02 / 0x03 | JL2121 | ID1=`0x937c` ID2=`0x937c`（`0x58` done=1 busy=0）；BMSR=`0x7949` 与 ID 已分离，锁存生效 | 部分 |
| STATUS phy_link | 插网线=1 | 默认 `0x0003001b` bit2=0；BMCR 环回后 `0x0003021f` bit2=1 | 部分 |

未插网线；BMCR=`0x4140` 后内部 link 置位证明 MDIO 写通路可用。ID1/ID2 同值，待对照 JL2121 手册 OUI。

## L2

| 检查 | 期望 | 实测 | 通过 |
|------|------|------|------|
| PHY 环回后 CNT_RX | 递增且见额外 MAC RX | **clk90off** `nsec_l2_test`：soft_reset 后一次 start `CNT_RX=4` `CNT_TX/FWD=4` `MIR/DPI=2`（2 帧 pkt_gen + 2 帧 RGMII 回波）。再 start 一次 `CNT_RX=0x1b`（环回自激，进一步证明 pad 通） | 是（仅 clk90off 图） |
| 相位方案 | delay / clk90off / IDELAY tap= | **`RGMII_TX_USE_CLK90=FALSE`** + JL2121 出厂 2 ns TX delay。clk90on 图同脚本只有 `CNT_RX=2`（无额外 MAC RX） | |

比特流：`bitstream_output/system_top_clk90off.bit`（2026-09-13 07:03，WNS +1.002 ns）。默认 `system_top.bit` 仍为 clk90on，L2/L3 请烧 clk90off。L0 在 clk90off 上回归：`RX=2 TX=1 FWD=1 MIR=1 DPI=1`，`STATUS=0x0003021f`（PHY 仍处上次 BMCR 环回）。

ILA-B 截图：未抓；计数已足够证明。

## L3 — 双口自环（PS GEM3 ↔ PL RGMII）

日期：2026-09-14。编排：`scripts/xsct_l3_rxdly_sweep.tcl`。  
比特流：`bitstream_output/system_top_rxdly.bit`（clk90off TX + RXC MMCM 67.5° + IDELAYE3 VAR_LOAD）。  
拓扑：网口1（GEM3）网线直连网口2（PL RGMII）。

根因：厂家 TEMAC 在同一组 Bank66 引脚上用 IDELAYE3 TIME 500 ps + RXC 0°；本设计原先 RX 零延时。单级 COUNT IDELAY 约 0–1.25 ns，90° MMCM 从 2.0 ns 起跳，1.25–2.0 ns 是空档。67.5°（1.5 ns）+ tap 扫过该空档后方向 B 通。

| 检查 | 期望 | 实测 | 通过 |
|------|------|------|------|
| PL 编程 | DONE=1 | xsct `rst -system` + TCK 100 kHz `fpga` | 是 |
| 双 PHY 1G AN | link=1 | `STATUS=0x21F`，PL PHY1 / GEM PHY0 `BMSR=0x796D` | 是 |
| 方向 B GEM→PL | CNT_RX≈20 FWD≈16 DPI≈MIR≈4 | **B_PASS** tap=464（窗口 440–488；FCS=0 区 470–496）。20 帧 `TXOK=20/20`，`RX=56 FWD=44 DPI=MIR=12`（含扫尾余量，比例符合 16/4） | 是 |
| 方向 A PL→GEM | OCTRX>0 且 RXCNT>0 | **A_PASS** `OCTRX=64 RXCNT=1 FCS=0` | 是 |
| 相位方案 | 可复现 | RXC MMCM **67.5°** + IDELAY tap **480**（RTL `DELAY_VALUE` 默认）。`0x5C` 仍可运行时重载 | 是 |

2026-09-13 对照（未闭环）：clk90off/on 方向 A 通、方向 B `CNT_RX=0`；JL2121 `0xD08` 无效。

要点：

- `0x6C` 为 RXC/256 活动计数（不能再探 RXD/CTL：IDATAIN 独占、DATAOUT 不能进 fabric）。
- 卡 CPU0 只用 `RST_FPD_APU |= 1`，禁止写 `0x3D0F`。每次 `targets` 后重新选 PSU。
- 双口禁止 `BMCR=0x4140`。GEM TX 用 `NWCTRL=0x18`。复测：`xsct scripts/xsct_l3_rxdly_sweep.tcl bitstream_output/system_top_rxdly.bit`。

## L3 — PC→PL（网口2，无需 PS）

日期：2026-09-15。拓扑：**PC 千兆网卡（Motorcomm YT6801）↔ PL RJ45**。`LOOPBACK=0`，tap=480，`STATUS=0x21F`（phy_link=1）。  
**未跑** `xsct_l3_rxdly_sweep.tcl`（该脚本假定网口1↔网口2）。

| 检查 | 期望 | 实测 | 通过 |
|------|------|------|------|
| `GET` echo | 0 | `sig echoes = 0`；非本机源 MAC 回显 124 | 是 |
| `CNT_DPI` / `CNT_MIR` | 各 +10 | 均为 `0xA` | 是 |
| `CNT_MAC_RX_BAD_FCS` | 不涨 | `0x2C=0` | 是 |
| `CNT_RX` / `CNT_FWD` | ≈110 / ≈100 | `RX=0xF7` `FWD=0xEF`（PC 协议栈对回显再发 RST，计数偏高；以 DPI/MIR 比例为准） | 是 |

## DPI_PAT 改写

`0x40` 默认 `0x47455420`（`"GET "`）。写成 `0x464F4F20`（`"FOO "`）后再打：

| 步骤 | 期望 | 实测 | 通过 |
|------|------|------|------|
| 10 帧 `GET /` | FWD 涨，DPI/MIR 不涨 | DPI=MIR=`0`；PC `sig echoes=10`（已转发） | 是 |
| 10 帧 `FOO ` | DPI/MIR 各 +10 | DPI=MIR=`0xA`；`sig echoes=0` | 是 |
| 写回 `0x47455420` | PAT0=`GET ` | `DPI_PAT0=0x47455420` | 是 |

## AES / RFC1071 AXI 自检（不进以太网数据面）

日期：2026-09-15。新图 `system_top_rxdly.bit`（22:18，WNS **+0.839 ns**）。AES 按轮密钥扩展；核挂 `axi_clk`，JTAG 触发。

| 检查 | 期望 | 实测 | 通过 |
|------|------|------|------|
| L0 回归 | RX=2 FWD/TX/DPI/MIR≥1 | `RX=2 TX=1 FWD=1 MIR=1 DPI=1` | 是 |
| AES FIPS-197 App.B | CT `69c4e0d8 6a7b0430 d8cdb780 70b4c55a`，STATUS bit5 | `AES CT 0x69c4e0d8 0x6a7b0430 0xd8cdb780 0x70b4c55a` `STATUS=0x0003023f` | 是 |
| checksum `0x1234`+last | `0xEDCB`，STATUS bit6 | `RESULT=0x0000edcb` `STATUS=0x0003027f` | 是 |

寄存器：key `0x30–0x3C`，pt `0x70–0x7C`，ct RO `0x80–0x8C`，CTRL[9] start；csum 数据 `0x90`（[31]=last），结果 `0x94`，CTRL[10] start。

## 模幂 32bit AXI 自检（不进数据面）

日期：2026-09-15 22:59。图 `system_top_rxdly.bit`（含多周期模乘，WNS **+0.485 ns**）。`pow(base,exp,mod)` 黄金值。

| 检查 | 期望 | 实测 | 通过 |
|------|------|------|------|
| L0 回归 | RX=2 FWD/DPI/MIR≥1 | `RX=2 TX=1 FWD=1 MIR=1 DPI=1` | 是 |
| AES / CSUM 回归 | NIST / `0xEDCB` | CT 匹配；`CSUM=0x0000edcb` | 是 |
| `7^560 mod 561` | 1，STATUS bit7 | `RESULT=0x00000001` `STATUS=0x000302fb` | 是 |
| `123^45 mod 2027` | 668 (`0x29C`) | `RESULT=0x0000029c` | 是 |

寄存器：`0x98` base / `0x9C` exp / `0xA0` mod / `0xA4` result；CTRL[11] start。仍是 square-and-multiply 原理级，非 Montgomery RSA。

## AES 进数据面 + Aho-Corasick DPI

日期：2026-09-16 21:52。图 `system_top_rxdly.bit`（21:48，WNS **+0.832 ns**）。CTRL[12] 打开后，FORWARD 帧偏移 42 起 16 字节走 AES-ECB；DPI 为片上重建的 4×4B AC 自动机。

| 检查 | 期望 | 实测 | 通过 |
|------|------|------|------|
| L0（AC，CTRL[12]=0） | RX=2 FWD/TX/DPI/MIR≥1 | `RX=2 TX=1 FWD=1 MIR=1 DPI=1` | 是 |
| AES MMIO / CSUM / MODEXP | 回归 | NIST CT；`0xEDCB`；`1` / `0x29C` | 是 |
| AES 数据面 `0xB0–0xBC` | NIST CT，STATUS bit10 | `69c4e0d8 6a7b0430 d8cdb780 70b4c55a` `STATUS=0x0003061f` | 是 |

L3/PC 打流时保持 CTRL[12]=0。光口外环回见下节，缺模块则 LINK=0。

## L4 — IBERT 近端 PMA（不以 LED 为判据）

日期：2026-09-13 09:06。`bitstream_output/system_top_ibert.bit`（08:52，1.25G / 125 MHz / `MGTREFCLK1_224`）。  
脚本：`scripts/hw_ibert_test.tcl`（TCK 100 kHz 烧图）。

| 检查 | 期望 | 实测 | 通过 |
|------|------|------|------|
| IBERT 可见 | Quad 224 / X0Y4 | `MGT_X0Y4`…`X0Y7` 四个 GT | 是 |
| 近端 PMA + PRBS7 | Near-End PMA / PRBS 7-bit | `LOOPBACK=Near-End PMA`，`TX/RX_PATTERN=PRBS 7-bit`，`PORT.LOOPBACK=2` | 是 |
| LOGIC.LINK | 1 | **`1`** | 是 |
| RX_BER | ≪1e-6 | **`4.03e-08`**（`RX_RECEIVED_BIT_COUNT=2608448280`） | 是 |
| 默认图 `0x60` | 可读 | stub `SFP_ST=0x00000003`（LOS 位；默认图无 GT） | 是（寄存器通路） |
| LED | — | 远程无法目视；L4 **不以 LED 为判据** | — |

权威结论：GTH X0Y4 + V6/V5 125 MHz refclk **物理可用**。自研 PRBS 图见下一节。L4 IBERT 测完请再烧回 `system_top_rxdly.bit`。

## L4 — 自研 `system_top_sfp.bit`（近端 PMA / LED）

日期：2026-09-15。`scripts/build_sfp.tcl`：LED 两拍同步到 50 MHz，去掉 RGMII 假负载，SFP 专用 `constraints/sfp_rgmii_ignore.xdc`。

| 检查 | 期望 | 实测 | 通过 |
|------|------|------|------|
| WNS | ≥0 | **+18.336 ns**（`docs/timing_report/timing_summary_sfp.rpt`；此前 −2.02 ns） | 是 |
| 烧图 | DONE=1，无 jtag_axi | `End of startup HIGH`；`design that has no supported debug core(s)` | 是 |
| LED | 近端 PMA 下恒亮 | 远程无法目视；逻辑为同步后的 `link_status & prbs_match`。保持 8 s 后已烧回 rxdly | — |
| 烧回 | `system_top_rxdly.bit` | DONE=HIGH；随后 `get_hw_axis` 恢复，`AES_PT0` 可读 0（非 `DEADBEEF`） | 是 |

无光模块：只做近端 PMA，不做光口环回。

## L4 — IBERT 光口外环回（LOOPBACK=None）

日期：2026-09-16 21:55。`scripts/hw_ibert_optical.tcl` 烧 `system_top_ibert.bit`，GT X0Y4，`LOOPBACK=None`，PRBS7。笼内**无 SFP**。测完已烧回 `system_top_rxdly.bit`（DONE=HIGH）。

| 检查 | 期望 | 实测 | 通过 |
|------|------|------|------|
| IBERT 可见 | Quad 224 / X0Y4 | `MGT_X0Y4`…`X0Y7` | 是（核可见） |
| LOOPBACK | None（外环） | `None` | 是（配置） |
| LOGIC.LINK | 有模块时应为 1 | **`0`** | **NEED_HW** |
| RX_BER | 有光时应 ≪1e-6 | **`0.575`**（无信号噪声） | NEED_HW |

缺件：**1× 1000BASE-SX/LX 1.25G SFP 插 SFP1 + LC TX→RX 环回跳线**。这不是 RTL 失败。近端 PMA 仍以 2026-09-13 `LINK=1` / BER `4.03e-08` 为准。远程无法目视 SFP LED。

## PS 裸机对照

| 检查 | 期望 | 实测 | 通过 |
|------|------|------|------|
| UART L0 计数 | 与 `nsec_l0_test` 一致 | 未下 Vitis UART；L0 仍以 JTAG `nsec_l0_test` 为准 | — |
| A53 L3 自主启动 | 邮箱 `NS3L`，PL 见 16:4 | 2026-09-15 `xsct_l3_a53_stage.tcl` + `firmware/netsec_l3.elf`，tap=480。`HANG_OR_DONE: NS3L_done`。`CNT_RX=MAC_GOOD=0x8C` `FWD=0x70` `DPI=MIR=0x1C` `FCS=0` `GEM TXCNT=0x8C`（16:4；单 BD WRAP 在 USED 回写前会连发，帧数 >20。20 帧权威判据仍是 PSU `xsct_l3_rxdly_sweep.tcl`） | 是 |

阶段码（`0xFFFEF000`）踩过的挂死点：

- 邮箱全 0：`psu_init` 留下 `RST_FPD_APU` 的 L2/PWRON0，释放 bit0 后 CPU 仍死。A53 启动写 `0x380F` 卡住 CPU0、`0x380E` 放行（禁止写 `0x3D0F`）。
- 停在 `A0`：`Xil_DCacheFlushRange`/`dc civac` 在这颗 SoC 上会卡死；PSU `mrd` 也看不到 DCache 里的邮箱。
- `ESR=0x96000061`（对齐 abort，`XEmacPs_Reset` 的 `stur`）：MMU 关掉后 OCM 变成 Device，不允许非对齐。`firmware/crt0_ocm.S` 开 identity MMU、关 DCache。
- 停在 `306`：`BdRingFromHwTx` 在 USED=0 时死循环。TX 改为与 PSU 相同的 Cadence 单 BD（`TXEN` 关 → 写 BD → `NWCTRL=0x18` → `STARTTX`）。
- `NS3L` 但 `TXCNT=0`：ZynqMP GEM `Version>2`，`XEmacPs_Start` 不写 QBASE。Q0/Q1 都指向自写的 TX BD。

A53 **不要**碰 `0x80050000`（HPM0 可能挂死）；PL 由 xsct 武装。复测：`xsct scripts/xsct_l3_a53_stage.tcl bitstream_output/system_top_rxdly.bit 480`。
