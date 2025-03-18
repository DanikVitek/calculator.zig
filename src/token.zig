const std = @import("std");
const util = @import("util.zig");

pub const Token = union(enum) {
    /// `(`
    l_paren,
    /// `)`
    r_paren,
    /// `+`
    plus,
    /// `-`
    minus,
    /// `*`
    star,
    /// `/`
    slash,
    /// `^`
    hat,
    /// `√`
    root: struct { unicode: bool },
    /// `|`
    bar,
    /// `!`
    bang,
    /// floating point number (possibly scientific notation)
    number: []const u8,

    pub fn format(self: Token, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        util.validateWriter(@TypeOf(writer));

        switch (self) {
            .l_paren => try writer.writeAll("("),
            .r_paren => try writer.writeAll(")"),
            .plus => try writer.writeAll("+"),
            .minus => try writer.writeAll("-"),
            .star => try writer.writeAll("*"),
            .slash => try writer.writeAll("/"),
            .hat => try writer.writeAll("^"),
            .root => |repr| if (repr.unicode) try writer.writeAll("√") else try writer.writeAll("//"),
            .bar => try writer.writeAll("|"),
            .bang => try writer.writeAll("!"),
            .number => |str| try writer.writeAll(str),
        }
    }

    pub fn width(self: Token) usize {
        return switch (self) {
            .l_paren => 1,
            .r_paren => 1,
            .plus => 1,
            .minus => 1,
            .star => 1,
            .slash => 1,
            .hat => 1,
            .root => |repr| if (repr.unicode) 1 else 2,
            .bar => 1,
            .bang => 1,
            .number => |str| str.len,
        };
    }
};

pub fn Spanned(comptime T: type) type {
    return struct {
        /// The token.
        token: T,
        /// Position of the start of the token in the input string in grapheme clusters.
        start_codepoint_pos: usize,
    };
}

pub const SpannedToken = Spanned(Token);
