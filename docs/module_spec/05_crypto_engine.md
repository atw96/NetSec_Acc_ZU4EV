# 05 加解密引擎 (Crypto Engine)

## 5a. AES-128 （对称密码，已完整实现并验证）

标准 AES-128 分组加密，10 轮结构：
`AddRoundKey(轮0) → [SubBytes → ShiftRows → MixColumns → AddRoundKey] * 9 → [SubBytes → ShiftRows → AddRoundKey](末轮)`

- **密钥扩展 (Key Expansion)**：128bit 主密钥扩展出 11 组轮密钥（Rcon + S-box 查表），
  实现为组合逻辑一次性展开。
- **数据通路（本仓库实际实现：迭代型，非满流水线）**：单一 128bit 数据通路，
  每个时钟周期完成 1 轮变换，10 轮迭代复用同一套 SubBytes/ShiftRows/MixColumns/AddRoundKey
  组合逻辑，完成 1 个分组的加密需要约 10 个时钟周期（非同时处理多个分组）。
  @125MHz 估算单分组延迟约 80ns，吞吐约 128bit / 80ns ≈ 1.6Gbps（保守估算，忽略启动/切换开销）。
  **说明**：规格设计之初曾设想满流水线（10级流水线，每周期吞吐1个新分组，理论可达
  ~16Gbps），但为控制本阶段验证复杂度与资源，当前版本采用迭代实现；满流水线版本
  列为后续可扩展方向（见文末）。
- **模式**：本版本实现 ECB 单分组核心（`u_aes128_core`），CTR 模式可在 PS 侧或额外一层
  计数器+异或逻辑上叠加（v2 可扩展项，当前仓库标注为待办）。
- **验证**：`python_model/golden_model_aes.py` 使用 `pycryptodome` 生成
  NIST FIPS-197 标准测试向量（明文/密钥/密文三元组），与 RTL 仿真输出逐 bit 比对，
  **已在本仓库沙箱环境中用 Icarus Verilog 跑通并通过（3/3 向量，含 FIPS-197 Appendix B 标准向量）**。

## 5b. RSA 模幂运算（非对称密码，原理级 Demo，非完整实现）

**明确声明**：这是原理演示级模块，用于证明理解非对称密码硬件实现的核心难点
（大数模幂运算 = 重复模乘），**不是**可商用的 RSA 硬件加速器。

- 位宽：32bit（为便于仿真验证与资源可控，未采用真实 RSA 所需的 1024/2048bit）
- 算法：Square-and-Multiply（从高位到低位扫描指数 bit，每 bit 做一次平方+条件乘），
  未实现 Montgomery 模乘优化（Montgomery 需要额外的 Montgomery 域转换逻辑，
  工程量显著增加，作为"后续可扩展方向"写入 README）。
- 接口：`base[31:0]`, `exp[31:0]`, `mod[31:0]` → `result[31:0]`, `done`

## 时序/资源预估
- AES-128 单轮数据通路（S-box 16 份并行查找表 + MixColumns 矩阵乘）：
  预估 LUT 800~1500（S-box 若用 LUT 实现而非 BRAM，会占用较多 LUT，
  资源敏感场景可将 S-box 改为 BRAM/ROM 实现，本版本先用组合逻辑真值表以便仿真调试）。
- RSA 模幂 32bit Demo：LUT 约 200~300（32bit 乘法器 + 32bit 取模器）。

## 后续可扩展方向（诚实列出，避免过度承诺）
- AES：升级为满流水线多分组并行架构（10级流水线，每周期吞吐1个新分组），
  增加 CTR/GCM 模式、192/256bit 密钥长度、S-box 改用 BRAM 节省 LUT。
- RSA：升级到 Montgomery Ladder + 更大位宽（如 1024bit，需要多周期分块乘法器）。
