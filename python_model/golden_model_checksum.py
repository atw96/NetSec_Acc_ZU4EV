"""
RFC1071 反码和校验和 —— 黄金参考模型
用于与 rtl/tcpip_offload/checksum_rfc1071.sv 的仿真结果比对。
"""
from typing import List


def rfc1071_checksum(data: bytes) -> int:
    """标准 RFC1071 校验和实现（软件参考版本）。"""
    if len(data) % 2 == 1:
        data = data + b"\x00"  # 奇数长度补零对齐，与硬件约定一致
    total = 0
    for i in range(0, len(data), 2):
        word = (data[i] << 8) | data[i + 1]
        total += word
        while total > 0xFFFF:
            total = (total & 0xFFFF) + 1
    return (~total) & 0xFFFF


def words_from_bytes(data: bytes) -> List[int]:
    """将字节流拆分为 16bit 字列表，供 RTL 测试激励生成使用。"""
    if len(data) % 2 == 1:
        data = data + b"\x00"
    return [(data[i] << 8) | data[i + 1] for i in range(0, len(data), 2)]


if __name__ == "__main__":
    # 与 tb_checksum.sv 中硬编码的测试向量保持一致
    test_vectors = [
        bytes.fromhex("4500003C1C4640004006B1E6C0A80001C0A800C7"),  # 典型 IPv4 头(20B, 奇数长度示例)
        bytes.fromhex("0001020304050607"),
        b"HELLO, NETSEC-ACCEL-ZU4EV!",
    ]
    for i, tv in enumerate(test_vectors):
        cksum = rfc1071_checksum(tv)
        words = words_from_bytes(tv)
        print(f"[vec{i}] len={len(tv)}B words={['%04X' % w for w in words]} checksum=0x{cksum:04X}")
