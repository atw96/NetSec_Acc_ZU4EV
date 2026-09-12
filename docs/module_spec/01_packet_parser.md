# 01 报文解析引擎 (Packet Parser)

## 功能描述
从 MAC 层接收到的字节流中，逐拍提取 L2(以太网)/L3(IPv4)/L4(TCP/UDP) 关键字段，
并将提取结果与原始报文一起以流水线方式向下游（流表匹配、TCP/IP 加速）传递。

## 接口定义

输入（来自 MAC RX，简化 AXI-Stream，8bit 数据位宽，便于时序收敛与逐字节解析）：
- `s_valid`, `s_data[7:0]`, `s_last`

输出（向下游）：
- `m_valid`, `m_data[7:0]`, `m_last`（透传原始字节流）
- `m_user`：解析结果总线，包含：
  - `eth_type[15:0]`
  - `ip_valid`, `src_ip[31:0]`, `dst_ip[31:0]`, `protocol[7:0]`, `ip_hdr_len[3:0]`
  - `l4_valid`, `src_port[15:0]`, `dst_port[15:0]`
  - `hdr_done`（字段全部提取完成脉冲）

## 状态机

```
IDLE -> ETH_HDR(14B) -> IP_HDR(20B, 可变长跳过Option) -> L4_HDR(TCP 20B / UDP 8B) -> PAYLOAD -> (等待 s_last) -> IDLE
```

- `ETH_HDR`：计数 0~13 字节，第 12~13 字节为 EtherType，判断是否为 0x0800(IPv4)。
- `IP_HDR`：字节 0 高 4bit 为 IHL，决定 IP 头长度（IHL*4 字节，标准 20B，含选项时更长）；
  字节 9 为 Protocol（6=TCP, 17=UDP）；字节 12~15/16~19 为源/目的 IP。
- `L4_HDR`：TCP/UDP 前 4 字节为源/目的端口。
- 非 IPv4 或非 TCP/UDP 报文：`ip_valid`/`l4_valid` 置 0，仅透传字节流，不参与后续流表匹配。

## 时序/资源预估
- 单周期 1 字节吞吐，1500B 最大帧约需 1500 拍；千兆速率下每字节 8ns 预算，
  设计目标时钟 125MHz（8ns 周期）即可满足线速解析。
- 资源预估：约 200~400 LUT / 150 FF（字段寄存器 + 状态机），无 BRAM。
- 若需万兆速率，需改为多字节并行（如 8B/cycle）解析，当前版本为单字节版本，
  仓库中明确标注为千兆速率原理验证版本。

## 已知简化/取舍
- 不支持 VLAN Tag(802.1Q)、IPv6、IP 分片以外的复杂情况，只解析常见 IPv4/TCP/UDP 报文。
- 不做 IP 头校验和校验（该功能归属 03 号 TCP/IP 加速模块）。
