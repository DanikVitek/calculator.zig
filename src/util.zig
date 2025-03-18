const std = @import("std");

pub fn validateWriter(comptime Writer: type) void {
    const err_msg = "Expected writer to have a `writeAll` method that accepts `[]const u8` and returns `!void`";
    if (std.meta.hasMethod(Writer, "writeAll")) {
        const method_info = @typeInfo(@TypeOf(@field(Writer, "writeAll"))).@"fn";
        if (method_info.params[1].type != []const u8 or method_info.return_type == null) {
            @compileError(err_msg);
        }
        switch (@typeInfo(method_info.return_type.?)) {
            .error_union => |error_union| if (error_union.payload != void) @compileError(err_msg),
            else => @compileError(err_msg),
        }
    } else {
        @compileError(err_msg);
    }
}
