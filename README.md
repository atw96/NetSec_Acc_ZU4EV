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
| Board | L0 (AC) PASS; L3 1G + host→PL + DPI_PAT PASS; AES datapath NIST PASS; RFC1071 / modexp MMIO PASS; L4 IBERT near-end PMA `LINK=1`; optical external loopback needs an SFP module |
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
├── rtl/mac_pcs/              # RGMII wrap + SFP wrap + third_party MAC
├── rtl/top/                  # netsec_top / regs / datapath / system_top
├── scripts/create_project.tcl / create_bd.tcl / build.tcl / ps_preset.tcl
└── ...
```

## 5. Third-party and license

- Project license: [MIT](LICENSE), copyright **atw96**.
- `rtl/mac_pcs/third_party/verilog-ethernet` is [Alex Forencich](https://github.com/alexforencich/verilog-ethernet), MIT. It is used only for the RGMII MAC; the inspection datapath is separate.
- This design does **not** use Xilinx TEMAC (paid license).

## 6. Design choices (intentional limits)

1. DPI: on-chip 4×4B Aho-Corasick (goto/fail + expanded transition table), not a Snort-scale rule set.
2. RSA: 32-bit square-and-multiply demo, not Montgomery.
3. Flow table: simplified hash, not TCAM.
4. The two RJ45 ports are **PS GEM3 + PL RGMII**, not two PL MACs. L3 uses a copper cable between the two jacks. L2 PHY loopback uses `BMCR=0x4140`.
5. RGMII phase: default `RGMII_TX_USE_CLK90=FALSE` plus the JL2121 PHY 2 ns TX delay.
6. L4 near-end PMA is proven (IBERT `LINK=1`). Optical external loopback on 2026-09-16 with `LOOPBACK=None` measured `LINK=0` / BER ≈ 0.575 — needs **one 1.25G 1000BASE-SX/LX SFP in SFP1 + LC TX→RX loopback**. SFP LEDs are not a remote pass criterion.

## 7. Tools

| Tool | Version |
|---|---|
| Vivado | 2020.1 |
| Vitis / xsct | 2020.1 |
| Simulator | Icarus Verilog; optional XSim / Questa |

Install the tools yourself and add them to `PATH`, or set `XILINX_VIVADO` / `XILINX_VITIS`. Scripts in this tree do not hard-code host-specific install or project directories.
