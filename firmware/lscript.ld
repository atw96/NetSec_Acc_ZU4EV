/* OCM-only linker script for Zynq UltraScale+ (no DDR). */
MEMORY
{
    ocm : ORIGIN = 0xFFFC0000, LENGTH = 0x00040000
}

_STACK_SIZE = 0x2000;
_HEAP_SIZE  = 0x2000;

SECTIONS
{
    .text : { *(.text) *(.text.*) } > ocm
    .rodata : { *(.rodata) *(.rodata.*) } > ocm
    .data : { *(.data) *(.data.*) } > ocm
    .bss : { *(.bss) *(.bss.*) *(COMMON) } > ocm
    .heap : { . = ALIGN(8); . += _HEAP_SIZE; } > ocm
    .stack : { . = ALIGN(8); . += _STACK_SIZE; _stack = .; } > ocm
}
