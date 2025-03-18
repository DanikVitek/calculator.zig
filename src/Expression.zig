const std = @import("std");
const Allocator = std.mem.Allocator;

// pub const EvalError = DivisionError || RootError || FactorialError;

nodes: std.ArrayList(Node),

const Expression = @This();

pub fn init(alloc: Allocator) Expression {
    return Expression{ .nodes = .init(alloc) };
}
pub fn initCapacity(alloc: Allocator, num: usize) Allocator.Error!Expression {
    return Expression{ .nodes = try .initCapacity(alloc, num) };
}

pub const Float = f64;

pub const Node = union(enum) {
    real: Float,
    // complex: std.math.Complex(Float),
    unary: Unary,
    binary: Binary,

    threadlocal var indent: usize = 0;

    pub const Unary = struct {
        op: Operator,
        expr: usize,

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

        pub fn eval(self: *const Unary, nodes: []const Node) Float { //EvalError!Float {
            @setFloatMode(.strict);
            return switch (self.op) {
                .minus => -nodes[self.expr].eval(nodes),
                .factorial => factorial(nodes[self.expr].eval(nodes)),
                .sqrt => sqrt(nodes[self.expr].eval(nodes)),
                .abs => b: {
                    const x = nodes[self.expr].eval(nodes);
                    break :b if (x < 0) -x else x;
                },
            };
        }
    };

    pub const Binary = struct {
        op: Operator,
        left: usize,
        right: usize,

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

        pub fn eval(self: *const Binary, nodes: []const Node) Float { //EvalError!Float {
            @setFloatMode(.strict);
            return switch (self.op) {
                .add => nodes[self.left].eval(nodes) + nodes[self.right].eval(nodes),
                .subtract => nodes[self.left].eval(nodes) - nodes[self.right].eval(nodes),
                .multiply => nodes[self.left].eval(nodes) * nodes[self.right].eval(nodes),
                .divide => divide(nodes[self.left].eval(nodes), nodes[self.right].eval(nodes)),
                .power => std.math.pow(Float, nodes[self.left].eval(nodes), nodes[self.right].eval(nodes)),
                .root => b: {
                    const n = nodes[self.left].eval(nodes);
                    const x = nodes[self.right].eval(nodes);
                    break :b root(x, n);
                },
            };
        }
    };

    pub fn eval(self: *const Node, nodes: []const Node) Float { //EvalError!Float {
        @setFloatMode(.strict);
        return switch (self.*) {
            .real => |n| n,
            inline else => |e| e.eval(nodes),
        };
    }

    fn printIndent() void {
        for (0..indent) |_| {
            std.debug.print(" ", .{});
        }
    }
};

pub fn eval(self: *const Expression) Float {
    return self.nodes.getLast().eval(self.nodes.items);
}

pub fn deinit(self: Expression) void {
    self.nodes.deinit();
}

// pub const DivisionError = error{DivisionByZero};

fn divide(x: Float, y: Float) Float { //DivisionError!Float {
    // if (y == 0) {
    //     return DivisionError.DivisionByZero;
    // }
    return x / y;
}

// pub const RootError = error{NegativeArgument};

fn root(x: Float, n: Float) Float { //RootError!Float {
    // if (x < 0) {
    //     return RootError.NegativeArgument;
    // }
    if (n == 2) {
        return sqrt(x);
    }
    return std.math.pow(Float, x, 1 / n);
}

fn sqrt(x: Float) Float { //RootError!Float {
    // if (x < 0) {
    //     return error.NegativeArgument;
    // }
    return std.math.sqrt(x);
}

// pub const FactorialError = error{
//     NegativeFactorial,
//     NonIntegerFactorial,
// };

fn factorial(x: Float) Float { //FactorialError!Float {
    return std.math.gamma(Float, x + 1);
}

test "3 + 4 * 2 - 1 / 5 ^ 2" {
    var buf: [@sizeOf([11]Expression.Node)]u8 = undefined;
    var buf_alloc = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = buf_alloc.allocator();

    const expr: Expression = b: {
        var expr: Expression = try .initCapacity(alloc, 11);
        expr.nodes.appendAssumeCapacity(.{ .real = 4.0 }); // 0
        expr.nodes.appendAssumeCapacity(.{ .real = 2.0 }); // 1
        expr.nodes.appendAssumeCapacity(.{ .binary = .{
            .op = .multiply,
            .left = 0,
            .right = 1,
        } }); // 2
        expr.nodes.appendAssumeCapacity(.{ .real = 3.0 }); // 3
        expr.nodes.appendAssumeCapacity(.{ .binary = .{
            .op = .add,
            .left = 3,
            .right = 2,
        } }); // 4
        expr.nodes.appendAssumeCapacity(.{ .real = 5.0 }); // 5
        expr.nodes.appendAssumeCapacity(.{ .real = 2.0 }); // 6
        expr.nodes.appendAssumeCapacity(.{ .binary = .{
            .op = .power,
            .left = 5,
            .right = 6,
        } }); // 7
        expr.nodes.appendAssumeCapacity(.{ .real = 1.0 }); // 8
        expr.nodes.appendAssumeCapacity(.{ .binary = .{
            .op = .divide,
            .left = 8,
            .right = 7,
        } }); // 9
        expr.nodes.appendAssumeCapacity(.{ .binary = .{
            .op = .subtract,
            .left = 4,
            .right = 9,
        } }); // 10
        break :b expr;
    };
    const result = expr.eval();
    try std.testing.expectApproxEqAbs(
        3.0 + 4.0 * 2.0 - 1.0 / std.math.pow(Float, 5, 2),
        result,
        0.0001,
    );
}
