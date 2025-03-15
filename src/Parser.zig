const std = @import("std");
const Lexer = @import("Lexer.zig");
const Token = @import("token.zig").Token;
const Expression = @import("ast.zig").Expression;

input: Lexer,
curr: ?Token = null,
peek: ?Token = null,

const Parser = @This();

pub fn init(input: Lexer) Parser {
    return .{ .input = input };
}

pub fn parse(self: *Parser) !?Expression {
    // std.fmt.parseFloat(f64, s: []const u8)

}
