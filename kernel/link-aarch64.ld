TARGET(elf64-aarch64)
ENTRY(_start)

PHDRS {
    text PT_LOAD FLAGS((1 << 0) | (1 << 2)); /* r-x */
    rodata PT_LOAD FLAGS((1 << 2)); /* r-- */
    data PT_LOAD FLAGS((1 << 1) | (1 << 2)); /* rw- */
}

SECTIONS {
    . = 0xffffffff80000000;

    . = ALIGN(0x1000);

    .text : {
        *(.text)
        *(.text.*)
    } :text

    . = ALIGN(0x1000);

    .rodata : {
        *(.text)
        *(.text.*)
    } :rodata

    . = ALIGN(0x1000);

    .data : {
        *(.data)
        *(.data.*)
    } :data

    . = ALIGN(0x1000);

    .bss : {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } :data

    /DISCARD/ : {
        *(.eh_frame)
        *(.note)
        *(.note.*)
    }
}
