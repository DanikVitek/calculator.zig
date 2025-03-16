const std = @import("std");

// pub const EvalError = DivisionError || RootError || FactorialError;

pub const Expression = union(enum) {
    real: f64,
    // complex: std.math.Complex(f64),
    unary: Unary,
    binary: Binary,

    threadlocal var indent: usize = 0;

    pub const Unary = struct {
        op: Operator,
        expr: *const Expression,

        pub const Operator = enum {
            /// `-x`
            minus,
            /// `x!`
            factorial,
            /// `√x`
            sqrt,
            /// `|x|`
            abs,
        };

        pub fn eval(self: *const Unary) f64 { //EvalError!f64 {
            @setFloatMode(.strict);
            return switch (self.op) {
                .minus => -self.expr.eval(),
                .factorial => factorial(self.expr.eval()),
                .sqrt => sqrt(self.expr.eval()),
                .abs => b: {
                    const x = self.expr.eval();
                    break :b if (x < 0) -x else x;
                },
            };
        }

        pub fn deinit(self: *const Unary, alloc: std.mem.Allocator) void {
            defer {
                alloc.destroy(self.expr);
                printIndent();
                std.debug.print("destroyed unary branch\n", .{});
            }
            self.expr.deinit(alloc);
        }
    };

    pub const Binary = struct {
        op: Operator,
        left: *const Expression,
        right: *const Expression,

        pub const Operator = enum {
            /// `x + y`
            add,
            /// `x - y`
            subtract,
            /// `x * y`
            multiply,
            /// `x / y`
            divide,
            /// `x ^ y`
            power,
            /// `n √ x`
            root,
        };

        pub fn eval(self: *const Binary) f64 { //EvalError!f64 {
            @setFloatMode(.strict);
            return switch (self.op) {
                .add => self.left.eval() + self.right.eval(),
                .subtract => self.left.eval() - self.right.eval(),
                .multiply => self.left.eval() * self.right.eval(),
                .divide => divide(self.left.eval(), self.right.eval()),
                .power => std.math.pow(f64, self.left.eval(), self.right.eval()),
                .root => b: {
                    const n = self.left.eval();
                    const x = self.right.eval();
                    break :b root(x, n);
                },
            };
        }

        pub fn deinit(self: *const Binary, alloc: std.mem.Allocator) void {
            defer {
                alloc.destroy(self.left);
                printIndent();
                std.debug.print("destroyed left branch\n", .{});
            }
            defer {
                alloc.destroy(self.right);
                printIndent();
                std.debug.print("destroyed right branch\n", .{});
            }
            printIndent();
            std.debug.print("left:\n", .{});
            self.left.deinit(alloc);
            printIndent();
            std.debug.print("right:\n", .{});
            self.right.deinit(alloc);
        }
    };

    pub fn eval(self: *const Expression) f64 { //EvalError!f64 {
        @setFloatMode(.strict);
        return switch (self.*) {
            .real => |n| n,
            inline else => |e| e.eval(),
        };
    }

    pub fn deinit(self: *const Expression, alloc: std.mem.Allocator) void {
        printIndent();
        switch (self.*) {
            .real => |x| std.debug.print("deinit-ed real ({d})\n", .{x}),
            inline else => |e, tag| {
                std.debug.print("deinit-ing " ++ @tagName(tag) ++ " ({s})\n", .{@tagName(e.op)});
                defer {
                    printIndent();
                    std.debug.print("deinit-ed " ++ @tagName(tag) ++ " ({s})\n", .{@tagName(e.op)});
                }
                indent += 4;
                defer indent -= 4;
                e.deinit(alloc);
            },
        }
    }

    fn printIndent() void {
        for (0..indent) |_| {
            std.debug.print(" ", .{});
        }
    }
};

// pub const DivisionError = error{DivisionByZero};

fn divide(x: f64, y: f64) f64 { //DivisionError!f64 {
    // if (y == 0) {
    //     return DivisionError.DivisionByZero;
    // }
    return x / y;
}

// pub const RootError = error{NegativeArgument};

fn root(x: f64, n: f64) f64 { //RootError!f64 {
    // if (x < 0) {
    //     return RootError.NegativeArgument;
    // }
    if (n == 2) {
        return sqrt(x);
    }
    return std.math.pow(f64, x, 1 / n);
}

fn sqrt(x: f64) f64 { //RootError!f64 {
    // if (x < 0) {
    //     return error.NegativeArgument;
    // }
    return std.math.sqrt(x);
}

// pub const FactorialError = error{
//     NegativeFactorial,
//     NonIntegerFactorial,
// };

fn factorial(x: f64) f64 { //FactorialError!f64 {
    return std.math.gamma(f64, x + 1);
}

test "3 + 4 * 2 - 1 / 5 ^ 2" {
    const expr: Expression = .{ .binary = .{
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
    const result = expr.eval();
    try std.testing.expectApproxEqAbs(
        3.0 + 4.0 * 2.0 - 1.0 / std.math.pow(f64, 5, 2),
        result,
        0.0001,
    );
}
