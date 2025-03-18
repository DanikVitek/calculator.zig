const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const calculator = @import("calculator_lib");
const ArrayDeque = @import("../deque.zig").ArrayDeque;
const LineIterator = @import("../LineIterator.zig");

const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const arrows_widget = @import("simple.zig").arrows_widget;

deque: ArrayDeque(Entry),
selected_item: ?usize,

const History = @This();

pub const Entry = struct {
    input: []const u8,
    result: []const u8,

    pub fn init(input: []const u8, alloc: Allocator) !Entry {
        var err_str: ArrayList(u8) = .init(alloc);
        defer err_str.deinit();

        const lexer = calculator.Lexer.init(input) catch {
            try err_str.writer().print("String is not a valid UTF-8", .{});
            return .{
                .input = input,
                .result = try err_str.toOwnedSlice(),
            };
        };

        var diag: calculator.Parser.Diagnostics = undefined;

        var parser = calculator.Parser.init(lexer, &diag) catch |err| {
            try printLexerError(
                input,
                err_str.writer(),
                err,
                diag.lexer,
            );
            return .{
                .input = input,
                .result = try err_str.toOwnedSlice(),
            };
        };

        const expr = parser.parse(alloc, &diag) catch |err| {
            try printParserError(
                input,
                err_str.writer(),
                err,
                diag,
            );
            return .{
                .input = input,
                .result = try err_str.toOwnedSlice(),
            };
        };
        defer expr.deinit();

        const result = expr.eval();

        var buf: [std.fmt.format_float.min_buffer_size]u8 = undefined;

        const result_str: []const u8 = std.fmt.formatFloat(
            &buf,
            result,
            .{ .mode = .decimal },
        ) catch std.fmt.formatFloat(
            &buf,
            result,
            .{ .mode = .scientific },
        ) catch unreachable;

        return .{
            .input = input,
            .result = try alloc.dupe(u8, result_str),
        };
    }

    pub fn deinit(self: Entry, alloc: Allocator) void {
        alloc.free(self.input);
        alloc.free(self.result);
    }

    pub fn clone(self: *const Entry, alloc: Allocator) Allocator.Error!Entry {
        return .{
            .input = try alloc.dupe(u8, self.input),
            .result = try alloc.dupe(u8, self.result),
        };
    }

    pub fn height(self: *const Entry) usize {
        return self.inputHeight() + self.resultHeight();
    }

    pub fn width(self: *const Entry, ctx: vxfw.DrawContext) usize {
        return @max(self.inputWidth(ctx), self.resultWidth(ctx));
    }

    fn inputHeight(self: *const Entry) usize {
        return std.mem.count(u8, self.input, "\n") + 1;
    }

    fn resultHeight(self: *const Entry) usize {
        return std.mem.count(u8, self.result, "\n") + 1;
    }

    fn inputWidth(self: *const Entry, ctx: vxfw.DrawContext) usize {
        var line_iter: LineIterator = .init(self.input);
        var max_width: usize = 0;
        while (line_iter.next()) |line| {
            max_width = @max(max_width, ctx.stringWidth(line));
        }
        return max_width;
    }

    fn resultWidth(self: *const Entry, ctx: vxfw.DrawContext) usize {
        var line_iter: LineIterator = .init(self.result);
        var max_width: usize = 0;
        while (line_iter.next()) |line| {
            max_width = @max(max_width, ctx.stringWidth(line));
        }
        return max_width;
    }

    fn printParserError(
        line: []const u8,
        writer: ArrayList(u8).Writer,
        err: calculator.Parser.Error,
        diag: calculator.Parser.Diagnostics,
    ) !void {
        try writer.writeAll("Parser error:\n");
        switch (err) {
            error.OutOfMemory => return @as(Allocator.Error, @errorCast(err)),
            error.InvalidCharacter => try printLexerError(
                line,
                writer,
                error.InvalidCharacter,
                diag.lexer,
            ),
            error.ExpectedDigit, error.ExpectedSignOrDigit => |e| try printLexerError(
                line,
                writer,
                @errorCast(e),
                diag.lexer,
            ),
            error.UnexpectedEOI => {
                try writer.print("\t{s}\n\t", .{line});
                try writer.writeByteNTimes('~', diag.eoi.location);
                try writer.writeAll("^\nDescription: Unexpected end of input");
            },
            error.UnexpectedToken => {
                try writer.print("\t{s}\n\t", .{line});

                try writer.writeByteNTimes('~', diag.unexpected.start_codepoint_pos);
                try writer.writeByteNTimes('^', diag.unexpected.token.width());
                try writer.writeByteNTimes('~', line.len - (diag.unexpected.start_codepoint_pos + diag.unexpected.token.width()));

                try writer.print("\nDescription: Unexpected `{s}` token", .{diag.unexpected.token});
            },
            error.ExpectedGroupClosingToken => {
                try writer.print("\t{s}\n\t", .{line});
                try writer.writeByteNTimes('~', diag.expected_group_closing_token.start_codepoint_pos);
                try writer.print("^\nDescription: Expected `{s}` token", .{switch (diag.expected_group_closing_token.token) {
                    .r_paren => ")",
                    .bar => "|",
                    else => unreachable,
                }});
            },
            else => try writer.print("{!}", .{err}),
        }
    }

    fn printLexerError(
        line: []const u8,
        writer: ArrayList(u8).Writer,
        err: calculator.Lexer.Error,
        diag: calculator.Lexer.Diagnostics,
    ) !void {
        try writer.writeAll("Lexer error:\n");
        try writer.print("\t{s}\n\t", .{line});

        const location = diag.location;
        try writer.writeByteNTimes('~', location);
        try writer.writeByte('^');
        try writer.writeByteNTimes('~', line.len - location - 1);

        try writer.writeAll("\nDescription: ");
        switch (err) {
            error.InvalidCharacter => try writer.writeAll("Invalid character"),
            error.ExpectedDigit => try writer.writeAll("Expected digit"),
            error.ExpectedSignOrDigit => try writer.writeAll("Expected +, - or digit"),
        }
    }

    pub fn widget(self: *const Entry) vxfw.Widget {
        return .{
            .userdata = @constCast(self),
            .drawFn = Entry.typeErasedDraw,
        };
    }

    fn typeErasedDraw(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const self: *const Entry = @ptrCast(@alignCast(ptr));
        return self.draw(ctx);
    }

    fn draw(self: *const Entry, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const arrows_widget_width = @as(u16, @intCast(arrows_widget.text.len));

        const arrows_surf: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = try arrows_widget.draw(ctx.withConstraints(
                .{
                    .width = @min(ctx.min.width, arrows_widget_width),
                    .height = 1,
                },
                .{
                    .width = if (ctx.max.width) |w|
                        @min(w, arrows_widget_width)
                    else
                        @intCast(arrows_widget.text.len),
                    .height = 1,
                },
            )),
        };

        const input_widget: vxfw.Text = .{ .text = self.input, .softwrap = false };

        const input_width: u16 = @intCast(self.inputWidth(ctx));
        const input_height: u16 = @intCast(self.inputHeight());

        const input_surf: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = arrows_widget_width },
            .surface = try input_widget.draw(ctx.withConstraints(
                .{
                    .height = @min(ctx.min.height, input_height),
                    .width = @min(ctx.min.width -| arrows_widget_width, input_width),
                },
                .{
                    .height = if (ctx.max.height) |h|
                        @min(h, input_height)
                    else
                        input_height,

                    .width = if (ctx.max.width) |w|
                        @min(w -| arrows_widget_width, input_width)
                    else
                        input_width,
                },
            )),
        };

        const result_widget: vxfw.Text = .{ .text = self.result, .softwrap = false };

        const result_width: u16 = @intCast(self.resultWidth(ctx));
        const result_height: u16 = @intCast(self.resultHeight());

        const result_surf: vxfw.SubSurface = .{
            .origin = .{ .row = 1, .col = 0 },
            .surface = try result_widget.draw(ctx.withConstraints(
                .{
                    .height = @min(ctx.min.height, result_height),
                    .width = @min(ctx.min.width, result_width),
                },
                .{
                    .height = if (ctx.max.height) |h|
                        @min(h, result_height)
                    else
                        result_height,

                    .width = if (ctx.max.width) |w|
                        @min(w, result_width)
                    else
                        result_width,
                },
            )),
        };

        const children = try ctx.arena.alloc(vxfw.SubSurface, 3);
        children[0] = arrows_surf;
        children[1] = input_surf;
        children[2] = result_surf;

        return .{
            .size = .{
                .width = @max((3 + input_surf.surface.size.width), result_surf.surface.size.width),
                .height = 1 + result_surf.surface.size.height,
            },
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
        };
    }
};

