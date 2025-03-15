const std = @import("std");

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
    root,
    /// `|`
    bar,
    /// `!`
    bang,
    /// floating point number (possibly scientific notation)
    number: []const u8,

    pub fn format(self: Token, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        switch (self) {
            .l_paren => try writer.writeAll("("),
            .r_paren => try writer.writeAll(")"),
            .plus => try writer.writeAll("+"),
            .minus => try writer.writeAll("-"),
            .star => try writer.writeAll("*"),
            .slash => try writer.writeAll("/"),
            .hat => try writer.writeAll("^"),
            .root => try writer.writeAll("√"),
            .bar => try writer.writeAll("|"),
            .bang => try writer.writeAll("!"),
            .number => {
                if (std.mem.eql(u8, fmt, "s")) {
                    try writer.writeAll(self.number);
                } else {
                    try writer.print("\"{s}\"", .{self.number});
                }
            },
        }
    }
};
