const std = @import("std");
const Token = @import("token.zig").Token;

it: std.unicode.Utf8Iterator,
last_token_start: ?usize,

const Lexer = @This();

pub fn init(input: []const u8) error{InvalidUtf8}!Lexer {
    const view: std.unicode.Utf8View = try .init(input);
    return .{
        .it = view.iterator(),
        .last_token_start = null,
    };
}

pub const Error = error{
    InvalidCharacter,
    ExpectedDigit,
} || SkipExponentError;

pub const Diagnostics = struct {
    location: usize,
};

pub fn next(self: *Lexer, diag: ?*Diagnostics) Error!?Token {
    var start = self.it.i;

    var ok = true;
    defer if (ok) {
        self.last_token_start = start;
    };
    errdefer ok = false;

    errdefer self.it.i = start;
    errdefer if (diag) |d| {
        d.location = start;
    };

    return cases: switch (self.nextCodepoint() orelse return null) {
        ' ', '\t', '\n', '\r' => {
            self.skipWhitespace();
            start = self.it.i;
            continue :cases self.nextCodepoint() orelse return null;
        },
        '(' => .l_paren,
        ')' => .r_paren,
        '+' => .plus,
        '-' => .minus,
        '*' => .star,
        '/' => b: {
            if (self.peekCodepoint()) |peek| if (peek == '/') {
                _ = self.nextCodepoint().?;
                break :b .root;
            };
            break :b .slash;
        },
        '^' => .hat,
        '|' => .bar,
        '!' => .bang,
        '√' => .root,
        '0'...'9' => b: {
            self.skipDigits();

            if (self.peekCodepoint()) |peek| if (peek == '.') {
                _ = self.nextCodepoint().?;
                self.skipDigits();
            };

            try self.skipExponent();

            break :b .{ .number = self.it.bytes[start..self.it.i] };
        },
        '.' => b: {
            switch (self.peekCodepoint() orelse break :b Error.ExpectedDigit) {
                '0'...'9' => {
                    _ = self.nextCodepoint().?;
                    self.skipDigits();
                },
                else => break :b Error.ExpectedDigit,
            }

            try self.skipExponent();

            break :b .{ .number = self.it.bytes[start..self.it.i] };
        },
        else => Error.InvalidCharacter,
    };
}

fn skipWhitespace(self: *Lexer) void {
    while (self.peekCodepoint()) |c| switch (c) {
        ' ', '\t', '\n', '\r' => _ = self.nextCodepoint().?,
        else => break,
    };
}

fn skipDigits(self: *Lexer) void {
    while (self.peekCodepoint()) |c| switch (c) {
        '0'...'9' => _ = self.nextCodepoint().?,
        else => break,
    };
}

pub const SkipExponentError = error{
    ExpectedSignOrDigit,
    ExpectedDigit,
};

fn skipExponent(self: *Lexer) SkipExponentError!void {
    switch (self.peekCodepoint() orelse return) {
        'e', 'E' => _ = self.nextCodepoint().?,
        else => return,
    }

    switch (self.peekCodepoint() orelse return SkipExponentError.ExpectedSignOrDigit) {
        '+', '-' => {
            _ = self.nextCodepoint().?;
            switch (self.peekCodepoint() orelse return SkipExponentError.ExpectedDigit) {
                '0'...'9' => self.skipDigits(),
                else => return SkipExponentError.ExpectedDigit,
            }
        },
        '0'...'9' => self.skipDigits(),
        else => return SkipExponentError.ExpectedSignOrDigit,
    }
}

fn nextCodepoint(self: *Lexer) ?u21 {
    return self.it.nextCodepoint();
}

fn peekCodepoint(self: *Lexer) ?u21 {
    return decodeUtf8(self.it.peek(1));
}

fn decodeUtf8(slice: []const u8) ?u21 {
    if (slice.len == 0) {
        return null;
    }
    return std.unicode.utf8Decode(slice) catch unreachable;
}

