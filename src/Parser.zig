const std = @import("std");
const Allocator = std.mem.Allocator;
const Tag = std.meta.Tag;
const EnumMap = std.EnumMap;

const root = @import("root.zig");
const Lexer = root.Lexer;
const Token = root.Token;
const Ast = root.Ast;
const Expression = root.Expression;

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
    var expr: Expression = .init(alloc);
    errdefer expr.deinit();

    _ = try self.parseExpression(&expr, .lowest, diag);

    return expr;
}

pub inline fn parseCapacity(self: *Parser, alloc: Allocator, cap: usize, diag: ?*Diagnostics) Error!Expression {
    var expr: Expression = try .initCapacity(alloc, cap);
    errdefer expr.deinit();

    _ = try self.parseExpression(&expr, .lowest, diag);

    return expr;
}

fn parseExpression(self: *Parser, expr: *Expression, precedence: Precedence, diag: ?*Diagnostics) Error!usize {
    var left = try self.dispatchPrefixParser(expr, diag);

    while (self.peek != null and @intFromEnum(precedence) < @intFromEnum(self.peekPrecedence())) {
        left = try self.dispatchInfixParser(expr, left, diag);
    }

    return left;
}

fn dispatchPrefixParser(self: *Parser, expr: *Expression, diag: ?*Diagnostics) Error!usize {
    const curr = self.curr orelse {
        if (diag) |d| {
            d.* = .eoi;
        }
        return Error.UnexpectedEOI;
    };
    return switch (curr) {
        .number => self.parseReal(expr, diag),
        .plus, .minus, .root => self.parsePrefixExpression(expr, diag),
        else => b: {
            if (diag) |d| {
                d.* = .{ .missing_parse_fn = .{
                    .token = curr,
                    .kind = .prefix,
                    .location = self.input.last_token_start.?,
                } };
            }
            break :b Error.MissingPrefixParseFn;
        },
    };
}

fn dispatchInfixParser(self: *Parser, expr: *Expression, left: usize, diag: ?*Diagnostics) Error!usize {
    return switch (self.peek.?) {
        .plus, .minus, .star, .slash, .hat, .root => b: {
            try self.advance(diag);
            break :b self.parseInfixExpression(expr, left, diag);
        },
        .bang => b: {
            try self.advance(diag);
            break :b self.parsePostfixExpression(expr, left, diag);
        },
        else => b: {
            if (diag) |d| {
                d.* = .{ .missing_parse_fn = .{
                    .token = self.peek.?,
                    .kind = .infix,
                    .location = self.input.last_token_start.?,
                } };
            }
            break :b Error.MissingInfixParseFn;
        },
    };
}

fn parseReal(self: *Parser, expr: *Expression, diag: ?*Diagnostics) Error!usize {
    const value_str = self.curr.?.number;
    const value = std.fmt.parseFloat(f64, value_str) catch |err| {
        if (diag) |d| {
            d.* = .{ .float = value_str };
        }
        return err;
    };
    expr.nodes.append(.{ .real = value }) catch |err| {
        if (diag) |d| {
            d.* = .oom;
        }
        return err;
    };
    return expr.nodes.items.len - 1;
}

fn parsePrefixExpression(self: *Parser, expr: *Expression, diag: ?*Diagnostics) Error!usize {
    const op: Expression.Node.Unary.Operator = switch (self.curr.?) {
        .plus => {
            try self.advance(diag);
            return self.parseExpression(expr, .prefix, diag);
        },
        .minus => .minus,
        .root => .sqrt,
        else => unreachable,
    };
    try self.advance(diag);

    const right = try self.parseExpression(expr, .prefix, diag);
    expr.nodes.append(.{ .unary = .{ .op = op, .expr = right } }) catch |err| {
        if (diag) |d| {
            d.* = .oom;
        }
        return err;
    };

    return expr.nodes.items.len - 1;
}

fn parseInfixExpression(
    self: *Parser,
    expr: *Expression,
    left: usize,
    diag: ?*Diagnostics,
) Error!usize {
    const op: Expression.Node.Binary.Operator = switch (self.curr.?) {
        .plus => .add,
        .minus => .subtract,
        .star => .multiply,
        .slash => .divide,
        .hat => .power,
        .root => .root,
        else => unreachable,
    };

    const precedence = self.currPrecedence();
    try self.advance(diag);

    const right = try self.parseExpression(expr, precedence, diag);
    expr.nodes.append(.{ .binary = .{
        .op = op,
        .left = left,
        .right = right,
    } }) catch |err| {
        if (diag) |d| {
            d.* = .oom;
        }
        return err;
    };

    return expr.nodes.items.len - 1;
}

fn parsePostfixExpression(
    self: *Parser,
    expr: *Expression,
    left: usize,
    diag: ?*Diagnostics,
) Error!usize {
    const op: Expression.Node.Unary.Operator = switch (self.curr.?) {
        .bang => .factorial,
        else => unreachable,
    };

    expr.nodes.append(.{ .unary = .{
        .op = op,
        .expr = left,
    } }) catch |err| {
        if (diag) |d| {
            d.* = .oom;
        }
        return err;
    };

    return expr.nodes.items.len - 1;
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
        const input = try Lexer.init(case.input);
        var diag: Diagnostics = undefined;
        var parser = Parser.init(input, &diag) catch |err| {
            std.debug.print(
                "{s}:\n{!}: {any}\n",
                .{ case.name, err, diag },
            );
            return err;
        };
        const result = parser.parse(testing.allocator, &diag) catch |err| {
            std.debug.print(
                "{s}\n{!}: {any}\n",
                .{ case.name, err, diag },
            );
            return err;
        };
        defer result.deinit();
        const result_value = result.nodes.items[0].real;
        testing.expectApproxEqAbs(case.expected, result_value, 0.000001) catch |err| {
            std.debug.print(
                "{s}\nexpected: {1d} ({1e})\nactual: {2d} ({2e})\n",
                .{ case.name, case.expected, result_value },
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

    const alloc = testing.allocator;

    const result = parser.parse(alloc, &diag) catch |err| {
        std.debug.print("{!}: {any}\n", .{ err, diag });
        return err;
    };
    defer result.deinit();

    const expected: [11]Expression.Node = .{
        .{ .real = 3.0 }, // 0
        .{ .real = 4.0 }, // 1
        .{ .real = 2.0 }, // 2
        .{ .binary = .{
            .op = .multiply,
            .left = 1,
            .right = 2,
        } }, // 3
        .{ .binary = .{
            .op = .add,
            .left = 0,
            .right = 3,
        } }, // 4
        .{ .real = 1.0 }, // 5
        .{ .real = 5.0 }, // 6
        .{ .real = 2.0 }, // 7
        .{ .binary = .{
            .op = .power,
            .left = 6,
            .right = 7,
        } }, // 8
        .{ .binary = .{
            .op = .divide,
            .left = 5,
            .right = 8,
        } }, // 9
        .{ .binary = .{
            .op = .subtract,
            .left = 4,
            .right = 9,
        } }, // 10
    };

    testing.expectEqualDeep(expected[0..], result.nodes.items) catch |err| {
        std.debug.print("expected: {any}\nactual: {any}\n", .{ expected, result.nodes.items });
        return err;
    };
}