pub fn init(alloc: Allocator) !History {
    return .{
        .deque = try .initCapacity(alloc, 32),
        .selected_item = null,
    };
}

pub fn deinit(self: *History, alloc: Allocator) void {
    var iter = self.deque.iterator();
    defer iter.deinit(alloc);
    while (iter.next()) |entry| {
        entry.deinit(alloc);
    }
}

pub fn height(self: *const History) usize {
    var iter = self.deque.iter();
    var total_height: usize = 0;
    while (iter.next()) |entry| {
        total_height += entry.height();
    }
    return total_height;
}

pub fn width(self: *const History, ctx: vxfw.DrawContext) usize {
    var iter = self.deque.iter();
    var max_width: usize = 0;
    while (iter.next()) |entry| {
        max_width = @max(max_width, entry.width(ctx));
    }
    return max_width;
}

pub fn widgetBuilder(userdata: *const anyopaque, idx: usize, _: usize) ?vxfw.Widget {
    const self: *const History = @ptrCast(@alignCast(userdata));
    var entry = self.deque.getOrNull(idx) orelse return null;
    return entry.widget();
}

pub fn add(self: *History, item: Entry) ?Entry {
    return self.deque.pushBackReplace(item);
}

pub fn selectNext(self: *History) void {
    if (self.deque.len == 0) {
        return;
    }

    if (self.selected_item == null) {
        self.selected_item = self.deque.len - 1;
    } else if (self.selected_item.? > 0) {
        self.selected_item.? -= 1;
    }
}

pub fn selectPrevious(self: *History) void {
    if (self.deque.len == 0) {
        return;
    }

    if (self.selected_item) |*selected_item| {
        if (selected_item.* < self.deque.len - 1) {
            selected_item.* += 1;
        } else {
            self.selected_item = null;
        }
    }
}

pub fn getSelectedItem(self: *History) ?*Entry {
    return self.deque.getMut(self.selected_item orelse return null);
}

pub fn deselect(self: *History) void {
    self.selected_item = null;
}
