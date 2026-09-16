"""
DPI 多模式匹配 —— 黄金参考模型
(a) 滑动窗口精确比较（历史 RTL）
(b) Aho-Corasick（与当前 `u_dpi_matcher` 对齐；4×4B 无重叠时与 (a) 命中位置相同）
"""
from typing import List, Tuple

PATTERNS = [
    bytes.fromhex("47455420"),  # "GET "
    bytes.fromhex("636d642e"),  # "cmd."
    bytes.fromhex("53454c45"),  # "SELE"
    bytes.fromhex("90909090"),  # NOP sled
]


def sliding_window_match(stream: bytes) -> List[Tuple[int, int]]:
    """返回 (字节位置, 命中的特征索引) 列表，字节位置为该 4B 窗口最后一个字节的索引，
    与 RTL 中 data_valid 且窗口对齐时的语义一致。"""
    hits = []
    for i in range(len(stream)):
        if i < 3:
            continue
        window = stream[i-3:i+1]
        for pidx, pat in enumerate(PATTERNS):
            if window == pat:
                hits.append((i, pidx))
    return hits


# ---------------- 通用 Aho-Corasick 参考实现（供未来升级 RTL 使用） ----------------
class AhoCorasick:
    def __init__(self, patterns: List[bytes]):
        self.goto = [dict()]
        self.fail = [0]
        self.output = [set()]
        for idx, pat in enumerate(patterns):
            self._insert(pat, idx)
        self._build_fail()

    def _insert(self, pat: bytes, idx: int):
        state = 0
        for b in pat:
            if b not in self.goto[state]:
                self.goto.append(dict())
                self.fail.append(0)
                self.output.append(set())
                self.goto[state][b] = len(self.goto) - 1
            state = self.goto[state][b]
        self.output[state].add(idx)

    def _build_fail(self):
        from collections import deque
        q = deque()
        for b, s in self.goto[0].items():
            self.fail[s] = 0
            q.append(s)
        while q:
            r = q.popleft()
            for b, s in self.goto[r].items():
                q.append(s)
                f = self.fail[r]
                while f and b not in self.goto[f]:
                    f = self.fail[f]
                self.fail[s] = self.goto[f].get(b, 0) if (f or b in self.goto[0]) else 0
                self.output[s] |= self.output[self.fail[s]]

    def search(self, stream: bytes) -> List[Tuple[int, int]]:
        state = 0
        hits = []
        for i, b in enumerate(stream):
            while state and b not in self.goto[state]:
                state = self.fail[state]
            state = self.goto[state].get(b, 0)
            for pidx in self.output[state]:
                hits.append((i, pidx))
        return hits


if __name__ == "__main__":
    test_stream = (
        b"AB" + b"GET " + b"/index.html HTTP/1.1\r\n" +
        b"randomjunk" + b"cmd." + b"exe /c dir" +
        b"more_junk_SELE" + b"CT * FROM users" +
        b"\x90\x90\x90\x90" + b"tail_bytes"
    )
    print("Sliding-window (RTL-equivalent) hits:")
    for pos, pidx in sliding_window_match(test_stream):
        print(f"  byte_idx={pos} pattern={pidx} ({PATTERNS[pidx].hex()})")

    print("\nAho-Corasick reference hits (for future full-automaton RTL):")
    ac = AhoCorasick(PATTERNS)
    for pos, pidx in ac.search(test_stream):
        print(f"  byte_idx={pos} pattern={pidx}")

    print(f"\ntotal stream length = {len(test_stream)} bytes")
    print("stream hex:", test_stream.hex())
