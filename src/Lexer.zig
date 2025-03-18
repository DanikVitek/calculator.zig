const std = @import("std");
const Token = @import("token.zig").Token;
const SpannedToken = @import("token.zig").SpannedToken;

it: std.unicode.Utf8Iterator,
codepoint: usize,

const Lexer = @This();

pub fn init(input: []const u8) error{InvalidUtf8}!Lexer {
    const view: std.unicode.Utf8View = try .init(input);
    return .{
        .it = view.iterator(),
        .codepoint = 0,
    };
}

pub const Error = error{
    InvalidCharacter,
    ExpectedDigit,
} || SkipExponentError;

pub const Diagnostics = struct {
    location: usize,
};

pub fn next(self: *Lexer, diag: ?*Diagnostics, comptime spanned: bool) Error!?if (spanned) SpannedToken else Token {
    self.skipWhitespace();

    const start_byte = self.it.i;
    const start_codepoint = self.codepoint;

    errdefer self.it.i = start_byte;
    errdefer self.codepoint = start_codepoint;
    errdefer if (diag) |d| {
        d.location = start_codepoint;
    };

    return if (spanned) .{
        .token = (try self.nextImpl(start_byte)) orelse return null,
        .start_codepoint_pos = start_codepoint,
    } else self.nextImpl(start_byte);
}

fn nextImpl(self: *Lexer, start_byte: usize) Error!?Token {
    return switch (self.nextCodepoint() orelse return null) {
        '(' => .l_paren,
        ')' => .r_paren,
        '+' => .plus,
        '-' => .minus,
        '*' => .star,
        '/' => b: {
            if (self.peekCodepoint()) |peek| if (peek == '/') {
                _ = self.nextCodepoint().?;
                break :b .{ .root = .{ .unicode = false } };
            };
            break :b .slash;
        },
        '^' => .hat,
        '|' => .bar,
        '!' => .bang,
        '√' => .{ .root = .{ .unicode = true } },
        '0'...'9' => b: {
            self.skipDigits();

            if (self.peekCodepoint()) |peek| if (peek == '.') {
                _ = self.nextCodepoint().?;
                self.skipDigits();
            };

            try self.skipExponent();

            break :b .{ .number = self.it.bytes[start_byte..self.it.i] };
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

            break :b .{ .number = self.it.bytes[start_byte..self.it.i] };
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
    return if (self.it.nextCodepoint()) |c| b: {
        self.codepoint += 1;
        break :b c;
    } else null;
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
        const token = lexer.next(&diag, false) catch |err| {
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
        const token = lexer.next(&diag, false) catch |err| {
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
        const token = lexer.next(&diag, false);
        testing.expectError(case.expected_error, token) catch |err| {
            std.debug.print(
                "test \"{s}\":\nexpected: {!}\nactual: {!?}\n",
                .{ case.name, case.expected_error, token },
            );
            return err;
        };
    }
}
