const std = @import("std");

// pub const EvalError = DivisionError || RootError || FactorialError;

pub const Expression = union(enum) {
    real: f64,
    // complex: std.math.Complex(f64),
    unary: Unary,
    binary: Binary,

    pub const Unary = struct {
        op: Operator,
        expr: *const Expression,

        pub const Operator = enum {
            /// `+x`
            plus,
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
                .plus => self.expr.eval(),
                .minus => -self.expr.eval(),
                .factorial => factorial(self.expr.eval()),
                .sqrt => sqrt(self.expr.eval()),
            };
        }
    };

    pub const Binary = struct {
        op: Operator,
        left: *const Expression,
        right: *const Expression,

        pub const Operator = enum {
            /// `x + y`
            plus,
            /// `x - y`
            minus,
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
                .plus => self.left.eval() + self.right.eval(),
                .minus => self.left.eval() - self.right.eval(),
                .multiply => self.left.eval() * self.right.eval(),
                .divide => divide(self.left.eval(), self.right.eval()),
                .power => std.math.pow(self.left.eval(), self.right.eval()),
                .root => b: {
                    const n = self.left.eval();
                    const x = self.right.eval();
                    break :b root(x, n);
                },
            };
        }
    };

    pub fn eval(self: *const Expression) f64 { //EvalError!f64 {
        @setFloatMode(.strict);
        return switch (self.*) {
            .number => self.number,
            .unary => self.unary.eval(),
            .binary => self.binary.eval(),
        };
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
    return std.math.pow(x, 1 / n);
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

fn factorial(n: f64) f64 { //FactorialError!f64 {
    // if (n < 0) {
    //     return FactorialError.NegativeFactorial;
    // }
    if (n != @trunc(n)) {
        return std.math.nan(f64); //return FactorialError.NonIntegerFactorial; // TODO: Implement gamma function
    }
    var result: f64 = 1;
    var i: f64 = 2;
    while (i <= n) : (i += 1) {
        result *= i;
    }
    return result;
}
