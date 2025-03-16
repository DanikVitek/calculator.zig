const std = @import("std");
const Allocator = std.mem.Allocator;
const File = std.fs.File;

const calculator = @import("calculator_lib");

pub fn run(alloc: Allocator, stdin: File.Reader, stdout: File.Writer, stderr: File.Writer) !void {
    var line = std.ArrayList(u8).init(alloc);
    defer line.deinit();

    while (true) {
        try stderr.print(">> ", .{});

        try stdin.streamUntilDelimiter(line.writer(), '\n', null);
        defer line.clearRetainingCapacity();

        const lexer = calculator.Lexer.init(line.items) catch {
            try stderr.print("String is not a valid UTF-8\n", .{});
            continue;
        };
        var parser = calculator.Parser.init(lexer, null) catch |err| {
            try stderr.print("Lexer error: {!}\n", .{err});
            continue;
        };

        const expr = parser.parse(alloc, null) catch |err| {
            try stderr.print("Parser error: {!}\n", .{err});
            continue;
        };
        defer expr.deinit();

        const result = expr.eval();
        try stdout.print("{d}\n", .{result});
    }
}
