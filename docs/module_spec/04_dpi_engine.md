# 04 DPI 深度报文检测引擎 (DPI Engine)

## 设计取舍说明（重要，建议面试中主动说明）
规格书原始方案为 **Aho-Corasick**。本仓库 RTL（`u_dpi_matcher`）已实现 4×4B 可编程
goto/fail/output 自动机：`DPI_PAT0..3` 写入后由片上 FSM 重建状态表，匹配 1 字节/拍。
完整商用特征库（千条变长 Snort 规则 + ROM 编译器）仍不在范围内；当前规模与上板
`DPI_PAT` 接口对齐。

## 接口定义
输入：`data_valid`, `data[7:0]`, `data_last`（报文 payload 字节流）
输出：`hit_valid`, `hit_vector[7:0]`（8 条特征各自的命中标志，1 拍脉冲）

## 时序/资源
- 匹配路径：`trans[state][byte]` 一拍查表，命中再延迟 1 拍；数据面在 `tlast` 后再等 `dpi_lag=2` 才进 IPS。
- 17 状态 × 256 转移在 2020.1 上推断为 LUT/FF（非整片 BRAM），全芯片 LUT **22195 (25.27%)**。
- 单周期 1 字节，满足千兆线速。特征库仍是 4×4B，不是千条 Snort。

## 验证方式
Python `golden_model_dpi.py` 对同一段随机+注入特征的字节流做参考匹配，
与 RTL 输出的 `hit_vector` 逐拍比对。
