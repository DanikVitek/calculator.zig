const std = @import("std");
const Allocator = std.mem.Allocator;
const File = std.fs.File;
const ArrayList = std.ArrayList;

const calculator = @import("calculator_lib");
const ArrayDeque = @import("deque.zig").ArrayDeque;

const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const TextInput = vaxis.widgets.TextInput;
const TextView = vaxis.widgets.TextView;

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

const Event = union(enum) {
    key_press: vaxis.Key,
    win_size: vaxis.Winsize,
};

const arrows_widget = vxfw.Text{
    .text = ">> ",
    .softwrap = false,
    .overflow = .clip,
};

const Model = struct {
    scroll_bars: vxfw.ScrollBars,
    history: History,
    text_input: vxfw.TextField,
    alloc: Allocator,

    pub fn init(alloc: Allocator, unicode: *const vaxis.Unicode) !*Model {
        const model = try alloc.create(Model);
        errdefer alloc.destroy(model);

        model.* = .{
            .history = try .init(alloc),
            .text_input = .init(alloc, unicode),
            .scroll_bars = .{
                .scroll_view = .{
                    .children = .{
                        .builder = .{
                            .userdata = model,
                            .buildFn = Model.widgetBuilder,
                        },
                    },
                },
                .estimated_content_height = 0,
            },
            .alloc = alloc,
        };

        return model;
    }

    pub fn deinit(self: *Model) void {
        self.history.deinit(self.alloc);
        self.text_input.deinit();
    }

    fn widgetBuilder(userdata: *const anyopaque, idx: usize, _: usize) ?vxfw.Widget {
        const self: *const Model = @ptrCast(@alignCast(userdata));
        var entry = self.history.deque.getOrNull(idx) orelse return null;
        return entry.widget();
    }

    pub fn widget(self: *Model) vxfw.Widget {
        return .{
            .userdata = self,
            .drawFn = Model.typeErasedDraw,
            .eventHandler = Model.typeErasedEventHandler,
        };
    }

    fn typeErasedDraw(userdata: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const self: *Model = @ptrCast(@alignCast(userdata));
        return self.draw(ctx);
    }

    fn draw(self: *Model, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
        const scroll_view: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = try self.scroll_bars.draw(ctx.withConstraints(.{
                .width = ctx.min.width,
                .height = @max(ctx.min.height -| 1, 1),
            }, .{
                .width = ctx.max.width,
                .height = if (ctx.max.height) |h| h -| 1 else null,
            })),
        };

        const arrows_surf: vxfw.SubSurface = .{
            .origin = .{ .row = scroll_view.surface.size.height, .col = 0 },
            .surface = try arrows_widget.draw(ctx.withConstraints(
                .{ .width = 3, .height = 1 },
                .{ .width = 3, .height = 1 },
            )),
        };

        const text_input: vxfw.SubSurface = .{
            .origin = .{ .row = scroll_view.surface.size.height, .col = 3 },
            .surface = try self.text_input.draw(ctx.withConstraints(
                .{ .height = 1, .width = 4 },
                .{ .height = 1, .width = ctx.max.width },
            )),
        };

        const children = try ctx.arena.alloc(vxfw.SubSurface, 3);
        children[0] = scroll_view;
        children[1] = arrows_surf;
        children[2] = text_input;

        return .{
            .size = .{
                .width = @max(scroll_view.surface.size.width, text_input.surface.size.width + 3),
                .height = scroll_view.surface.size.height + 1,
            },
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
        };
    }

    fn typeErasedEventHandler(userdata: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *Model = @ptrCast(@alignCast(userdata));
        return self.eventHandler(ctx, event);
    }

    fn eventHandler(self: *Model, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        switch (event) {
            .key_press => |key| {
                if (key.codepoint == 'c' and key.mods.ctrl) {
                    ctx.quit = true;
                    return;
                } else if (key.matches(vaxis.Key.up, .{})) {
                    self.history.selectNext();
                    self.text_input.clearRetainingCapacity();
                    if (self.history.getSelectedItem()) |item| {
                        try self.text_input.insertSliceAtCursor(item.input);
                    }
                } else if (key.matches(vaxis.Key.down, .{})) {
                    self.history.selectPrevious();
                    self.text_input.clearRetainingCapacity();
                    if (self.history.getSelectedItem()) |item| {
                        try self.text_input.insertSliceAtCursor(item.input);
                    }
                } else if (key.matches(vaxis.Key.enter, .{}) or key.matches('j', .{ .ctrl = true })) {
                    if (self.history.getSelectedItem()) |selected_entry| {
                        defer self.history.deselect();
                        defer self.text_input.clearRetainingCapacity();
                        const new_entry = try selected_entry.clone(self.alloc);
                        if (self.history.add(new_entry)) |tail_entry| {
                            const entry_height = tail_entry.height();
                            tail_entry.deinit(self.alloc);
                            self.scroll_bars.estimated_content_height.? -= @intCast(entry_height);
                        }
                        self.scroll_bars.estimated_content_height.? += @intCast(new_entry.height());
                    } else {
                        const new_entry = try History.Entry.init(try self.text_input.toOwnedSlice(), self.alloc);
                        if (self.history.add(new_entry)) |tail_entry| {
                            const entry_height = tail_entry.height();
                            tail_entry.deinit(self.alloc);
                            self.scroll_bars.estimated_content_height.? -= @intCast(entry_height);
                        }
                        self.scroll_bars.estimated_content_height.? += @intCast(new_entry.height());
                    }
                } else {
                    self.history.deselect();
                    try self.text_input.handleEvent(ctx, event);
                }
            },
            else => {},
        }
    }
};

