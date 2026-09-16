/*
 * netsec_test.c — Zynq UltraScale+ OCM bare-metal poke of netsec_regs
 * Base: 0x8005_0000 (M_AXI_HPM0_LPD)
 *
 * Build (Vitis 2020.1 / SDK):
 *   1. File > New > Application Project from firmware/netsec.xsa
 *   2. Replace src with this file; use lscript.ld (OCM only, no DDR)
 *   3. UART0 @ 115200 (MIO42/43)
 */
#include <stdint.h>

#ifdef __XILINX__
#include "xil_printf.h"
#include "xil_io.h"
#include "sleep.h"
#define PRINT xil_printf
#define DELAY_MS(ms) usleep((ms) * 1000)
#else
#include <stdio.h>
#define PRINT printf
#define DELAY_MS(ms) do { volatile int _i; for (_i = 0; _i < (ms) * 80000; _i++); } while (0)
#endif

#define NETSEC_BASE   0x80050000UL
#define REG_CTRL      0x00
#define REG_STATUS    0x04
#define REG_LOOPBACK  0x08
#define REG_CNT_RX    0x10
#define REG_CNT_TX    0x14
#define REG_CNT_FWD   0x18
#define REG_CNT_DROP  0x1C
#define REG_CNT_MIR   0x20
#define REG_CNT_DPI   0x24
#define REG_MDIO_CTRL 0x50
#define REG_MDIO_WD   0x54
#define REG_MDIO_RD   0x58

static inline uint32_t nrd(uint32_t off)
{
#ifdef Xil_In32
    return Xil_In32(NETSEC_BASE + off);
#else
    return *(volatile uint32_t *)(NETSEC_BASE + off);
#endif
}

static inline void nwr(uint32_t off, uint32_t val)
{
#ifdef Xil_Out32
    Xil_Out32(NETSEC_BASE + off, val);
#else
    *(volatile uint32_t *)(NETSEC_BASE + off) = val;
#endif
}

static void dump(const char *tag)
{
    PRINT("%s STATUS=%08x RX=%u TX=%u FWD=%u DROP=%u MIR=%u DPI=%u\r\n",
          tag, nrd(REG_STATUS),
          nrd(REG_CNT_RX), nrd(REG_CNT_TX), nrd(REG_CNT_FWD),
          nrd(REG_CNT_DROP), nrd(REG_CNT_MIR), nrd(REG_CNT_DPI));
}

static void l0_test(void)
{
    nwr(REG_CTRL, 0x3);
    DELAY_MS(5);
    nwr(REG_LOOPBACK, 1);
    nwr(REG_CTRL, 0x101);
    DELAY_MS(50);
    dump("L0");
}

static void l1_test(void)
{
    nwr(REG_CTRL, 0x3);
    DELAY_MS(5);
    nwr(REG_LOOPBACK, 2);
    nwr(REG_CTRL, 0x101);
    DELAY_MS(50);
    dump("L1");
}

int main(void)
{
    PRINT("netsec_test OCM start\r\n");
    dump("boot");
    l0_test();
    l1_test();
    nwr(REG_LOOPBACK, 0);
    nwr(REG_CTRL, 0x1);
    dump("L3-ready");
    PRINT("done\r\n");
    for (;;)
        ;
    return 0;
}
