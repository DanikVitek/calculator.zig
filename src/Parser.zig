const std = @import("std");
const Allocator = std.mem.Allocator;
const Tag = std.meta.Tag;
const EnumMap = std.EnumMap;

const Lexer = @import("Lexer.zig");
const Token = @import("token.zig").Token;
const Expression = @import("expr.zig").Expression;

input: Lexer,
curr: ?Token = null,
peek: ?Token = null,

pub const Error = Lexer.Error || std.fmt.ParseFloatError || Allocator.Error || error{
    MissingPrefixParseFn,
    MissingInfixParseFn,
    MissingPostfixParseFn,
    UnexpectedEOI,
};
pub const Diagnostics = union(enum) {
    lexer: Lexer.Diagnostics,
    float: []const u8,
    missing_parse_fn: struct {
        token: Tag(Token),
        kind: enum { prefix, infix, postfix },
        location: usize,
    },
    oom,
    expected_expression: struct {
        location: usize,
    },
    eoi,
};

const Parser = @This();

const PrefixParseFn = *const fn (*Parser, Allocator, ?*Diagnostics) Error!Expression;
const InfixParseFn = *const fn (*Parser, Allocator, Expression, ?*Diagnostics) Error!Expression;
const PostfixParseFn = *const fn (*Parser, Allocator, Expression, ?*Diagnostics) Error!Expression;

const prefix_parse_fns: EnumMap(Tag(Token), PrefixParseFn) = .init(.{
    .number = parseReal,
    .plus = parsePrefixExpression,
    .minus = parsePrefixExpression,
    .root = parsePrefixExpression,
});
const infix_parse_fns: EnumMap(Tag(Token), InfixParseFn) = .init(.{
    .plus = parseInfixExpression,
    .minus = parseInfixExpression,
    .star = parseInfixExpression,
    .slash = parseInfixExpression,
    .hat = parseInfixExpression,
    .root = parseInfixExpression,
});
const postfix_parse_fns: EnumMap(Tag(Token), PostfixParseFn) = .init(.{
    // .bang = parsePostfixExpression,
});

const Precedence = enum(u3) {
    lowest,
    sum,
    product,
    prefix,
    power,
    postfix,
};
const precedences: EnumMap(Tag(Token), Precedence) = .init(.{
    .plus = .sum,
    .minus = .sum,
    .star = .product,
    .slash = .product,
    .hat = .power,
    .root = .power,
    .bang = .postfix,
});

pub fn init(input: Lexer, diag: ?*Diagnostics) Lexer.Error!Parser {
    var parser: Parser = .{ .input = input };
    _ = try parser.advance(diag);
    _ = try parser.advance(diag);
    return parser;
}

pub inline fn parse(self: *Parser, alloc: Allocator, diag: ?*Diagnostics) Error!Expression {
    return self.parseExpression(alloc, .lowest, diag);
}

fn parseExpression(self: *Parser, alloc: Allocator, precedence: Precedence, diag: ?*Diagnostics) Error!Expression {
    const prefixParseFn = prefix_parse_fns.get(self.curr orelse {
        if (diag) |d| {
            d.* = .eoi;
        }
        return Error.UnexpectedEOI;
    }) orelse {
        if (diag) |d| {
            d.* = .{ .missing_parse_fn = .{
                .token = self.curr.?,
                .kind = .prefix,
                .location = self.input.last_token_start.?,
            } };
        }
        return Error.MissingPrefixParseFn;
    };

    var left = try prefixParseFn(self, alloc, diag);
    errdefer left.deinit(alloc);

    while (self.peek != null and @intFromEnum(precedence) < @intFromEnum(self.peekPrecedence())) {
        const infixParseFn = infix_parse_fns.get(self.peek.?) orelse {
            if (diag) |d| {
                d.* = .{ .missing_parse_fn = .{
                    .token = self.peek.?,
                    .kind = .infix,
                    .location = self.input.last_token_start.?,
                } };
            }
            return Error.MissingInfixParseFn;
        };

        try self.advance(diag);

        left = try infixParseFn(self, alloc, left, diag);
    }

    return left;
}

fn parseReal(self: *Parser, diag: ?*Diagnostics) Error!Expression {
    const value_str = self.curr.?.number;
    const value = std.fmt.parseFloat(f64, value_str) catch |err| {
        if (diag) |d| {
            d.* = .{ .float = value_str };
        }
        return err;
    };
    return .{ .real = value };
}

fn parsePrefixExpression(self: *Parser, alloc: Allocator, diag: ?*Diagnostics) Error!Expression {
    const op: Expression.Unary.Operator = switch (self.curr.?) {
        .plus => {
            try self.advance(diag);
            return self.parseExpression(alloc, .prefix, diag);
        },
        .minus => .minus,
        .root => .sqrt,
        else => unreachable,
    };
    try self.advance(diag);

    const right = alloc.create(Expression) catch |err| {
        if (diag) |d| {
            d.* = .oom;
        }
        return err;
    };
    errdefer alloc.destroy(right);

    right.* = try self.parseExpression(alloc, .prefix, diag);

    return .{ .unary = .{ .op = op, .expr = right } };
}

