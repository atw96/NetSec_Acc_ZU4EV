/*
 * OCM-only A53 entry: MMU on (identity), DCache off.
 * libxil boot.S also turns DCache on; PSU JTAG then cannot see mailbox
 * stores, and dc civac hangs. MMU-off makes all RAM Device nGnRnE, so
 * unaligned STUR in XEmacPs_Reset aborts (ESR 0x96000061).
 * RVBAR / ELF entry must be 0xFFFF0000 (.boot).
 */
	.section .crt0_boot,"ax"
	.align 8
	.global _start
	.type _start, %function
	.extern MMUTableL0
_start:
	msr	daifset, #0xf

	/* MMU / caches off while programming tables */
	mov	x0, xzr
	msr	sctlr_el3, x0
	isb

	adr	x0, vectors
	msr	vbar_el3, x0

	ldr	x0, =__el3_stack
	mov	sp, x0

	/* SMPEN — recommended even with DCache off */
	mrs	x0, S3_1_c15_c2_1
	orr	x0, x0, #(1 << 6)
	msr	S3_1_c15_c2_1, x0
	isb

	tlbi	alle3
	ic	iallu
	dsb	sy
	isb

	ldr	x1, =MMUTableL0
	msr	ttbr0_el3, x1
	ldr	x1, =0x000000BB0400FF44
	msr	mair_el3, x1
	ldr	x1, =0x80823518
	msr	tcr_el3, x1
	isb

	/* M=1 I=1 C=0 A=0: OCM is Normal (unaligned OK), not in DCache */
	mov	x1, #(1 << 12)
	orr	x1, x1, #(1 << 0)
	msr	sctlr_el3, x1
	dsb	sy
	isb

	adrp	x0, __bss_start__
	add	x0, x0, :lo12:__bss_start__
	adrp	x1, __bss_end__
	add	x1, x1, :lo12:__bss_end__
1:
	cmp	x0, x1
	b.ge	2f
	str	xzr, [x0], #8
	b	1b
2:
	bl	main
3:
	wfe
	b	3b
	.size _start, .-_start

	.macro ventry label
	.align 7
	b	\label
	.endm

	.align	11
	.global vectors
vectors:
	ventry	exc_report
	ventry	exc_report
	ventry	exc_report
	ventry	exc_report
	ventry	exc_report
	ventry	exc_report
	ventry	exc_report
	ventry	exc_report
	ventry	exc_report
	ventry	exc_report
	ventry	exc_report
	ventry	exc_report
	ventry	exc_report
	ventry	exc_report
	ventry	exc_report
	ventry	exc_report

exc_report:
	mov	x0, #0xf000
	movk	x0, #0xfffe, lsl #16
	mov	w1, #0x33EE
	movk	w1, #0x4E53, lsl #16
	str	w1, [x0]
	mrs	x1, esr_el3
	str	w1, [x0, #4]
	mrs	x1, elr_el3
	str	w1, [x0, #8]
	mrs	x1, far_el3
	str	w1, [x0, #12]
	dsb	sy
4:
	wfe
	b	4b
