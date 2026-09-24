# 分级环回自测 runbook（AXU4EVB-P）

寄存器基址：`0x8005_0000`。PL 自持：`axi_clk` = 板上 200 MHz / 2，**不依赖 PS 启动**。  
访问通路：Vivado Hardware Manager + `jtag_axi`（`scripts/hw_jtag.tcl`）。PS 裸机见 `firmware/`。

上电默认 `LOOPBACK=1`（L0），`CTRL.enable=1`。LED 挂在 `axi_clk`，MMCM 未锁也会闪。

## 0. 连板与下载

板拨 **JTAG 启动**（或先用厂家 SD 把 Linux 拉起再下 PL）。

```tcl
# Vivado Tcl Console
cd <repo>/NetSec-Accel-ZU4EV
source scripts/hw_jtag.tcl
nsec_connect
nsec_program                          ;# 默认 bitstream_output/system_top_rxdly.bit
nsec_rd 0x04
nsec_rd 0x00
```

**B0 出口**

| 检查 | 期望 |
|------|------|
| LED | ~1.5 Hz 闪烁 |
| `nsec_rd 0x04` bit1 | 1（MMCM lock） |
| `nsec_rd 0x00` | `0x00000001` |

失败：确认 200 MHz 晶振 / `pl_key_n` 未按住；JTAG 启动模式；`get_hw_axis` 非空。

## 寄存器速查

| Offset | 名称 | 说明 |
|--------|------|------|
| 0x00 | CTRL | `[0]` enable；`[1]` soft_reset；`[8]` pkt_gen；`[9]` AES MMIO；`[10]` csum；`[11]` modexp；`[12]` AES 数据面 |
| 0x04 | STATUS | `[0]` ready；`[1]` mmcm；`[2]` phy_link；`[5]` aes_done；`[6]` csum_valid；`[7]` modexp_done |
| 0x08 | LOOPBACK | `0` L3；`1` L0；`2` L1；`3` L2；`4` L4 |
| 0x10–0x24 | CNT_* | RX / TX / FWD / DROP / MIR / DPI |
| 0x40–0x4C | DPI_PAT | 主机可改特征（默认 `GET ` / `cmd.` / `SELE` / NOP） |
| 0x50 | MDIO_CTRL | `[4:0]` phy `[12:8]` reg `[16]` we `[17]` go |
| 0x54 | MDIO_WDATA | 写数据 |
| 0x58 | MDIO_RDATA | `[15:0]` `[16]` busy `[17]` done |
| 0x5C | RGMII_DLY | `[8:0]` IDELAY tap `[16]` load |

## L0 — 纯 PL 内部环回（首板必做）

```tcl
nsec_l0_test
```

等价手动：

```tcl
nsec_wr 0x00 0x2          ;# soft_reset
nsec_wr 0x08 0x1          ;# L0
nsec_wr 0x00 0x101        ;# enable + pkt_gen_start
after 20
nsec_dump
```

**通过**：`CNT_RX=2`，`CNT_FWD≥1`，`CNT_TX≥1`，`CNT_DPI≥1`。GET 帧首次命中是 MIRROR（`CNT_MIR+1`，不是 DROP）。再 `nsec_wr 0x00 0x3` 后重跑，计数从 0 再变成同样结果。

失败：ILA-A（`ila_logic`）抓 `probe0`（dp_s）是否在 start 后出现两帧；`STATUS[1]`。

## L1 — MAC AXIS 内环回（不经 RGMII）

```tcl
nsec_l1_test
```

**通过**：`CNT_RX` 随每次 `0x101` 增加（每拍 2 帧）；ILA-B / `rgmii_tx_ctl` 无活动。

## L2 — PHY 环回（RGMII 时序）

1. 确认 MDIO：`nsec_mdio_read 2` 与 `nsec_mdio_read 3` 读 PHY ID（JL2121，地址 `001`）。
2. 查手册置环回位（典型 BMCR `0x00` bit14）。例（以手册为准）：

```tcl
nsec_mdio_write 0 0x4000
```

3. `nsec_wr 0x08 0x3`；`nsec_wr 0x00 0x101`。拔网线仍应 `CNT_RX` 增加。

相位工具箱（按序）：

1. MDIO 关 PHY 内部 TX 2 ns delay（手册私有页；没有就跳过）。
2. L3 烧 `bitstream_output/system_top_rxdly.bit`（RXC MMCM 67.5° + IDELAY tap 480）。
3. IDELAYE3 `DATAOUT` 只能进 IDDRE1（进 fabric 会 RTSTAT）。`0x6C` 数 RXC，不探 RXD/CTL。

## L3 — 双口自环（PS GEM3 ↔ PL RGMII）

一根网线连接 **网口1（PS）与网口2（PL）**。不要用 `nsec_l2_test` 的 `BMCR=0x4140`（会关自协商，两端同角色）。

`RGMII_TX_USE_CLK90` 只影响 PL TX。GEM→PL 靠 FPGA 侧 RXC 67.5° MMCM + IDELAY tap（JL2121 无 RTL8211F delay 页）。

