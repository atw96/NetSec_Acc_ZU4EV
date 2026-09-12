# 03 TCP/IP 协议栈硬件加速 (TCP/IP Offload)

## 功能描述
硬件实现 IP/TCP/UDP 校验和的增量计算（RFC 1071 算法），并提供简化的 IP 分片重组状态机。

## 子模块 A：RFC1071 增量校验和引擎（已实现并验证）
算法：将报文视为 16bit 字为单位反码求和，最终取反。硬件采用流水线一位宽 16bit 累加器
+ 进位回卷（end-around carry）：

```
sum = 0
for each 16-bit word w in header/payload:
    sum = sum + w
    if sum > 0xFFFF: sum = (sum & 0xFFFF) + 1   // end-around carry
checksum = ~sum & 0xFFFF
```

硬件实现为逐字（16bit/cycle）流水线累加器，1 级加法 + 1 级回卷修正，可达到
每周期消耗 1 个 16bit 字的吞吐，满足千兆线速需求（125MHz * 16bit = 2Gbps 数据面吞吐能力，
足够覆盖千兆口）。

接口：`data_valid`, `data[15:0]`, `data_last` → `checksum_valid`, `checksum[15:0]`

## 子模块 B：IP 分片重组（简化版，文档级说明）
真实分片重组需要维护分片缓冲区、超时管理、乱序到达处理，复杂度较高。
本项目仅实现**同一 IP ID 的顺序到达分片**的简单拼接演示（不处理乱序/超时/攻击性分片），
在 README 中明确注明"非 RFC 完整合规实现，仅体现协议理解"。

## 时序/资源预估
- 校验和引擎：LUT 约 50~100，FF 约 32，无 BRAM，2 级流水线。
- 分片重组（简化版）：需要小型 BRAM 缓存单帧数据，资源视最大帧长而定。

## 验证方式
`python_model/golden_model_checksum.py` 用标准库实现 RFC1071 校验和作为黄金参考，
与 RTL 仿真结果逐字节比对（见 `tb/simple_tb/tb_checksum.sv`）。
