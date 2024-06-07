export fn _start() callconv(.C) noreturn {
    asm volatile (
        \\mov $'x', %al
        \\out %al, $0xe9
        ::: "al");

    while (true) {}
}
