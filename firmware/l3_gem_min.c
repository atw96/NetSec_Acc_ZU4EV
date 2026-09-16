/* Freestanding A53 GEM3 TX — no Xilinx CRT/MMU/cache. Entry @ 0xFFFF0000 */
typedef unsigned int u32;

#define GEM 0xFF0E0000u
#define BD  0xFFFC0000u
#define FRM 0xFFFC0100u
#define MB  0xFFFEF000u

static inline void wr(u32 a, u32 v) { *(volatile u32 *)(unsigned long)a = v; }
static inline u32  rd(u32 a) { return *(volatile u32 *)(unsigned long)a; }

static void delay(unsigned n)
{
    volatile unsigned i;
    for (i = 0; i < n; i++)
        ;
}

__attribute__((naked, section(".vectors")))
void _vec(void)
{
    asm volatile(
        "mov x0, #0xF000\n"
        "movk x0, #0xFFFE, lsl #16\n"
        "mov w1, #0x33A0\n"
        "movk w1, #0x4E53, lsl #16\n"
        "str w1, [x0]\n"
        "mov x2, #0x0000\n"
        "movk x2, #0xFFFE, lsl #16\n"
        "mov sp, x2\n"
        "b _start\n"
    );
}

void _start(void)
{
    unsigned i, ok = 0;
    u32 st;

    asm volatile("mov sp, #0xFFFE0000");
    wr(MB, 0x4E5333A0);
    wr(MB + 4, 0);
    wr(MB + 8, 0);

    wr(GEM + 0x00, 0);
    wr(GEM + 0x04, 0x002C0412);
    wr(GEM + 0x10, 0x40180704);
    wr(GEM + 0x88, 0x00000002);
    wr(GEM + 0x8C, 0x0000A300);
    wr(GEM + 0x14, 0xFF);
    wr(GEM + 0x2C, 0xFFFFFFFF);

    /* dummy RX */
    wr(0xFFFC0400, 0xFFFC0502);
    wr(0xFFFC0404, 0);
    wr(GEM + 0x18, 0xFFFC0400);
    wr(GEM + 0x4D4, 0);
    /* dummy Q1 */
    wr(0xFFFC0600, 0xFFFC0700);
    wr(0xFFFC0604, 0xC0000000);
    wr(GEM + 0x440, 0xFFFC0600);
    wr(GEM + 0x4C8, 0);

    wr(MB, 0x4E5333B1);

    /* 64-byte broadcast frame */
    wr(FRM + 0, 0xFFFFFFFF);
    wr(FRM + 4, 0x0002FFFF);
    wr(FRM + 8, 0xA3000000);
    wr(FRM + 12, 0x00450008);
    wr(FRM + 16, 0x00000040);
    for (i = 20; i < 64; i += 4)
        wr(FRM + i, 0);

    wr(GEM + 0x00, 0x10);
    delay(1000);
    wr(GEM + 0x1C, BD);
    wr(GEM + 0x00, 0x18);
    wr(MB, 0x4E5333B2);

    for (i = 0; i < 20; i++) {
        wr(BD + 0, FRM);
        wr(BD + 4, 0x40008040);
        wr(BD + 8, 0);
        wr(BD + 12, 0);
        wr(GEM + 0x00, rd(GEM + 0x00) | 0x200);
        {
            unsigned t;
            for (t = 0; t < 200000u; t++) {
                st = rd(BD + 4);
                if (st & 0x80000000u)
                    break;
            }
        }
        if (st & 0x80000000u)
            ok++;
        wr(GEM + 0x14, 0xFF);
        delay(2000);
    }

    wr(MB + 4, ok);
    wr(MB + 8, rd(GEM + 0x108));
    wr(MB + 12, rd(GEM + 0x14));
    wr(MB, 0x4E53334C);
    for (;;)
        ;
}