```bat
xsct scripts/xsct_l3_rxdly_sweep.tcl bitstream_output/system_top_rxdly.bit
```

流程（PSU，不 halt A53）：`rst -system` → TCK 100 kHz `fpga` → TCK 1 MHz → `psu_init`（跳过 DDR）→ `RST_FPD_APU |= 1` 卡 CPU0 → 双 PHY 1G AN → 写 `0x5C=tap|0x10000` → 先方向 B（GEM TX，`NWCTRL=0x18`）→ 再方向 A。

判据：

| 方向 | 看什么 | 分流 |
|------|--------|------|
| A PL→GEM | GEM `OCTRX` / `RXCNT` / `FCS` | 全 0 = 无信号；`RXCNT>0` = 已通 |
| B GEM→PL | PL `0x6C` / `0x2C` / `0x28` / `CNT_RX` | `0x6C=0` 无 RXC；FCS 涨 = 相位；`0x28` 与 `CNT_RX` 涨 = 窗口 |

**通过（2026-09-14）**：`system_top_rxdly.bit`，RXC **67.5°** + IDELAY tap **480**（窗口 440–488）。方向 B `B_PASS`，方向 A `A_PASS OCTRX=64 RXCNT=1`。`PASS: 1`。

Vivado 与 xsct 不能同时占同一 JTAG。卡 CPU0 只用 `rst |= 1`，禁止写 `0x3D0F`。

PHY 预置：只广告 1000M full + 重启 AN（脚本内 `phy_an`）。

A53 自主启动（OCM ELF，邮箱 `0xFFFEF000`）：

```bat
scripts\link_ps_app.bat
xsct scripts/xsct_l3_a53_stage.tcl bitstream_output/system_top_rxdly.bit 480
```

入口是 `firmware/crt0_ocm.S`（MMU identity、DCache 关）。`RST_FPD_APU` 用 `0x380F`/`0x380E`，不要写 `0x3D0F`。看到 `NS3L_done` 且 PL `DPI:MIR:FWD` 为 16:4 即自主启动成功。20 帧精确计数仍看上面的 PSU 脚本。

---

## L3 — PC 接 PL 口（备选，无需 PS）

编排：`vivado -mode batch -source scripts/hw_pc_l3.tcl -tclargs arm`（`LOOPBACK=0`，tap 480，1G AN），再

```bat
python scripts/pc_traffic_test.py --iface "<千兆网卡名>" --normal 100 --attack 10 --inter 0.02
```

然后 `-tclargs dump`。DPI 对照：`-tclargs dpi_foo` → `--attack 10 --sig "GET /"`（应转发）→ `--sig "FOO "`（应 DPI）→ `-tclargs dpi_get`。

**通过（2026-09-15）**：PC `GET echoes=0`；板 `CNT_DPI=CNT_MIR=10`，`0x2C FCS=0`。改 `0x40=FOO` 后 GET 转发（echo=10、DPI=0），FOO 命中 DPI/MIR=+10。PC 协议栈 RST 会使 `CNT_RX/FWD` 高于 110/100，以 DPI 比例为准。

已知限制：存储转发一次只处理一帧，背靠背高速流会丢帧。

## AES / RFC1071 MMIO 自检

AES MMIO、校验和、模幂**默认不进**以太网数据面。烧 `system_top_rxdly.bit` 后：

```tcl
nsec_l0_test
nsec_aes_nist
nsec_csum_test
```

或一次跑完：`vivado -mode batch -source scripts/hw_pc_l3.tcl -tclargs board_b`。

| 寄存器 | 含义 |
|--------|------|
| `0x30–0x3C` | AES key（w0=LSB） |
| `0x70–0x7C` | plaintext |
| `0x80–0x8C` | ciphertext 只读 |
| CTRL[9] | AES start（W1C） |
| STATUS[5] | aes_done 粘滞 |
| `0x90` | checksum 字；写时 `data_valid`，`[31]=last` |
| `0x94` | checksum 结果 |
| CTRL[10] | checksum start（清累加器） |
| STATUS[6] | checksum_valid 粘滞 |
| `0x98/9C/A0/A4` | modexp base / exp / mod / result |
| CTRL[11] | modexp start（W1C） |
| STATUS[7] | modexp_done 粘滞 |

NIST：key=`00010203…0f` pt=`001122…ff` → ct=`69c4e0d8 6a7b0430 d8cdb780 70b4c55a`。  
单字 `0x1234`+last → `0xEDCB`。  
模幂：`nsec_modexp_test` → `7^560 mod 561 = 1`，`123^45 mod 2027 = 668`。

**通过（2026-09-15）**：L0 回归 + AES/校验和/模幂数字见 bringup_log。  
**通过（2026-09-16）**：Aho-Corasick L0 `DPI=1`；`nsec_aes_dp_test` 数据面 NIST CT 匹配。

## AES 进数据面（CTRL[12]，默认关）