const testing = std.testing;

test "different tokens" {
    const input = "1 + 2 * 3 / 4 - 5 ^ 6 | 7 // 8 ()";
    var lexer = try Lexer.init(input);
    const expected_tokens = [_]?Token{
        .{ .number = "1" },
        .plus,
        .{ .number = "2" },
        .star,
        .{ .number = "3" },
        .slash,
        .{ .number = "4" },
        .minus,
        .{ .number = "5" },
        .hat,
        .{ .number = "6" },
        .bar,
        .{ .number = "7" },
        .root,
        .{ .number = "8" },
        .l_paren,
        .r_paren,
        null,
        null,
    };
    for (expected_tokens) |expected_token| {
        var diag: Diagnostics = undefined;
        const token = lexer.next(&diag) catch |err| {
            std.debug.print("{!}: \"{s}\"\n", .{ err, input[diag.location..] });
            return err;
        };
        testing.expectEqualDeep(expected_token, token) catch |err| {
            std.debug.print(
                "expected: {?}\nactual: {?}\n",
                .{ expected_token, token },
            );
            return err;
        };
    }
}

test "number" {
    const cases = [_]struct {
        name: []const u8,
        input: []const u8,
    }{
        .{ .name = "integer", .input = "123" },
        .{ .name = "floating point w/o fraction", .input = "123." },
        .{ .name = "floating point w/ fraction", .input = "123.456" },
        .{ .name = "scientific notation", .input = "123.456e+789" },
        .{ .name = "scientific notation 2", .input = "123.456E+789" },
        .{ .name = "scientific notation 3", .input = "123.456e-789" },
        .{ .name = "scientific notation 4", .input = "123.456E-789" },
        .{ .name = "scientific notation 5", .input = "123.456e789" },
        .{ .name = "scientific notation 6", .input = "123.456E789" },
        .{ .name = "scientific notation 7", .input = "123E789" },
        .{ .name = "scientific notation 8", .input = "123.E789" },
    };

    inline for (cases) |case| {
        const input = case.input;
        var lexer = try Lexer.init(input);
        const expected_token: Token = .{
            .number = input,
        };
        var diag: Diagnostics = undefined;
        const token = lexer.next(&diag) catch |err| {
            std.debug.print(
                "test \"{s}\":\n{!}: \"{s}\"\n",
                .{ case.name, err, input[diag.location..] },
            );
            return err;
        };
        testing.expectEqualDeep(expected_token, token.?) catch |err| {
            std.debug.print(
                "test \"{s}\":\nexpected: {?}\nactual: {?}\n",
                .{ case.name, expected_token, token },
            );
            return err;
        };
    }
}

test "fail number" {
    const cases = [_]struct {
        name: []const u8,
        input: []const u8,
        expected_error: Error,
    }{
        .{ .name = "no digit after .", .input = ".", .expected_error = Error.ExpectedDigit },
        .{ .name = "no digit after e", .input = "123e", .expected_error = Error.ExpectedSignOrDigit },
        .{ .name = "no digit after e+", .input = "123e+", .expected_error = Error.ExpectedDigit },
        .{ .name = "no digit after e-", .input = "123e-", .expected_error = Error.ExpectedDigit },
        .{ .name = "no digit after E", .input = "123E", .expected_error = Error.ExpectedSignOrDigit },
        .{ .name = "no digit after E+", .input = "123E+", .expected_error = Error.ExpectedDigit },
        .{ .name = "no digit after E-", .input = "123E-", .expected_error = Error.ExpectedDigit },
    };

    inline for (cases) |case| {
        const input = case.input;
        var lexer = try Lexer.init(input);
        var diag: Diagnostics = undefined;
        const token = lexer.next(&diag);
        testing.expectError(case.expected_error, token) catch |err| {
            std.debug.print(
                "test \"{s}\":\nexpected: {!}\nactual: {!?}\n",
                .{ case.name, case.expected_error, token },
            );
            return err;
        };
    }
}
