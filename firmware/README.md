# PS 端控制程序骨架 (firmware/)

本目录为 PS 侧（裸机 / PetaLinux 用户态）AXI-Lite 寄存器驱动骨架，用于：
- 规则/特征库下发
- 流表状态查询与人工加白/拉黑
- 统计计数器读取（命中数、丢包数等）

## 寄存器地址映射（示例，需与 Vivado IP 集成时的实际地址对齐）

| 偏移 | 寄存器 | 说明 |
|---|---|---|
| 0x00 | CTRL | bit0: 全局使能; bit1: 软复位 |
| 0x04 | STATUS | bit0: 数据面就绪 |
| 0x10 | FLOW_QUERY_KEY_LO/HI | 待查询流的五元组（多字寄存器） |
| 0x20 | FLOW_UPDATE_IDX | 目标流表项索引 |
| 0x24 | FLOW_UPDATE_STATE | 写入的新状态(00/01/10/11) |
| 0x30 | STAT_DROP_CNT | 累计丢包计数 |
| 0x34 | STAT_MIRROR_CNT | 累计告警(镜像上送)计数 |

## 裸机驱动骨架 (C)

```c
// axi_lite_driver.h (骨架，需替换 BASE_ADDR 为实际 Vivado 地址编辑器分配的基地址)
#define NETSEC_BASE_ADDR   0xA0000000UL
#define REG_CTRL           (*(volatile unsigned int*)(NETSEC_BASE_ADDR + 0x00))
#define REG_STATUS         (*(volatile unsigned int*)(NETSEC_BASE_ADDR + 0x04))
#define REG_FLOW_UPDATE_IDX   (*(volatile unsigned int*)(NETSEC_BASE_ADDR + 0x20))
#define REG_FLOW_UPDATE_STATE (*(volatile unsigned int*)(NETSEC_BASE_ADDR + 0x24))
#define REG_STAT_DROP_CNT     (*(volatile unsigned int*)(NETSEC_BASE_ADDR + 0x30))

static inline void netsec_enable(void)      { REG_CTRL |= 0x1; }
static inline void netsec_soft_reset(void)  { REG_CTRL |= 0x2; }
static inline unsigned int netsec_get_drop_count(void) { return REG_STAT_DROP_CNT; }

// 人工将某条流标记为阻断（例如运维通过 CLI/Web 下发黑名单）
static inline void netsec_block_flow(unsigned int flow_idx) {
    REG_FLOW_UPDATE_IDX   = flow_idx;
    REG_FLOW_UPDATE_STATE = 0b11; // FS_BLOCKED
}
```

**状态说明**：以上为骨架代码，尚未在真实硬件上验证（本沙箱无 AXU4EV 板卡与 Vivado
地址编辑器生成的真实基地址）。集成到 Vivado Block Design 后，请以 Address Editor
中分配的实际基地址替换 `NETSEC_BASE_ADDR`，并根据 AXI-Lite 从设备(u_ips_decision
外围包装的寄存器接口，需自行补充一层 AXI4-Lite Slave 适配逻辑，当前仓库的核心模块
只暴露了简化的原生信号接口，AXI-Lite 封装层属于待补充的集成工作)。
