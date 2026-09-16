/*
 * netsec_l3_gem3.c — PS GEM3 (port 1) <-> PL RGMII (port 2) dual-port L3 test
 *
 * Cable: RJ45 port1 (PS) straight to port2 (PL). OCM only, no DDR.
 * Results mailbox @ 0xFFFEF000. Stage codes: A0 after first store,
 * A1 after barrier, 302 skip PL, 303 gem_setup, 304 phy+1, 305 AN done, 306 pre-TX,
 * 307 post-TX, E1 gem_setup fail. Final magic NS3L.
 */
#include <stdint.h>
#include <string.h>

#include "xparameters.h"
#include "xil_io.h"
#include "xemacps.h"
/* No UART / no TTC — both can hang before mailbox if clocks are incomplete. */
#define PRINT(...) do { } while (0)
static void delay_ms(unsigned ms)
{
    volatile unsigned i, j;
    for (i = 0; i < ms; i++)
        for (j = 0; j < 80000U; j++)
            ;
}
#define DELAY_MS(ms) delay_ms(ms)

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

#define MAILBOX       0xFFFEF000UL
#define MB_MAGIC      0x4E53334CUL /* "NS3L" */

#define N_NORMAL      16
#define N_ATTACK      4
#define FRAME_LEN     128
#define RX_BD_CNT     32
#define TX_BD_CNT     24

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

static inline void mb_barrier(void)
{
    /* dc civac / Xil_DCacheFlushRange hangs on this OCM window (device/SO). */
    __asm__ volatile ("dsb sy" ::: "memory");
}

static void mb_write(uint32_t *w)
{
    volatile uint32_t *mb = (volatile uint32_t *)MAILBOX;
    unsigned i;
    for (i = 0; i < 12; i++)
        mb[i] = w[i];
    mb_barrier();
}

static void mb_stage(uint32_t stage, uint32_t extra)
{
    uint32_t w[12];
    unsigned i;
    for (i = 0; i < 12; i++)
        w[i] = 0;
    w[0] = stage;
    w[9] = extra;
    w[10] = 1;
    mb_write(w);
}

#define BD_ALIGN 64
static XEmacPs Emac;
static XEmacPs_BdRing *TxRing;
static XEmacPs_BdRing *RxRing;
static u8 TxBdSpace[TX_BD_CNT * sizeof(XEmacPs_Bd) + BD_ALIGN] __attribute__((aligned(64)));
static u8 RxBdSpace[RX_BD_CNT * sizeof(XEmacPs_Bd) + BD_ALIGN] __attribute__((aligned(64)));
static u8 TxBuf[TX_BD_CNT][FRAME_LEN] __attribute__((aligned(64)));
static u8 RxBuf[RX_BD_CNT][FRAME_LEN] __attribute__((aligned(64)));

static int phy_read(u32 phy, u32 reg, u16 *v)
{
    return XEmacPs_PhyRead(&Emac, phy, reg, v);
}

static int phy_write(u32 phy, u32 reg, u16 v)
{
    return XEmacPs_PhyWrite(&Emac, phy, reg, v);
}

static int find_phy(void)
{
    u16 id1, id2;
    u32 a;
    for (a = 0; a < 32; a++) {
        if (phy_read(a, 2, &id1) != XST_SUCCESS)
            continue;
        if (id1 == 0x0000 || id1 == 0xFFFF)
            continue;
        phy_read(a, 3, &id2);
        PRINT("GEM3 PHY addr=%u ID1=%04x ID2=%04x\r\n", a, id1, id2);
        return (int)a;
    }
    PRINT("GEM3: no PHY found on MDIO\r\n");
    return -1;
}

static void phy_eee_off(u32 phy)
{
    /* Clause-22 MMD 7.60: clear EEE advertisement (verified PSU sequence). */
    phy_write(phy, 13, 0x0007);
    phy_write(phy, 14, 0x003C);
    phy_write(phy, 13, 0x4007);
    phy_write(phy, 14, 0x0000);
}

