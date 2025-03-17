//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("calculator_lib");
const repl = @import("repl.zig");

pub fn main() void {
    // var alloc_impl = if (@import("builtin").mode == .Debug) b: {
    //     const SmpAllocatorProvider = struct {
    //         pub inline fn allocator(_: @This()) std.mem.Allocator {
    //             return std.heap.smp_allocator;
    //         }
    //     };
    //     break :b std.mem.validationWrap(SmpAllocatorProvider{});
    // } else @compileError("impl is global");

    const alloc = if (@import("builtin").mode == .Debug)
        // alloc_impl.allocator()
        std.heap.c_allocator
    else
        std.heap.smp_allocator;

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.skip();

    const arg1 = args.next() orelse "repl";

    if (std.mem.eql(u8, arg1, "repl")) {
        return repl.run(alloc) catch |err| std.debug.panic("{!}", .{err});
    } else {
        std.debug.print("Unknown command: \"{s}\"\n", .{arg1});
        return std.process.exit(1);
    }
}
