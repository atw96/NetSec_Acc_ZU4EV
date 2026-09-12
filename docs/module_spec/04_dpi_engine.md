# 04 DPI 深度报文检测引擎 (DPI Engine)

## 设计取舍说明（重要，建议面试中主动说明）
规格书原始方案建议采用 **Aho-Corasick 多模式匹配自动机**。完整 Aho-Corasick 需要
构建 goto/fail/output 三张表并生成较大状态转移 ROM，工程量与验证复杂度较高。

在时间与验证条件受限的 PoC 阶段，本仓库采用**并行比较器阵列（Parallel Comparator
Array）**方案作为替代实现：
- 对一个小型固定特征库（默认 8 条，长度 4~16 字节的攻击特征串，模拟 Snort 规则 payload 关键字）
- 每条特征对应一个独立的"滑动窗口 + 逐字节比较"状态机，N 条特征并行比较，
  每字节到达时所有比较器并行推进；任一比较器命中即拉高对应 `hit[i]`。
- 优点：结构简单、时序容易收敛、易于验证；
- 缺点：特征库规模扩大后（>百条）LUT 资源随特征数线性增长，不如 Aho-Corasick 的
  O(文本长度) 复杂度友好，**不适合直接商用**，仅作为原理验证。

`docs/module_spec/04_dpi_engine.md` 附加一节："若升级为真正 Aho-Corasick 需要的
工作量"，供面试展示技术路线认知：需要 (1) 离线构建自动机（Python：
`python_model/golden_model_dpi.py` 中已包含一个纯 Python版 Aho-Corasick 参考实现，
可直接用于生成状态表）(2) 用生成的状态表实例化 ROM (3) RTL 部分只需实现"查表+跳转"的
通用状态机，与特征数量解耦。

## 接口定义
输入：`data_valid`, `data[7:0]`, `data_last`（报文 payload 字节流）
输出：`hit_valid`, `hit_vector[7:0]`（8 条特征各自的命中标志，1 拍脉冲）

## 时序/资源预估
- 8 条特征、平均长度 8 字节：每条比较器约 8 字节寄存器 + 8 个比较器 + 移位逻辑，
  预估约 40~60 LUT/特征，共约 400~500 LUT。
- 单周期 1 字节，满足千兆线速。

## 验证方式
Python `golden_model_dpi.py` 对同一段随机+注入特征的字节流做参考匹配，
与 RTL 输出的 `hit_vector` 逐拍比对。
