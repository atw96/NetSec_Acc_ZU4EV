"""
AES-128 黄金参考模型（基于 pycryptodome），用于与
rtl/crypto/aes/aes128_core.sv 的仿真结果做逐 bit 比对。
测试向量取自 NIST FIPS-197 Appendix B / C.1，并附加若干随机向量。
"""
import os
from Crypto.Cipher import AES


def aes128_ecb_encrypt_block(key: bytes, plaintext: bytes) -> bytes:
    assert len(key) == 16 and len(plaintext) == 16
    cipher = AES.new(key, AES.MODE_ECB)
    return cipher.encrypt(plaintext)


TEST_VECTORS = [
    # (name, key_hex, plaintext_hex) —— 前两组为 NIST 标准向量
    ("fips197_appendix_b", "000102030405060708090a0b0c0d0e0f", "00112233445566778899aabbccddeeff"),
    ("fips197_allzero", "00000000000000000000000000000000"[:32], "00000000000000000000000000000000"[:32]),
    ("random_1", "2b7e151628aed2a6abf7158809cf4f3c", "6bc1bee22e409f96e93d7e117393172a"),
]


if __name__ == "__main__":
    for name, key_hex, pt_hex in TEST_VECTORS:
        key = bytes.fromhex(key_hex)
        pt = bytes.fromhex(pt_hex)
        ct = aes128_ecb_encrypt_block(key, pt)
        print(f"[{name}] key={key_hex} pt={pt_hex} ct={ct.hex()}")
