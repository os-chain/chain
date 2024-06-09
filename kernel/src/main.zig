const std = @import("std");
const builtin = @import("builtin");
const debug = @import("debug.zig");
const uart = @import("uart.zig");

const log = std.log.scoped(.core);

pub const std_options = .{
    .logFn = debug.logFn,
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },
};

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    log.err("*Panic*\n{s}", .{msg});

    while (true) {}
}

export fn _start() callconv(.C) noreturn {
    init() catch |err| switch (err) {
        error.OutOfMemory => @panic("Ran out of memory while initializing the kernel"),
    };

    while (true) {}
}

pub fn init() !void {
    uart.init(uart.Speed.fromBaudrate(9600).?);

    log.debug("Initializing", .{});

    @panic("foo");
}
