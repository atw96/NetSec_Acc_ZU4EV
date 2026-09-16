ENTRY(_vec)
SECTIONS
{
    . = 0xFFFF0000;
    .text : {
        KEEP(*(.vectors))
        *(.text*)
        *(.rodata*)
        *(.data*)
    }
    /DISCARD/ : { *(.note*) *(.comment) *(.eh_frame*) }
}
