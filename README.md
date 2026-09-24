# NetSec-Accel-ZU4EV

FPGA network-security accelerator for Xilinx Zynq UltraScale+ (`xczu4ev-sfvc784-1-i`) on an ALINX ACU4EV SoM + AXU4EVB-P carrier.

This repository is a **proof-of-concept / portfolio** design: an inline 1G inspection path (parse, flow table, DPI, IPS, AES, checksum, modexp) with on-board measurements recorded in [`docs/bringup_log.md`](docs/bringup_log.md). A feature is **board-verified** only if that log has measured values. Do not treat undocumented stages as proven in hardware.

- JTAG self-test: [`scripts/hw_jtag.tcl`](scripts/hw_jtag.tcl)
- Bring-up runbook: [`docs/selftest_loopback.md`](docs/selftest_loopback.md)
- Pin authority: [`docs/board_pinout.md`](docs/board_pinout.md) (vendor Vivado example + board manual)

Copyright (c) 2026 [atw96](https://github.com/atw96). Licensed under the [MIT License](LICENSE).

---

## 1. Feature coverage

| Topic | Module | How it is covered | Status |
|---|---|---|---|
| Firewall / switching datapath | Architecture + flow table + IPS | Single-port loopback inline gateway | Simulation; board: see bringup log |
| RTL + behavioral sim | All RTL | SystemVerilog + Icarus / XSim | Simulation PASS |
| Timing / FPGA implementation | Full design | Vivado 2020.1 reports | Default bitstream WNS +0.832 ns; SFP image +18.3 ns |
| TCP/IP offload | `tcpip_offload` | RFC 1071 checksum | Simulation + board `0xEDCB` |
| Symmetric crypto | `crypto/aes` | AES-128 | NIST MMIO + **datapath** ciphertext readout |
| Asymmetric crypto | `crypto/modexp` | 32-bit demo | Simulation + board `pow()` readout |
| DPI | `dpi_engine` | Aho-Corasick 4×4B | Simulation + L0 GET hit on board |
| IPS | `ips_decision` | Decision pipeline | Simulation |
| Domestic-FPGA notes | Docs only | [`docs/architecture.md`](docs/architecture.md) | Documentation |

## 2. Implementation results (Vivado 2020.1)

| Item | Value |
|---|---|
| Part | `xczu4ev-sfvc784-1-i` |
| CLB LUTs | **22195 / 87840 (25.27%)** (ILA + jtag_axi + AES datapath + AC transition tables) |
| CLB Registers | **33818 / 175680 (19.25%)** |
| Block RAM Tile | **7.5 / 128 (5.86%)** |
| DSP / MMCM | **4** DSP / 2 MMCM |
| WNS / TNS | **+0.832 ns** (default image = IDELAY + AES datapath + Aho-Corasick, 2026-09-16) |
| Bitstream | `bitstream_output/system_top_rxdly.bit` (same contents as `system_top.bit`; not stored in git) |
| Board | L0 (AC) PASS; L3 1G + host→PL + DPI_PAT PASS; AES datapath NIST PASS; RFC1071 / modexp MMIO PASS; L4 IBERT near-end PMA `LINK=1` @ 1.25G; dual-SFP **10G** fiber loopback `system_top_sfp10g` 2026-09-24 lock+RX PASS (separate image, not in the copper datapath) |
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
```

## 3. Simulation

```bash
bash scripts/run_sim.sh
```

| Testbench | Result |
|---|---|
| `tb_packet_parser` / `tb_checksum` / `tb_aes128` / `tb_dpi_engine` / `tb_flow_table` / `tb_ips_decision` / `tb_modexp` / `tb_common_smoke` | PASS |

XSim (Vivado): `vivado -mode batch -source scripts/run_xsim.tcl` (uses `XILINX_VIVADO` if set).

## 4. Layout

```
NetSec-Accel-ZU4EV/
├── docs/board_pinout.md
├── docs/selftest_loopback.md
├── constraints/              # axu4ev_netsec / sfp_gth / timing_exceptions
├── rtl/mac_pcs/              # RGMII wrap + SFP / 10G wrap + third_party MAC
├── rtl/top/                  # netsec_top / regs / datapath / system_top / system_top_sfp10g
├── scripts/create_project.tcl / create_bd.tcl / build.tcl / build_sfp10g.tcl
└── ...
```

## 5. Third-party and license

- Project license: [MIT](LICENSE), copyright **atw96**.
- `rtl/mac_pcs/third_party/verilog-ethernet` is [Alex Forencich](https://github.com/alexforencich/verilog-ethernet), MIT. Used for the 1G RGMII MAC and the optional 10G `eth_mac_phy_10g` image. The inspection datapath is separate.
- This design does **not** use Xilinx TEMAC (paid license).

## 6. Design choices (intentional limits)

1. DPI: on-chip 4×4B Aho-Corasick (goto/fail + expanded transition table), not a Snort-scale rule set.
2. RSA: 32-bit square-and-multiply demo, not Montgomery.
3. Flow table: simplified hash, not TCAM.
4. The two RJ45 ports are **PS GEM3 + PL RGMII**, not two PL MACs. L3 uses a copper cable between the two jacks. L2 PHY loopback uses `BMCR=0x4140`.
5. RGMII phase: default `RGMII_TX_USE_CLK90=FALSE` plus the JL2121 PHY 2 ns TX delay.
6. L4 near-end PMA is proven (IBERT `LINK=1` @ 1.25G). Dual-SFP **10G** fiber loopback is a **separate bitstream** (see below). SFP cage LEDs are not a pass criterion.

## 7. Optical SFP bring-up (10G)

Bank 224 MGT refclk is a **SiT9121 125.000 MHz** on `V6/V5` (factory `gt.xdc` period 8.000 ns). **Do not** constrain `mgtrefclk` as 156.25 MHz. 156.25 MHz is the 10GBASE-R user clock (`10.3125 Gbps / 66`) produced by QPLL0 after lock.

| Port | GTH | Sideband |
|---|---|---|
| SFP1 | `X0Y4` | `sfp1_los=B10` |
| SFP2 | `X0Y5` | `sfp2_los=C11` |
| Shared | `MGTREFCLK1_224` = V6/V5 | `sfp_tx_dis=D12` must be **0** or the lasers stay off |
| Do not use | `X0Y6` / `X0Y7` (PCIe) | |

Fiber: SFP1 TX↔SFP2 RX and SFP2 TX↔SFP1 RX. Default copper image `system_top_rxdly.bit` is left unchanged; optical tests restore it when finished.

Vivado 2020.1 IBERT and GT Wizard reject **10.3125G + exactly 125 MHz** (ratio 82.5). IBERT therefore runs **10.0 Gbps / 125 MHz**. The Ethernet Wizard declares refclk 125.7621951 MHz (nearest legal value); the crystal is still 125.000 MHz, so both ports run at the same ~10.25G serial rate.

```bat
vivado -mode batch -source scripts/create_ibert.tcl
vivado -mode batch -source scripts/build_ibert.tcl
vivado -mode batch -source scripts/hw_ibert_optical_10g.tcl
```

```bat
vivado -mode batch -source scripts/create_gt_10g.tcl
vivado -mode batch -source scripts/build_sfp10g.tcl
vivado -mode batch -source scripts/hw_sfp10g.tcl
```

`system_top_sfp10g` JTAG-AXI map (`0x80050000`):

| Offset | Name | Notes |
|---|---|---|
| `0x00` | CTRL | `[0]` tx_enable (default 1), `[1]` soft_reset |
| `0x04` | STATUS | `[0]` por `[1]` tx_done `[2]` rx_done `[3]` los1 `[4]` los2 `[8]` block_lock0 `[9]` block_lock1 |
| `0x10` / `0x14` / `0x18` | CNT_TX0 / RX0 / BAD0 | SFP1 / X0Y4 |
| `0x20` / `0x24` / `0x28` | CNT_TX1 / RX1 / BAD1 | SFP2 / X0Y5 |

**2026-09-24 board result** (`hw_sfp10g.tcl` **PASS**): WNS **+1.963 ns**; STATUS=`0x2F07` (both `block_lock=1`, LOS=0); both RX counters grew over 3 s (peer frames on the fiber). BAD stayed close to RX (FCS still dirty). The 10.0G IBERT image used that day did not drive `sfp_tx_dis`, so `LINK=0` / BER≈0.5; `create_ibert.tcl` now patches D12=0. Numbers: [`docs/bringup_log.md`](docs/bringup_log.md). Procedure: [`docs/selftest_loopback.md`](docs/selftest_loopback.md).

This 10G path is **not** wired into `netsec_datapath` / DPI.

## 8. Tools

| Tool | Version |
|---|---|
| Vivado | 2020.1 |
| Vitis / xsct | 2020.1 |
| Simulator | Icarus Verilog; optional XSim / Questa |

Install the tools yourself and add them to `PATH`, or set `XILINX_VIVADO` / `XILINX_VITIS`. Scripts in this tree do not hard-code host-specific install or project directories.
