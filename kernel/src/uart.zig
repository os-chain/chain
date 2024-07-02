const std = @import("std");
const builtin = @import("builtin");

pub const Speed = enum(usize) {
    pub const base = 115200;

    @"115200",
    @"57600",
    @"38400",
    @"19200",
    @"9600",
    @"4800",

    /// Get the numeric baudrate
    pub fn getBaudrate(self: Speed) usize {
        return switch (self) {
            inline else => |s| std.fmt.parseInt(usize, @tagName(s), 10) catch unreachable,
        };
    }

    /// From a set baudrate. Returns null if invalid.
    pub fn fromBaudrate(baudrate: usize) ?Speed {
        inline for (comptime std.enums.values(Speed)) |speed| {
            if (baudrate == speed.getBaudrate()) {
                return speed;
            }
        }

        // Invalid baudrate
        return null;
    }

    /// Get the clock divisor for a specific speed
    pub fn getDivisor(self: Speed) u16 {
        return @intCast(@divExact(base, self.getBaudrate()));
    }
};

pub fn init(speed: Speed) void {
    switch (builtin.cpu.arch) {
        .x86_64 => {
            const cpu = @import("arch/x86_64/cpu.zig");

            // Set the speed
            cpu.outb(0x3F8 + 3, 0x80); // Enable DLAB
            cpu.outb(0x3F8, @intCast(speed.getDivisor() >> 8));
            cpu.outb(0x3F8, @truncate(speed.getDivisor()));
            cpu.outb(0x3F8 + 3, 0x0); // Disable DLAB

            cpu.outb(0x3F8 + 3, 0x03); // 8 bits, no parity, 1 stop bit, no break control

            cpu.outb(0x3F8 + 2, 0xc7); // FIFO enabled, clear both FIFOs, 14 bytes

            cpu.outb(0x3F8 + 4, 0x03); // RTS, DTS
        },
        .aarch64 => {},
        else => @compileError("Unsupported arch"),
    }
}

pub fn putc(char: u8) void {
    switch (builtin.cpu.arch) {
        .x86_64 => {
            const cpu = @import("arch/x86_64/cpu.zig");

            while (cpu.inb(0x3F8 + 5) & 0x20 == 0) {}
            cpu.outb(0x3F8, char);
        },
        .aarch64 => {
            @as(*volatile u8, @ptrFromInt(0x9000000)).* = char;
        },
        else => @compileError("Unsupported arch"),
    }
}
