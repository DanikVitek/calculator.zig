const std = @import("std");
const Allocator = std.mem.Allocator;
const File = std.fs.File;
const ArrayList = std.ArrayList;

const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const Model = @import("repl/widget.zig").Model;

pub fn run(alloc: Allocator) !void {
    var app = try vxfw.App.init(alloc);
    defer app.deinit();

    const model = try Model.init(alloc, &app.vx.unicode);
    defer {
        model.deinit();
        alloc.destroy(model);
    }

    try app.run(model.widget(), .{});
}
