# PS 端控制程序（OCM 裸机）

基址：**0x8005_0000**。自测步骤见 [`docs/selftest_loopback.md`](../docs/selftest_loopback.md)。

**不依赖 DDR。** 当前 BD 是最小 PS（无厂家 DDR 时序），程序必须链到 OCM `0xFFFC0000`。

## 构建

1. `scripts/build.tcl` 成功后会写出 `firmware/netsec.xsa`（若本步失败，在实现后的 Vivado 里手动 `write_hw_platform -fixed -include_bit`）。
2. Vitis 2020.1：New Application Project，硬件平台选 `netsec.xsa`，应用选 Hello World 再换成 `netsec_test.c`。
3. 用 [`lscript.ld`](lscript.ld) 替换默认链接脚本（去掉 DDR 段）。
4. UART0 115200 8N1（MIO42/43）。板载 USB-UART 看打印。
5. Run / Debug 经 JTAG 下载到 A53。不要依赖 FSBL+SD 除非已换成厂家完整 PS。

L3 双口（GEM3 ↔ PL）：`netsec_l3_gem3.c`，xsct 批处理：

```bat
xsct scripts/build_ps_app.tcl
powershell -File scripts/run_l3_dualport.ps1
```

邮箱 `0xFFFEF000`：magic `NS3L`、PL 计数、GEM 回显数。JTAG 烧图用 TCK 100 kHz，xsct `dow` 用 1 MHz。

与 JTAG 路径对照：同一套 L0/L1 序列（CTRL 写 `0x3` 再 `0x101`），`hw_jtag.tcl` 的 `nsec_l0_test` 读数应与串口一致。

期望 UART（与 2026-09-12 JTAG L0 实测对齐）：

```
L0 STATUS=0003001b RX=2 TX=1 FWD=1 DROP=0 MIR=1 DPI=1
```

## 寄存器

| 偏移 | 寄存器 | 说明 |
|---|---|---|
| 0x00 | CTRL | `[0]` enable；`[1]` soft_reset；`[8]` pkt_gen_start |
| 0x04 | STATUS | `[0]` ready；`[1]` mmcm；`[2]` phy_link |
| 0x08 | LOOPBACK | 0=L3 1=L0 2=L1 3=L2 4=L4 |
| 0x10..0x24 | 计数器 | RX/TX/FWD/DROP/MIR/DPI |
| 0x40..0x4C | DPI_PAT | 4×32b 特征 |
| 0x50/54/58 | MDIO | phy/reg/we/go、wdata、rdata+busy+done |
| 0x5C | RGMII_DLY | `[8:0]` tap `[16]` load |
| 0x60 | SFP_STATUS | 只读；默认图为 LOS stub，GT 图为 `status_vector` |