static int phy_an_1g(int phy)
{
    u16 bmsr = 0;
    int i;
    phy_read((u32)phy, 1, &bmsr);
    if ((bmsr & 0x0024) == 0x0024) {
        phy_eee_off((u32)phy);
        PRINT("GEM3 PHY already up BMSR=%04x\r\n", bmsr);
        return 0;
    }
    phy_write((u32)phy, 0, 0x8000);
    DELAY_MS(50);
    phy_write((u32)phy, 4, 0x0001);
    phy_write((u32)phy, 9, 0x0200);
    phy_eee_off((u32)phy);
    phy_write((u32)phy, 0, 0x1200);
    for (i = 0; i < 40; i++) {
        DELAY_MS(200);
        phy_read((u32)phy, 1, &bmsr);
        if ((bmsr & 0x0024) == 0x0024) {
            PRINT("GEM3 PHY AN done BMSR=%04x\r\n", bmsr);
            return 0;
        }
    }
    PRINT("GEM3 PHY AN timeout BMSR=%04x\r\n", bmsr);
    return -1;
}

static UINTPTR align64(UINTPTR p)
{
    return (p + 63U) & ~(UINTPTR)63U;
}

static int gem_setup(void)
{
    XEmacPs_Config *cfg;
    XEmacPs_Bd bd_t;
    u8 mac[6] = {0x02, 0x00, 0x00, 0x00, 0x00, 0xA3};
    int i;
    UINTPTR txb, rxb;

#ifdef XPAR_XEMACPS_0_DEVICE_ID
    cfg = XEmacPs_LookupConfig(XPAR_XEMACPS_0_DEVICE_ID);
#else
    cfg = XEmacPs_LookupConfig(0);
#endif
    if (cfg == NULL) {
        PRINT("GEM3: LookupConfig failed\r\n");
        return -1;
    }
    mb_stage(0x4E533311, (uint32_t)cfg->BaseAddress);
    mb_stage(0x4E533318, *(volatile uint32_t *)(cfg->BaseAddress + 0xFC));
    if (XEmacPs_CfgInitialize(&Emac, cfg, cfg->BaseAddress) != XST_SUCCESS) {
        PRINT("GEM3: CfgInitialize failed\r\n");
        return -1;
    }
    mb_stage(0x4E533312, 0);
#ifdef XEMACPS_MDIO_DIV_32
    XEmacPs_SetMdioDivisor(&Emac, XEMACPS_MDIO_DIV_32);
#endif
    XEmacPs_SetMacAddress(&Emac, mac, 1);
    XEmacPs_SetOperatingSpeed(&Emac, 1000);
    XEmacPs_SetOptions(&Emac, XEMACPS_PROMISC_OPTION | XEMACPS_BROADCAST_OPTION |
                       XEMACPS_FCS_STRIP_OPTION | XEMACPS_TRANSMITTER_ENABLE_OPTION |
                       XEMACPS_RECEIVER_ENABLE_OPTION);

    txb = align64((UINTPTR)TxBdSpace);
    rxb = align64((UINTPTR)RxBdSpace);
    TxRing = &Emac.TxBdRing;
    RxRing = &Emac.RxBdRing;
    if (XEmacPs_BdRingCreate(TxRing, txb, txb, XEMACPS_BD_ALIGNMENT, TX_BD_CNT) != XST_SUCCESS)
        return -1;
    if (XEmacPs_BdRingClone(TxRing, &bd_t, XEMACPS_SEND) != XST_SUCCESS)
        return -1;
    if (XEmacPs_BdRingCreate(RxRing, rxb, rxb, XEMACPS_BD_ALIGNMENT, RX_BD_CNT) != XST_SUCCESS)
        return -1;
    if (XEmacPs_BdRingClone(RxRing, &bd_t, XEMACPS_RECV) != XST_SUCCESS)
        return -1;

    for (i = 0; i < RX_BD_CNT; i++) {
        XEmacPs_Bd *bd;
        if (XEmacPs_BdRingAlloc(RxRing, 1, &bd) != XST_SUCCESS)
            return -1;
        XEmacPs_BdSetAddressRx(bd, (UINTPTR)RxBuf[i]);
        XEmacPs_BdClear(bd);
        XEmacPs_BdSetLength(bd, FRAME_LEN);
        XEmacPs_BdRingToHw(RxRing, 1, bd);
    }
    /* ZynqMP GEM Version>2: XEmacPs_Start does not write QBASE. Must do it
     * here before Start (SetQueuePtr is a no-op once started). Q1 gets a
     * dummy USED/WRAP BD so a live-queue mismatch cannot walk junk. */
    {
        static u8 dummy_txbd[16] __attribute__((aligned(16)));
        memset(dummy_txbd, 0, sizeof(dummy_txbd));
        dummy_txbd[4] = 0x00;
        dummy_txbd[5] = 0x00;
        dummy_txbd[6] = 0x00;
        dummy_txbd[7] = 0xC0; /* USED | WRAP, little-endian */
        XEmacPs_SetQueuePtr(&Emac, txb, 0, XEMACPS_SEND);
        XEmacPs_SetQueuePtr(&Emac, (UINTPTR)dummy_txbd, 1, XEMACPS_SEND);
        XEmacPs_SetQueuePtr(&Emac, rxb, 0, XEMACPS_RECV);
    }
    mb_stage(0x4E533313, (uint32_t)txb);
    XEmacPs_Start(&Emac);
    mb_stage(0x4E533314, 0);
    /* TX path: MDEN|TXEN without RXEN (0x18). RXEN makes USED never write back. */
    XEmacPs_WriteReg(cfg->BaseAddress, XEMACPS_NWCTRL_OFFSET,
                     XEMACPS_NWCTRL_MDEN_MASK | XEMACPS_NWCTRL_TXEN_MASK);
    return 0;
}