fn parseInfixExpression(self: *Parser, alloc: Allocator, left: Expression, diag: ?*Diagnostics) Error!Expression {
    const op: Expression.Binary.Operator = switch (self.curr.?) {
        .plus => .add,
        .minus => .subtract,
        .star => .multiply,
        .slash => .divide,
        .hat => .power,
        .root => .root,
        else => unreachable,
    };

    const left_ptr = alloc.create(Expression) catch |err| {
        if (diag) |d| {
            d.* = .oom;
        }
        return err;
    };
    errdefer alloc.destroy(left_ptr);

    left_ptr.* = left;
    errdefer left.deinit(alloc);

    const precedence = self.currPrecedence();
    try self.advance(diag);

    const right_ptr = alloc.create(Expression) catch |err| {
        if (diag) |d| {
            d.* = .oom;
        }
        return err;
    };
    errdefer alloc.destroy(right_ptr);

    right_ptr.* = try self.parseExpression(alloc, precedence, diag);

    return .{ .binary = .{
        .op = op,
        .left = left_ptr,
        .right = right_ptr,
    } };
}

fn advance(self: *Parser, diag: ?*Diagnostics) Lexer.Error!void {
    self.curr = self.peek;
    var lexer_diag: Lexer.Diagnostics = undefined;
    self.peek = self.input.next(if (diag != null) &lexer_diag else null) catch |err| {
        if (diag) |d| {
            d.* = .{ .lexer = lexer_diag };
        }
        return err;
    };
}

inline fn currPrecedence(self: *const Parser) Precedence {
    return precedences.get(self.curr.?) orelse .lowest;
}

inline fn peekPrecedence(self: *const Parser) Precedence {
    return precedences.get(self.peek.?) orelse .lowest;
}

inline fn currIs(self: *const Parser, token: Tag(Token)) bool {
    return self.curr == token;
}

inline fn peekIs(self: *const Parser, token: Tag(Token)) bool {
    return self.peek == token;
}

fn checkAdvance(self: *Parser, token: Tag(Token), diag: ?*Diagnostics) Lexer.Error!bool {
    return if (self.peekIs(token)) b: {
        try self.advance(diag);
        break :b true;
    } else false;
}

const testing = std.testing;

test "parse float" {
    std.debug.print("\n", .{});

    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);

    const cases = [_]struct {
        name: []const u8,
        input: []const u8,
        expected: f64,
    }{
        .{ .name = "positive integer", .input = "42", .expected = 42.0 },
        .{ .name = "negative integer", .input = "-42", .expected = -42.0 },
        .{ .name = "number and dot", .input = "42.", .expected = 42.0 },
        .{ .name = "positive float", .input = "3.14", .expected = 3.14 },
        .{ .name = "negative float", .input = "-3.14", .expected = -3.14 },
        .{ .name = "positive float w/ exponent", .input = "3.14e2", .expected = 314.0 },
        .{ .name = "float w/ dot and exponent", .input = "3.e2", .expected = 300.0 },
        .{ .name = "negative float w/ exponent", .input = "-3.14e2", .expected = -314.0 },
        .{ .name = "positive float w/ negative exponent", .input = "3.14e-2", .expected = 0.0314 },
        .{ .name = "negative float w/ negative exponent", .input = "-3.14e-2", .expected = -0.0314 },
    };

    inline for (cases) |case| {
        defer arena.deinit();

        const input = try Lexer.init(case.input);
        var diag: Diagnostics = undefined;
        var parser = Parser.init(input, &diag) catch |err| {
            std.debug.print(
                "{s}:\n{!}: {any}\n",
                .{ case.name, err, diag },
            );
            return err;
        };
        const result = parser.parse(arena.allocator(), &diag) catch |err| {
            std.debug.print(
                "{s}\n{!}: {any}\n",
                .{ case.name, err, diag },
            );
            return err;
        };
        testing.expectApproxEqAbs(case.expected, result.real, 0.000001) catch |err| {
            std.debug.print(
                "{s}\nexpected: {1d} ({1e})\nactual: {2d} ({2e})\n",
                .{ case.name, case.expected, result.real },
            );
            return err;
        };
    }
}

test "parse expression" {
    std.debug.print("\n", .{});

    const input = "3 + 4 * 2 - 1 / 5 ^ 2";

    const lexer = try Lexer.init(input);

    var diag: Diagnostics = undefined;
    var parser = Parser.init(lexer, &diag) catch |err| {
        std.debug.print("{!}: {any}\n", .{ err, diag });
        return err;
    };

    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    const alloc = arena.allocator();

    const result = parser.parse(alloc, &diag) catch |err| {
        std.debug.print("{!}: {any}\n", .{ err, diag });
        return err;
    };
    defer result.deinit(alloc);

    const expected: Expression = .{ .binary = .{
        .op = .subtract,
        .left = &.{ .binary = .{
            .op = .add,
            .left = &.{ .real = 3.0 },
            .right = &.{ .binary = .{
                .op = .multiply,
                .left = &.{ .real = 4.0 },
                .right = &.{ .real = 2.0 },
            } },
        } },
        .right = &.{ .binary = .{
            .op = .divide,
            .left = &.{ .real = 1.0 },
            .right = &.{ .binary = .{
                .op = .power,
                .left = &.{ .real = 5.0 },
                .right = &.{ .real = 2.0 },
            } },
        } },
    } };

    testing.expectEqualDeep(expected, result) catch |err| {
        std.debug.print("expected: {any}\nactual: {any}\n", .{ expected, result });
        return err;
    };
}
