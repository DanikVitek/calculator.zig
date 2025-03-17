const std = @import("std");
const Allocator = std.mem.Allocator;

const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const Unicode = vaxis.Unicode;

const arrows_widget = @import("common.zig").arrows_widget;
const History = @import("History.zig");

scroll_bars: vxfw.ScrollBars,
history: History,
text_input: vxfw.TextField,
alloc: Allocator,

const Model = @This();

pub fn init(alloc: Allocator, unicode: *const Unicode) !*Model {
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

pub fn draw(self: *Model, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
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
    return self.handleEvent(ctx, event);
}

pub fn handleEvent(self: *Model, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
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
                ctx.redraw = true;
            } else {
                self.history.deselect();
                try self.text_input.handleEvent(ctx, event);
            }
        },
        else => {},
    }
}