static void fill_frame(u8 *p, int attack, int idx)
{
    static const u8 dst[6] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff};
    static const u8 src[6] = {0x02, 0x00, 0x00, 0x00, 0x00, 0xA3};
    memset(p, 0, FRAME_LEN);
    memcpy(p, dst, 6);
    memcpy(p + 6, src, 6);
    p[12] = 0x08;
    p[13] = 0x00;
    p[14] = 0x45;
    p[15] = 0x00;
    p[16] = 0x00;
    p[17] = 80;
    p[22] = 0x40;
    p[23] = 0x00;
    p[24] = 64;
    p[25] = 6;
    if (attack) {
        p[26] = 10; p[27] = 0; p[28] = 0; p[29] = 5;
        memcpy(p + 54, "GET /", 5);
    } else {
        p[26] = 192; p[27] = 168; p[28] = 1; p[29] = 2;
        memcpy(p + 54, "ping", 4);
    }
    p[30] = 192; p[31] = 168; p[32] = 1; p[33] = 100;
    p[34] = (u8)(0x30 + (idx >> 8));
    p[35] = (u8)idx;
    p[36] = 0x00;
    p[37] = 80;
}

static u8 TxBdRaw[16] __attribute__((aligned(16)));

static int gem_send(int idx, u32 len)
{
    volatile uint32_t *bd = (volatile uint32_t *)(void *)TxBdRaw;
    UINTPTR base = Emac.Config.BaseAddress;
    u8 *frame = TxBuf[idx];
    int i;
    /* Verified PSU sequence: TXEN off → rewrite BD → 0x18 → STARTTX → wait USED */
    XEmacPs_WriteReg(base, XEMACPS_NWCTRL_OFFSET, XEMACPS_NWCTRL_MDEN_MASK);
    bd[0] = (uint32_t)(uintptr_t)frame;
    bd[1] = XEMACPS_TXBUF_WRAP_MASK | XEMACPS_TXBUF_LAST_MASK |
            (len & XEMACPS_TXBUF_LEN_MASK);
    bd[2] = 0;
    bd[3] = 0;
    mb_barrier();
    XEmacPs_WriteReg(base, XEMACPS_TXQBASE_OFFSET, (u32)(uintptr_t)TxBdRaw);
    XEmacPs_WriteReg(base, XEMACPS_TXQ1BASE_OFFSET, (u32)(uintptr_t)TxBdRaw);
    XEmacPs_WriteReg(base, XEMACPS_MSBBUF_TXQBASE_OFFSET, 0);
    XEmacPs_WriteReg(base, XEMACPS_NWCTRL_OFFSET,
                     XEMACPS_NWCTRL_MDEN_MASK | XEMACPS_NWCTRL_TXEN_MASK);
    XEmacPs_WriteReg(base, XEMACPS_NWCTRL_OFFSET,
                     XEMACPS_NWCTRL_MDEN_MASK | XEMACPS_NWCTRL_TXEN_MASK |
                     XEMACPS_NWCTRL_STARTTX_MASK);
    for (i = 0; i < 400; i++) {
        if ((bd[1] & XEMACPS_TXBUF_USED_MASK) != 0)
            break;
        DELAY_MS(1);
    }
    XEmacPs_WriteReg(base, XEMACPS_TXSR_OFFSET, 0xFF);
    return 0;
}

