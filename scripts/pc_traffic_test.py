#!/usr/bin/env python3
"""L3 board test: send normal + DPI-hit frames, sniff replies.

Requires: pip install scapy
Run as admin/root, NIC in promiscuous mode.

  python scripts/pc_traffic_test.py --iface Ethernet --normal 100 --attack 10
"""
from __future__ import annotations

import argparse
import time
from threading import Thread

from scapy.all import Ether, IP, TCP, Raw, sendp, sniff
from scapy.config import conf as scapy_conf


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--iface", help="PC NIC connected to PL RJ45 (board port 2)")
    ap.add_argument("--list", action="store_true", help="print scapy interface names and exit")
    ap.add_argument("--normal", type=int, default=100)
    ap.add_argument("--attack", type=int, default=10)
    ap.add_argument("--timeout", type=float, default=3.0)
    ap.add_argument("--sig", default="GET /", help="attack payload (default 'GET /')")
    ap.add_argument("--inter", type=float, default=0.01, help="gap between frames in seconds")
    args = ap.parse_args()

    if args.list:
        print(scapy_conf.ifaces)
        return
    if not args.iface:
        ap.error("need --iface (or --list). Cable must be PL RJ45 port 2, not PS GEM3.")

    dst = "ff:ff:ff:ff:ff:ff"
    src = "02:00:00:00:00:99"
    pkts = []
    for i in range(args.normal):
        pkts.append(
            Ether(src=src, dst=dst)
            / IP(src="192.168.1.2", dst="192.168.1.100")
            / TCP(sport=12345 + i, dport=80)
            / Raw(load=b"ping")
        )
    for i in range(args.attack):
        pkts.append(
            Ether(src=src, dst=dst)
            / IP(src="10.0.0.5", dst="192.168.1.100")
            / TCP(sport=23456 + i, dport=80)
            / Raw(load=args.sig.encode("ascii"))
        )

    sniff_time = args.timeout + (args.normal + args.attack) * args.inter + 1.0
    captured: list = []

    def _sniff() -> None:
        nonlocal captured
        captured = sniff(iface=args.iface, timeout=sniff_time, store=True)

    th = Thread(target=_sniff, daemon=True)
    th.start()
    time.sleep(0.4)
    print(f"Sending {len(pkts)} frames on {args.iface} sig={args.sig!r} inter={args.inter} ...")
    sendp(pkts, iface=args.iface, inter=args.inter, verbose=False)
    th.join()

    replies = [p for p in captured if Ether in p and p[Ether].src != src]
    print(f"sniffed {len(captured)}  replies_not_from_us={len(replies)}")
    sig_b = args.sig.encode("ascii")[:4]
    print(f"Expect: ~{args.normal} MAC-swapped echoes; 0 frames with {args.sig!r} payload.")
    print("Board: CNT_DPI and CNT_MIR each +attack (first hit is MIRROR, not DROP).")
    sig_echo = 0
    for p in replies:
        raw = bytes(p[Raw].load) if Raw in p else b""
        if sig_b in raw:
            sig_echo += 1
    print(f"sig echoes (should be 0): {sig_echo}")


if __name__ == "__main__":
    main()
