const std = @import("std");

buf: []const u8,
index: usize = 0,

const LineIterator = @This();

pub fn init(buf: []const u8) LineIterator {
    return .{ .buf = buf };
}

pub fn next(self: *LineIterator) ?[]const u8 {
    if (self.index >= self.buf.len) return null;

    const start = self.index;
    const end = std.mem.indexOfAnyPos(u8, self.buf, self.index, "\r\n") orelse {
        self.index = self.buf.len;
        return self.buf[start..];
    };

    self.index = end;
    self.consumeCR();
    self.consumeLF();
    return self.buf[start..end];
}

/// consumes a \n byte
fn consumeLF(self: *LineIterator) void {
    if (self.index >= self.buf.len) return;
    if (self.buf[self.index] == '\n') self.index += 1;
}

/// consumes a \r byte
fn consumeCR(self: *LineIterator) void {
    if (self.index >= self.buf.len) return;
    if (self.buf[self.index] == '\r') self.index += 1;
}
