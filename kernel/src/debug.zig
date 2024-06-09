const std = @import("std");
const uart = @import("uart.zig");

var last_newline: bool = false;

pub const Writer = struct {
    prefix_len: usize,

    fn writeFn(ctx: *const anyopaque, bytes: []const u8) error{}!usize {
        const self: *const Writer = @ptrCast(@alignCast(ctx));

        for (bytes) |char| {
            if (last_newline) {
                last_newline = false;
                for (0..self.prefix_len - 2) |_| uart.putc(' ');
                uart.putc('|');
                uart.putc(' ');
            }

            if (char == '\n') {
                last_newline = true;
            }

            uart.putc(char);
        }

        return bytes.len;
    }

    pub fn any(self: *const Writer) std.io.AnyWriter {
        return .{
            .context = self,
            .writeFn = writeFn,
        };
    }
};

pub fn logFn(comptime level: std.log.Level, comptime scope: @Type(.EnumLiteral), comptime fmt: []const u8, args: anytype) void {
    const prefix = std.fmt.comptimePrint("[{s}] ({s}) ", .{ @tagName(level), @tagName(scope) });

    var debug_writer = Writer{ .prefix_len = prefix.len };
    const writer = debug_writer.any();

    last_newline = false;
    std.fmt.format(writer, prefix ++ fmt ++ "\n", args) catch unreachable;
}