L0 frame0 偏移 42 起 16 字节为 FIPS-197 明文。`nsec_aes_dp_test` 写 NIST 密钥、置 CTRL[12]、打 L0，回读 `0xB0–0xBC` 应为 `69c4e0d8 6a7b0430 d8cdb780 70b4c55a`。L3/PC 打流时保持 CTRL[12]=0，避免改写 TCP 头。

DPI 为片上重建的 4×4B Aho-Corasick（`DPI_PAT0..3`）。

## L4 — SFP GT 可观测（不以 LED 为判据）

权威路径是 **IBERT**（与自研 PRBS 解耦）：

```bat
vivado -mode batch -source scripts/create_ibert.tcl
vivado -mode batch -source scripts/build_ibert.tcl
vivado -mode batch -source scripts/hw_ibert_test.tcl
```

`hw_ibert_test.tcl` 烧 `bitstream_output/system_top_ibert.bit`，近端 PMA + PRBS 7-bit，打印 `LOGIC.LINK` / `RX_BER`。

默认 `system_top_rxdly.bit` 不含 GT；`nsec_l4_test` 读 `0x60` SFP_STATUS（stub 时为 LOS 位）。含 GT 的图：`scripts/build_sfp.tcl` → `system_top_sfp.bit`（2026-09-15 WNS **+18.336 ns**）。`scripts/hw_l4_sfp.tcl` 烧 SFP 图后保持数秒并**自动烧回 rxdly**。

无光模块时不要用 PCS 光口环回当主路径。

### L4 — 10G 双光口光纤互环（当前权威路径）

板上 Bank224 晶振是 **SiT9121 125.000 MHz**（V6/V5）。**不要**把 `mgtrefclk` 约束成 156.25 MHz。156.25 MHz 是 10GBASE-R 的 GT 用户时钟（`10.3125 Gbps / 66`），由 QPLL0 从 125 MHz 合成。

光纤：SFP1 TX↔SFP2 RX、SFP2 TX↔SFP1 RX。

**阶段 A — IBERT 10.0G PHY**

Vivado 2020.1 的 IBERT **和** GT Wizard 都不能把 **10.3125G 与正好 125 MHz** 配在一起（10.3125/125=82.5）。阶段 A 用 **10.0 Gbps + 125 MHz**（整数倍）证明模块+光纤。阶段 B 的 Wizard 声明 refclk=125.7621951（最近合法值），板上晶振仍是 125.000 MHz，互环两端同频，串行约 10.25G；PCS 仍按 10GBASE-R 64b/66b。XDC 的 `create_clock` 保持 8.000 ns。

```bat
vivado -mode batch -source scripts/create_ibert.tcl
vivado -mode batch -source scripts/build_ibert.tcl
vivado -mode batch -source scripts/hw_ibert_optical_10g.tcl
```

`hw_ibert_optical_10g.tcl` 烧 `system_top_ibert.bit`，X0Y4/X0Y5，`LOOPBACK=None`，PRBS31。通过：两路 `LOGIC.LINK=1`。测完烧回 rxdly。

**阶段 B — 10GBASE-R 以太网互环**

```bat
vivado -mode batch -source scripts/build_sfp10g.tcl
vivado -mode batch -source scripts/hw_sfp10g.tcl
```

`system_top_sfp10g.bit` 独立 top，不改默认铜口图。jtag_axi @ `0x80050000`：

| Offset | 名称 | 说明 |
|--------|------|------|
| 0x00 | CTRL | `[0]` tx_enable（默认 1）`[1]` soft_reset |
| 0x04 | STATUS | `[0]` por `[1]` gt_tx_done `[2]` gt_rx_done `[3]` sfp1_los `[4]` sfp2_los `[8]` block_lock0 `[9]` block_lock1 |
| 0x10 / 0x14 / 0x18 | CNT_TX0 / RX0 / BAD0 | 口 0（SFP1 / X0Y4） |
| 0x20 / 0x24 / 0x28 | CNT_TX1 / RX1 / BAD1 | 口 1（SFP2 / X0Y5） |

通过：两口 `block_lock=1`，`CNT_RX` 随对端 `CNT_TX` 增长。不以 LED 为判据。

旧 1.25G 单口 IBERT 外环（`hw_ibert_optical.tcl`）保留作历史；10G 单速率模块在 1.25G 上经常不锁。

**2026-09-24 实测（10G 业务图）**：`hw_sfp10g.tcl` **PASS**。STATUS=`0x2F07`（双口 lock、LOS=0），3 s 内两口 RX 从约 `0xBF1DE` 涨到 `0xF78D6`。IBERT 10.0G 图当时未拉 `sfp_tx_dis`，LINK=0。数字见 `bringup_log.md`。

**2026-09-16 实测（1.25G、无模块）**：`LOOPBACK=None`，`LOGIC.LINK=0`，`RX_BER=0.575`。结论当时是 NEED_HW。

## 推荐顺序

`B0 读 STATUS → L0 → L1 → MDIO ID → L2 → L3 → L4`。  
实测数字写入 [`bringup_log.md`](bringup_log.md) 后，才允许在 README 将该级标为通过。
