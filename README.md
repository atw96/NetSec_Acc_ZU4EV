# NetSec-Accel-ZU4EV

FPGA network-security accelerator for Xilinx Zynq UltraScale+ (`xczu4ev-sfvc784-1-i`) on an ALINX ACU4EV SoM + AXU4EVB-P carrier.

This repository is a **proof-of-concept / portfolio** design: an inline 1G inspection path (parse, flow table, DPI, IPS, AES, checksum, modexp) with on-board measurements recorded in [`docs/bringup_log.md`](docs/bringup_log.md). A feature is **board-verified** only if that log has measured values. Do not treat undocumented stages as proven in hardware.

- JTAG self-test: [`scripts/hw_jtag.tcl`](scripts/hw_jtag.tcl)
- Bring-up runbook: [`docs/selftest_loopback.md`](docs/selftest_loopback.md)
- Pin authority: [`docs/board_pinout.md`](docs/board_pinout.md) (vendor Vivado example + board manual)

Copyright (c) 2026 [atw96](https://github.com/atw96). Licensed under the [MIT License](LICENSE).

---

## Architecture

Default `system_top` is one bitstream: copper 1G inspection plus dual-SFP 10G PCS and a second pair of inspection datapaths. Control is AXI4-Lite at `0x80050000` (jtag_axi).

```
PS (A53) ── AXI4-Lite 0x80050000 ── netsec_regs
                                      │
RJ45 GEM3 ←cable→ JL2121 RGMII MAC ───┴── netsec_datapath (1G, MAC swap, depth 2048)
                                      │
SFP1 GTH X0Y4 ─┐                      │
SFP2 GTH X0Y5 ─┴─ sfp10g_wrap (64-bit AXIS, tx_clk_gt 160.156 MHz)
                 │  BIST: pkt_gen_10g → TX
                 │  INLINE/LOOP: TX from inspect path
                 ▼
              axis_async_fifo 64↔64 (drop bad/oversize) into sfp_tx_clk
                 ▼
              netsec10g_switch64  (BIST / INLINE / LOOP / DISABLE)
                 ▼
              2× netsec_dp64  (64-bit, same clock; port0 AES_LANES=3, port1=2)
                 │  0x100[6] W1C injects on-chip GET frames into DP_A (L5c)
                 ▼
              TX AXIS → wrap → SFP
```

Copper inspect pipeline: parse → flow table → RFC1071 → Aho-Corasick DPI → AES (optional) → IPS. The 10G path uses the same IPS and a 64-bit parser, 4-byte sliding DPI, URAM flow table, and a one-round-per-cycle AES pipeline.

| Plane | Clock / width | Role |
|---|---|---|
| Copper | 8-bit @ 125 MHz | L0–L3 loopback / GEM3 cable |
| 10G MAC/PCS | 64-bit, `tx_clk_gt` 6.244 ns | Dual 10GBASE-R, Bank224, 125 MHz SiT9121 refclk |
| 10G inspect | 64-bit @ `tx_clk_gt` | Line-rate datapath on the TX user clock; bad frames dropped in the RX async FIFO |

Modes at `0x100[1:0]`: `0` BIST (default, PCS counters `0xC0`), `1` INLINE (SFP1↔SFP2 bump-in-the-wire), `2` LOOP, `3` DISABLE. `[4]` GEN_INLINE keeps both `pkt_gen_10g` on the MACs and inspects both RX paths. `[5]` sends the on-chip GET out of MAC tx0 onto the fiber. Frame gap is `0x1F8` (default 1024 cycles; `0` is back-to-back).

Do not constrain `mgtrefclk` as 156.25 MHz. Do not occupy GTH `X0Y6`/`X0Y7` (PCIe).

---

## 1. Feature coverage

| Topic | Module | How it is covered | Status |
|---|---|---|---|
| Firewall / switching datapath | Architecture + flow table + IPS | Single-port loopback inline gateway | Simulation; board: see bringup log |
| RTL + behavioral sim | All RTL | SystemVerilog + Icarus / XSim | Simulation PASS |
| Timing / FPGA implementation | Full design | Vivado 2020.1 reports | 2026-10-15 `system_top`: WNS +0.092 ns / WHS +0.010 ns. WPWS −1.667 ns is the 200 MHz input |
| TCP/IP offload | `tcpip_offload` | RFC 1071 checksum | Simulation + board `0xEDCB` |
| Symmetric crypto | `crypto/aes` | AES-128 | NIST MMIO + **datapath** ciphertext readout |
| Asymmetric crypto | `crypto/modexp` | 32-bit demo | Simulation + board `pow()` readout |
| DPI | `dpi_engine` | Aho-Corasick 4×4B on copper; 64-bit 16×4B sliding match on 10G | Simulation + L0 GET hit; L5c on-chip GET |
| 10G line-rate inspect | `netsec_dp64` | 64-bit parse, URAM flow table, pipelined AES, IPS on `tx_clk_gt` | Simulation. Board 2026-10-15: L5a/L5b/L5b-DPI/L5c PASS; L5d slope recorded |
| IPS | `ips_decision` | Decision pipeline | Simulation |
| Domestic-FPGA notes | Docs only | [`docs/architecture.md`](docs/architecture.md) | Documentation |

## 2. Implementation results (Vivado 2020.1)

| Item | Value |
|---|---|
| Part | `xczu4ev-sfvc784-1-i` |
| CLB LUTs | **76411 / 87840 (86.99%)** |
| CLB Registers | **106497 / 175680 (60.62%)** |
| Block RAM Tile | **84 / 128 (65.63%)** |
| URAM | **32 / 48 (66.67%)** |
| DSP / MMCM | **4** DSP / 2 MMCM |
| WNS / TNS | **+0.092 ns / 0** setup; **WHS +0.010 ns / 0** hold (2026-10-15). `tx_clk_gt` WNS +0.092 ns at 6.244 ns; copper `gtx_clk_u` WNS +0.217 ns. WPWS −1.667 ns is on `sys_clk_clk_p` |
| Bitstream | `bitstream_output/system_top.bit` (6680244 bytes; not stored in git) |
| Board | L0–L4 同前。2026-10-15：**L5a PASS**（3 s，BAD 增量 0，交叉口 RX 与对端 TX 差 269 / 51）；**L5b PASS**（2 s，DP RX0 +307843、RX1 +310855，BADRX 增量 0）；**L5b-DPI PASS**（`0x134`/`0x130` 各 +1）；**L5c PASS**（DPI0/MIR0 各 +1）；**L5d** gap=0 的 1 s 窗口 MAC TX0 +14454536，GEN_INLINE DP RX0 +14586237 |
| Register access | JTAG-to-AXI (`scripts/hw_jtag.tcl`) + PS OCM bare-metal (`firmware/netsec_l3.elf`, A53 mailbox `NS3L`) |

Build (Vivado 2020.1 on `PATH`, or `%XILINX_VIVADO%`):

```bat
vivado -mode batch -source scripts/create_project.tcl
vivado -mode batch -source scripts/build.tcl
```

Board (Vivado Tcl console):

```tcl
source scripts/hw_jtag.tcl
nsec_connect
nsec_program
nsec_l0_test
nsec_aes_nist
nsec_aes_dp_test
nsec_csum_test
nsec_modexp_test
nsec_sfp10g_check
nsec_l5_test
nsec_l5b_dpi
nsec_l5c_test
nsec_l5d_test
```

## 3. Simulation

```bash
bash scripts/run_sim.sh
```

| Testbench | Result |
|---|---|
| `tb_packet_parser` / `tb_checksum` / `tb_aes128` / `tb_dpi_engine` / `tb_flow_table` / `tb_ips_decision` / `tb_modexp` / `tb_common_smoke` | PASS |
| `tb_sfp10g_axis_if` / `tb_netsec10g_inline` / `tb_dpi_match64` / `tb_dp64` | PASS |
| `tb_mac10g_digital_loop` (TB-4) | PASS (PCS lock; send/got criterion relaxed) |
| `tb_ns10g_regs` (TB-5) | PASS (`0x100`, `0x180`–`0x1AC`, flow/hit counters) |

XSim (Vivado): `vivado -mode batch -source scripts/run_xsim.tcl` (uses `XILINX_VIVADO` if set).

## 4. Layout

```
NetSec-Accel-ZU4EV/
├── docs/                     # architecture, bringup_log, selftest, pinout
├── constraints/              # axu4ev_netsec / sfp_gth / timing_exceptions
├── rtl/mac_pcs/              # RGMII + sfp10g_wrap + third_party verilog-ethernet
├── rtl/top/                  # netsec_top, copper datapath, netsec_dp64, switch64, regs
├── scripts/                  # create_project / build / hw_jtag / hw_l5_bringup
└── tb/simple_tb/             # unit + TB-1…5
```

## 5. Third-party and license

- Project license: [MIT](LICENSE), copyright **atw96**.
- `rtl/mac_pcs/third_party/verilog-ethernet` is [Alex Forencich](https://github.com/alexforencich/verilog-ethernet), MIT. Used for the 1G RGMII MAC and the default-image 10G `eth_mac_phy_10g`. The inspection datapath is separate.
- This design does **not** use Xilinx TEMAC (paid license).

## 6. Design choices (intentional limits)

1. DPI: on-chip 4×4B Aho-Corasick (goto/fail + expanded transition table), not a Snort-scale rule set.
2. RSA: 32-bit square-and-multiply demo, not Montgomery.
3. Flow table: simplified hash, not TCAM.
4. The two RJ45 ports are **PS GEM3 + PL RGMII**, not two PL MACs. L3 uses a copper cable between the two jacks. L2 PHY loopback uses `BMCR=0x4140`.
5. RGMII phase: default `RGMII_TX_USE_CLK90=FALSE` plus the JL2121 PHY 2 ns TX delay.
6. L4 near-end PMA is proven (IBERT `LINK=1` @ 1.25G). Dual-SFP **10G line-rate inspection** lives in the default `system_top` bitstream (`NETSEC_ENABLE_SFP10G=1`): `sfp10g_wrap` → 64-bit async FIFO → `netsec10g_switch64` → 2× `netsec_dp64` on `sfp_tx_clk`. Default mode is BIST. SFP cage LEDs are not a pass criterion.

## 7. Optical SFP bring-up (10G)

Bank 224 MGT refclk is a **SiT9121 125.000 MHz** on `V6/V5` (factory `gt.xdc` period 8.000 ns). **Do not** constrain `mgtrefclk` as 156.25 MHz. 156.25 MHz is the 10GBASE-R user clock (`10.3125 Gbps / 66`) produced by QPLL0 after lock.

| Port | GTH | Sideband |
|---|---|---|
| SFP1 | `X0Y4` | `sfp1_los=B10` |
| SFP2 | `X0Y5` | `sfp2_los=C11` |
| Shared | `MGTREFCLK1_224` = V6/V5 | `sfp_tx_dis=D12` must be **0** or the lasers stay off |
| Do not use | `X0Y6` / `X0Y7` (PCIe) | |

Fiber: SFP1 TX↔SFP2 RX and SFP2 TX↔SFP1 RX. Default `build.tcl` / `system_top` instantiates dual 10G GT+MAC and the 64-bit inspect path.

Vivado 2020.1 IBERT and GT Wizard reject **10.3125G + exactly 125 MHz** (ratio 82.5). IBERT therefore runs **10.0 Gbps / 125 MHz**. The Ethernet Wizard declares refclk 125.7621951 MHz (nearest legal value); the crystal is still 125.000 MHz, so both ports run at the same ~10.25G serial rate.

```bat
vivado -mode batch -source scripts/create_ibert.tcl
vivado -mode batch -source scripts/build_ibert.tcl
vivado -mode batch -source scripts/hw_ibert_optical_10g.tcl
```

Default image (same bitstream as copper L0–L3):

```tcl
source scripts/hw_jtag.tcl
nsec_connect
nsec_program
nsec_sfp10g_check
nsec_l5_test
nsec_l5b_dpi
nsec_l5c_test
nsec_l5d_test
```

`system_top` / `netsec_regs` 10G map (`0x80050000`):

| Offset | Name | Notes |
|---|---|---|
| `0xC0` | SFP10G_ST | `[1]` tx_done `[2]` rx_done `[3]` los1 `[4]` los2 `[8]` block_lock0 `[9]` block_lock1 |
| `0xC4` / `0xC8` / `0xCC` | CNT_TX0 / RX0 / BAD0 | SFP1 / X0Y4 |
| `0xD0` / `0xD4` / `0xD8` | CNT_TX1 / RX1 / BAD1 | SFP2 / X0Y5 |
| `0xDC` | SFP10G_CTRL | `[0]` tx_enable (default 1; not bit 16 of `0x00`) |
| `0x100` | NS10G_CTRL | `[1:0]` mode (0=BIST, 1=INLINE, 2=LOOP, 3=DISABLE); `[3:2]` dp_en; `[4]` GEN_INLINE; `[5]` inj out MAC tx0; `[6]` inj W1C（片上 GET，L5c）；`[9:8]` aes_en |
| `0x104` | NS10G_ST | `[7:6]` sticky fold of the extra AES lanes (port1, port0) |
| `0x180`–`0x1AC` | DPI_PAT4..15 | 4-byte patterns; pat4 default `504F5354` (`POST`) |
| `0x1B0` / `0x1B4` | FLOW0 / FLOW1 | flow-insert counts |
| `0x1B8`–`0x1F4` | PHIT | `{port1[15:0], port0[15:0]}` per pattern |
| `0x1F8` | NS10G_GAP | `[15:0]` `pkt_gen_10g` 帧间空拍，默认 1024，写 0 为背靠背 |

**2026-09-24 board result** (isolated `hw_sfp10g.tcl` **PASS**, image since removed): WNS **+1.963 ns**; STATUS=`0x2F07` (both `block_lock=1`, LOS=0); both RX counters grew over 3 s. BAD stayed close to RX.

**2026-10-15 image**（WNS **+0.092 ns**，`system_top.bit` 6680244 B，`End of startup HIGH`）：`0xC0=0x00000F07`。L5a 相邻采样 3 s：TX0 +461922 / RX1 +461653，TX1 +461611 / RX0 +461662，BAD0/BAD1 增量 0。L5b `0x100=0x1C` 的 2 s：DP RX0 +307843、RX1 +310855，BADRX 增量 0。L5b-DPI：`0x134` 与 `0x130` 各从 0 到 1。L5c：DPI0 与 MIR0 各 +1，CTRL 回到 `0x5`。L5d gap=`0` 的 1 s：MAC TX0 +14454536，随后 GEN_INLINE DP RX0 +14586237、FWD0 +14578512。复测：`vivado -mode batch -source scripts/hw_l5_bringup.tcl`。Numbers: [`docs/bringup_log.md`](docs/bringup_log.md).

RX 64-bit AXIS enters `netsec_dp64` through a same-width async FIFO (`0x100` mode: BIST/INLINE/LOOP). Bad frames are dropped before inspection. Default mode is BIST so `nsec_sfp10g_check` still reads `0xC0`.

## 8. Tools

| Tool | Version |
|---|---|
| Vivado | 2020.1 |
| Vitis / xsct | 2020.1 |
| Simulator | Icarus Verilog; optional XSim / Questa |

Install the tools yourself and add them to `PATH`, or set `XILINX_VIVADO` / `XILINX_VITIS`. Scripts in this tree do not hard-code host-specific install or project directories.