static void gem_drain(int *nrx, int *nget)
{
    XEmacPs_Bd *bd;
    int n, i;
    n = XEmacPs_BdRingFromHwRx(RxRing, RX_BD_CNT, &bd);
    for (i = 0; i < n; i++) {
        u32 len = XEmacPs_BdGetLength(bd);
        u8 *p = (u8 *)(UINTPTR)XEmacPs_BdGetBufAddr(bd);
        (*nrx)++;
        if (len >= 59 && memcmp(p + 54, "GET ", 4) == 0)
            (*nget)++;
        XEmacPs_BdClear(bd);
        XEmacPs_BdSetLength(bd, FRAME_LEN);
        XEmacPs_BdSetAddressRx(bd, (UINTPTR)p);
        bd = XEmacPs_BdRingNext(RxRing, bd);
    }
    if (n > 0)
        XEmacPs_BdRingFree(RxRing, n, XEmacPs_BdRingPrev(RxRing, bd));
    if (n > 0) {
        XEmacPs_Bd *nb;
        if (XEmacPs_BdRingAlloc(RxRing, n, &nb) == XST_SUCCESS)
            XEmacPs_BdRingToHw(RxRing, n, nb);
    }
}
int main(void)
{
    uint32_t mb[12];
    int gem_rx = 0, gem_get = 0;
    int i;

    /* Mailbox first. No Xil_DCache* — dc civac hangs on this OCM window. */
    *(volatile uint32_t *)MAILBOX = 0x4E5333A0;
    mb_barrier();
    memset(mb, 0, sizeof(mb));
    mb_stage(0x4E5333A1, 0);
    /* Do not touch 0x80050000 from A53 — HPM0 can hang if isolation/SMMU
     * is incomplete. PL is armed by xsct/Vivado; we only drive GEM3. */
    mb_stage(0x4E533302, 0);

    if (gem_setup() != 0) {
        mb_stage(0x4E5333E1, 0);
        goto report;
    }
    mb_stage(0x4E533303, 0);
    {
        int phy = find_phy();
        mb_stage(0x4E533304, (uint32_t)(phy + 1));
        if (phy >= 0)
            phy_an_1g(phy);
    }
    mb_stage(0x4E533305, 0);
    DELAY_MS(500);
    mb_stage(0x4E533306, XEmacPs_ReadReg(Emac.Config.BaseAddress, XEMACPS_NWCTRL_OFFSET));

    for (i = 0; i < N_NORMAL; i++) {
        fill_frame(TxBuf[i], 0, i);
        mb_stage(0x4E533306, (uint32_t)i);
        gem_send(i, FRAME_LEN);
    }
    mb_stage(0x4E533316, 0);
    for (i = 0; i < N_ATTACK; i++) {
        fill_frame(TxBuf[N_NORMAL + i], 1, i);
        gem_send(N_NORMAL + i, FRAME_LEN);
    }
    mb_stage(0x4E533317, 0);
    /* Enable RX to collect the PL echo, then drain. */
    {
        u32 nw = XEmacPs_ReadReg(Emac.Config.BaseAddress, XEMACPS_NWCTRL_OFFSET);
        XEmacPs_WriteReg(Emac.Config.BaseAddress, XEMACPS_NWCTRL_OFFSET,
                         nw | XEMACPS_NWCTRL_RXEN_MASK);
    }
    DELAY_MS(200);
    gem_drain(&gem_rx, &gem_get);
    mb_stage(0x4E533307, (uint32_t)gem_rx);

report:
    mb[0] = MB_MAGIC;
    mb[1] = 0;
    if (Emac.IsReady)
        mb[1] = XEmacPs_ReadReg(Emac.Config.BaseAddress, XEMACPS_RXCNT_OFFSET);
    mb[2] = 0;
    mb[3] = 0;
    mb[4] = 0;
    mb[5] = 0;
    mb[6] = 0;
    mb[7] = (uint32_t)gem_rx;
    mb[8] = (uint32_t)gem_get;
    mb[9] = 0;
    mb[10] = 1;
    mb[11] = 0;
    mb_write(mb);
    PRINT("done mailbox@FFFEF000\r\n");
    for (;;)
        ;
    return 0;
}
