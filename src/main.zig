//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("calculator_lib");
const repl = @import("repl.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.skip();

    const arg1 = args.next() orelse "repl";

    const stderr_file = std.io.getStdErr();
    defer stderr_file.close();
    const stderr = stderr_file.writer();

    if (std.mem.eql(u8, arg1, "repl")) {
        const stdout_file = std.io.getStdOut();
        defer stdout_file.close();
        const stdout = stdout_file.writer();

        const stdin_file = std.io.getStdIn();
        defer stdin_file.close();
        const stdin = stdin_file.reader();

        return repl.run(alloc, stdin, stdout, stderr);
    } else {
        try stderr.print("Unknown command: \"{s}\"\n", .{arg1});
        return std.process.exit(1);
    }
}
