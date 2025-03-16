const std = @import("std");
const Allocator = std.mem.Allocator;
const File = std.fs.File;

const calculator = @import("calculator_lib");

pub fn run(alloc: Allocator, stdin: File.Reader, stdout: File.Writer, stderr_w: File.Writer) !void {
    var line = std.ArrayList(u8).init(alloc);
    defer line.deinit();

    var buf_stderr = std.io.bufferedWriter(stderr_w);
    const stderr = buf_stderr.writer();

    while (true) {
        try stderr.print(">> ", .{});
        try buf_stderr.flush();

        try stdin.streamUntilDelimiter(line.writer(), '\n', null);
        defer line.clearRetainingCapacity();

        const lexer = calculator.Lexer.init(line.items) catch {
            try stderr.print("String is not a valid UTF-8\n", .{});
            continue;
        };

        var diag: calculator.Parser.Diagnostics = undefined;

        var parser = calculator.Parser.init(lexer, &diag) catch |err| {
            try printLexerError(
                line.items,
                &buf_stderr,
                err,
                diag.lexer,
            );
            continue;
        };

        const expr = parser.parse(alloc, &diag) catch |err| {
            try printParserError(
                line.items,
                &buf_stderr,
                err,
                diag,
            );
            continue;
        };
        defer expr.deinit();

        const result = expr.eval();
        try stdout.print("{d}\n", .{result});
    }
}

fn printParserError(
    line: []const u8,
    buf_stderr: *std.io.BufferedWriter(4096, File.Writer),
    err: calculator.Parser.Error,
    diag: calculator.Parser.Diagnostics,
) !void {
    const stderr = buf_stderr.writer();

    try stderr.print("Parser error:\n", .{});
    switch (err) {
        error.OutOfMemory => try stderr.print("Description: Ran out of available memory\n", .{}),
        error.InvalidCharacter => switch (diag) {
            .lexer => |lexer_diag| try printLexerError(
                line,
                buf_stderr,
                error.InvalidCharacter,
                lexer_diag,
            ),
            .float => |float| try stderr.print("\t{s}\nDescription: Invalid floating point number\n", .{float}),
            else => unreachable,
        },
        error.ExpectedDigit, error.ExpectedSignOrDigit => |e| try printLexerError(
            line,
            buf_stderr,
            @errorCast(e),
            diag.lexer,
        ),
        error.UnexpectedEOI => {
            try stderr.print("\t{s}\n\t", .{line});
            for (0..line.len) |_| {
                try stderr.print("~", .{});
            }
            try stderr.print("^\nDescription: Unexpected end of input\n", .{});
        },
        else => try stderr.print("{!}\n", .{err}),
    }

    try buf_stderr.flush();
}

fn printLexerError(
    line: []const u8,
    buf_stderr: *std.io.BufferedWriter(4096, File.Writer),
    err: calculator.Lexer.Error,
    diag: calculator.Lexer.Diagnostics,
) !void {
    const stderr = buf_stderr.writer();

    try stderr.print("Lexer error:\n", .{});
    const location = diag.location;
    try stderr.print("\t{s}\n\t", .{line});
    for (0..location) |_| {
        try stderr.print("~", .{});
    }
    try stderr.print("^", .{});
    for (location + 1..line.len) |_| {
        try stderr.print("~", .{});
    }
    try stderr.print("\nDescription: ", .{});
    switch (err) {
        error.InvalidCharacter => try stderr.print("Invalid character\n", .{}),
        error.ExpectedDigit => try stderr.print("Expected digit\n", .{}),
        error.ExpectedSignOrDigit => try stderr.print("Expected +, - or digit\n", .{}),
    }

    try buf_stderr.flush();
}
