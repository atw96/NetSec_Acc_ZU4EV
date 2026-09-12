"""
使用 scapy 生成"正常流量 + 攻击特征流量"混合 pcap，供以下用途：
1. 未来扩展报文级 UVM 环境时作为 Sequence 的输入源；
2. 板级测试时用 tcpreplay 等工具从 PS 侧或外部 PC 回放，验证 PL 数据面处理逻辑。

用法: python3 pcap_gen.py --out mixed_traffic.pcap --normal 20 --attack 5
"""
import argparse
import random
from scapy.all import IP, TCP, UDP, Raw, wrpcap, Ether


ATTACK_PAYLOADS = [
    b"GET /admin/config.php?cmd=cat /etc/passwd HTTP/1.1\r\n",
    b"cmd.exe /c whoami",
    b"' SELECT * FROM users WHERE '1'='1",
    b"\x90" * 16 + b"\xcc\xcc\xcc\xcc",  # NOP sled + int3 占位（非真实shellcode）
]

NORMAL_PAYLOADS = [
    b"GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n",
    b"hello world, this is normal traffic",
    b"PING",
]


def gen_normal_packet():
    src_ip = f"192.168.1.{random.randint(2,254)}"
    dst_ip = f"192.168.1.{random.randint(2,254)}"
    sport = random.randint(1024, 65535)
    dport = random.choice([80, 443, 22])
    payload = random.choice(NORMAL_PAYLOADS)
    return Ether() / IP(src=src_ip, dst=dst_ip) / TCP(sport=sport, dport=dport) / Raw(load=payload)


def gen_attack_packet():
    src_ip = f"10.0.0.{random.randint(2,254)}"
    dst_ip = "192.168.1.100"
    sport = random.randint(1024, 65535)
    dport = 80
    payload = random.choice(ATTACK_PAYLOADS)
    return Ether() / IP(src=src_ip, dst=dst_ip) / TCP(sport=sport, dport=dport) / Raw(load=payload)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="mixed_traffic.pcap")
    ap.add_argument("--normal", type=int, default=20)
    ap.add_argument("--attack", type=int, default=5)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    random.seed(args.seed)
    pkts = [gen_normal_packet() for _ in range(args.normal)]
    pkts += [gen_attack_packet() for _ in range(args.attack)]
    random.shuffle(pkts)

    wrpcap(args.out, pkts)
    print(f"Wrote {len(pkts)} packets ({args.normal} normal + {args.attack} attack) to {args.out}")


if __name__ == "__main__":
    main()
