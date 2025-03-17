const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn ArrayDeque(comptime T: type) type {
    return struct {
        slice: if (@sizeOf(T) != 0) []T else void,
        head: if (@sizeOf(T) != 0) usize else void,
        len: usize,

        const Self = @This();

        pub const empty: Self = .{
            .slice = &[_]T{},
            .start = 0,
            .end = 0,
        };

        pub fn initCapacity(alloc: Allocator, cap: usize) !Self {
            const slice = try alloc.alloc(T, cap);
            return Self{ .slice = slice, .head = 0, .len = 0 };
        }

        pub fn getMut(self: *Self, index: usize) *T {
            if (index >= self.len) unreachable;
            return &self.slice[(self.head + index) % self.slice.len];
        }

        pub fn getOrNullMut(self: *Self, index: usize) ?*T {
            return if (index < self.len) self.getMut(index) else null;
        }

        pub fn getLastMut(self: *Self) *T {
            if (self.len == 0) unreachable;
            return &self.slice[(self.head + self.len - 1) % self.slice.len];
        }

        pub fn getLastOrNullMut(self: *Self) ?*T {
            return if (self.len == 0) null else self.getLastMut();
        }

        pub fn get(self: *const Self, index: usize) *const T {
            if (index >= self.len) unreachable;
            return &self.slice[(self.head + index) % self.slice.len];
        }

        pub fn getOrNull(self: *const Self, index: usize) ?*const T {
            return if (index < self.len) self.get(index) else null;
        }

        pub fn getLast(self: *const Self) *const T {
            if (self.len == 0) unreachable;
            return &self.slice[(self.head + self.len - 1) % self.slice.len];
        }

        pub fn getLastOrNull(self: *const Self) ?*const T {
            return if (self.len == 0) null else self.getLast();
        }

        pub inline fn capacity(self: *const Self) usize {
            return if (@sizeOf(T) == 0) std.math.maxInt(usize) else self.slice.len;
        }

        pub inline fn unusedCapacity(self: *const Self) usize {
            return if (@sizeOf(T) == 0) std.math.maxInt(usize) else self.capacity() - self.len;
        }

        pub fn grow(self: *Self, alloc: Allocator) !void {
            if (self.unusedCapacity() > 0) return;

            const old_cap = self.capacity();

            const new_cap = old_cap * 2;
            const new_slice = try alloc.alloc(T, new_cap);

            const slice0, const slice1 = self.slices();

            const new_len = self.len;
            const new_head = if (self.head < old_cap - self.len) self.head else b: {
                const head_len = old_cap - self.head;
                const tail_len = self.len - head_len;
                if (head_len > tail_len and new_cap - old_cap >= tail_len) {
                    @memcpy(new_slice[self.head..][0..slice0.len], slice0);
                    @memcpy(new_slice[self.slice.len..][0..slice1.len], slice1);
                    break :b self.head;
                } else {
                    const new_head = new_cap - head_len;
                    @memcpy(new_slice[new_head..][0..slice0.len], slice0);
                    @memcpy(new_slice[0..slice1.len], slice1);
                    break :b new_head;
                }
            };

            const new_deque = Self{
                .slice = new_slice,
                .len = new_len,
                .head = new_head,
            };

            self.deinit(alloc);
            self.* = new_deque;
        }

        pub fn slices(self: *const Self) [2][]T {
            return if (self.head + self.len <= self.slice.len) .{
                self.slice[self.head..][0..self.len],
                &[_]T{},
            } else .{
                self.slice[self.head..self.slice.len],
                self.slice[0 .. self.len - (self.slice.len - self.head)],
            };
        }

        pub fn pushBack(self: *Self, value: T, alloc: Allocator) !void {
            if (@sizeOf(T) != 0) try self.grow(alloc);
            self.pushBackAssumeCapacity(value);
        }

        pub fn pushBackAssumeCapacity(self: *Self, value: T) void {
            if (@sizeOf(T) != 0) {
                self.slice[self.len] = value;
                self.len += 1;
            } else {
                self.len +|= 1;
            }
        }

        pub fn popBack(self: *Self) ?T {
            if (self.len == 0) return null;
            defer self.len -= 1;
            return if (@sizeOf(T) != 0) self.slice[(self.head + self.len - 1) % self.slice.len] else T{};
        }

        pub fn pushFront(self: *Self, value: T, alloc: Allocator) !void {
            if (@sizeOf(T) != 0) {
                try self.grow(alloc);
            }
            self.pushFrontAssumeCapacity(value);
        }

        pub fn pushFrontAssumeCapacity(self: *Self, value: T) void {
            if (@sizeOf(T) != 0) {
                self.head = if (self.head == 0) self.slice.len - 1 else self.head - 1;
                self.slice[self.head] = value;
                self.len += 1;
            } else {
                self.len +|= 1;
            }
        }

        pub fn popFront(self: *Self) ?T {
            if (self.len == 0) return null;
            defer {
                if (@sizeOf(T) != 0) self.head = (self.head + 1) % self.slice.len;
                self.len -= 1;
            }
            return if (@sizeOf(T) != 0) self.slice[self.head] else T{};
        }

        pub fn pushBackReplace(self: *Self, value: T) ?T {
            if (self.unusedCapacity() == 0) {
                const old = self.popFront();
                self.pushBackAssumeCapacity(value);
                return old;
            } else {
                self.pushBackAssumeCapacity(value);
                return null;
            }
        }

        pub fn pushFrontReplace(self: *Self, value: T) ?T {
            if (self.unusedCapacity() == 0) {
                const old = self.popBack();
                self.pushFrontAssumeCapacity(value);
                return old;
            } else {
                self.pushFrontAssumeCapacity(value);
                return null;
            }
        }

        pub fn deinit(self: Self, alloc: Allocator) void {
            alloc.free(self.slice);
        }

        pub fn iterator(self: Self) Iterator {
            return Iterator{ .deque = self };
        }

        pub fn iter(self: *const Self) Iter {
            return Iter{ .deque = self, .index = self.head };
        }

        pub fn iterMut(self: *Self) IterMut {
            return IterMut{ .deque = self, .index = self.head };
        }

        pub const Iterator = struct {
            deque: Self,

            pub fn next(self: *Iterator) ?T {
                return self.deque.popFront();
            }

            pub fn deinit(self: Iterator, alloc: Allocator) void {
                self.deque.deinit(alloc);
            }
        };

        pub const Iter = struct {
            deque: *const Self,
            index: usize,

            pub fn next(self: *Iter) ?*const T {
                if (self.index == self.deque.len) return null;
                defer self.index = (self.index + 1) % self.deque.slice.len;
                return &self.deque.slice[self.index];
            }
        };

        pub const IterMut = struct {
            deque: *Self,
            index: usize,

            pub fn next(self: *IterMut) ?*T {
                if (self.index == self.deque.len) return null;
                defer self.index = (self.index + 1) % self.deque.slice.len;
                return &self.deque.slice[self.index];
            }
        };
    };
}