const History = struct {
    deque: ArrayDeque(Entry),
    selected_item: ?usize,

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

        pub fn height(self: Entry) usize {
            return std.mem.count(u8, self.input, "\n") + 1 + std.mem.count(u8, self.result, "\n") + 1;
        }

        fn printParserError(
            line: []const u8,
            writer: ArrayList(u8).Writer,
            err: calculator.Parser.Error,
            diag: calculator.Parser.Diagnostics,
        ) !void {
            try writer.print("Parser error:\n", .{});
            switch (err) {
                error.OutOfMemory => return @as(Allocator.Error, @errorCast(err)),
                error.InvalidCharacter => switch (diag) {
                    .lexer => |lexer_diag| try printLexerError(
                        line,
                        writer,
                        error.InvalidCharacter,
                        lexer_diag,
                    ),
                    .float => |float| try writer.print("\t{s}\nDescription: Invalid floating point number", .{float}),
                    else => unreachable,
                },
                error.ExpectedDigit, error.ExpectedSignOrDigit => |e| try printLexerError(
                    line,
                    writer,
                    @errorCast(e),
                    diag.lexer,
                ),
                error.UnexpectedEOI => {
                    try writer.print("\t{s}\n\t", .{line});
                    for (0..line.len) |_| {
                        try writer.print("~", .{});
                    }
                    try writer.print("^\nDescription: Unexpected end of input", .{});
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
            try writer.print("Lexer error:\n", .{});
            const location = diag.location;
            try writer.print("\t{s}\n\t", .{line});
            for (0..location) |_| {
                try writer.print("~", .{});
            }
            try writer.print("^", .{});
            for (location + 1..line.len) |_| {
                try writer.print("~", .{});
            }
            try writer.print("\nDescription: ", .{});
            switch (err) {
                error.InvalidCharacter => try writer.print("Invalid character", .{}),
                error.ExpectedDigit => try writer.print("Expected digit", .{}),
                error.ExpectedSignOrDigit => try writer.print("Expected +, - or digit", .{}),
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
            const arrows_surf: vxfw.SubSurface = .{
                .origin = .{ .row = 0, .col = 0 },
                .surface = try arrows_widget.draw(ctx.withConstraints(
                    .{ .width = 3, .height = 1 },
                    .{ .width = 3, .height = 1 },
                )),
            };

            const input_widget: vxfw.Text = .{ .text = self.input, .softwrap = false };
            const input_surf: vxfw.SubSurface = .{
                .origin = .{ .row = 0, .col = 3 },
                .surface = try input_widget.draw(ctx.withConstraints(
                    .{ .height = 1, .width = 1 },
                    .{ .height = 1, .width = @truncate(ctx.stringWidth(self.input)) },
                )),
            };

            const result_widget: vxfw.Text = .{ .text = self.result, .softwrap = false };
            const result_surf: vxfw.SubSurface = .{
                .origin = .{ .row = 1, .col = 0 },
                .surface = try result_widget.draw(ctx),
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
};
