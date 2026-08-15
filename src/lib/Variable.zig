const std = @import("std");

/// Represents a shorter name for reusable strings.
const Self = @This();

name: []const u8,
value: []const u8,

pub fn init(name: []const u8, value: []const u8) Self {
    return .{ .name = name, .value = value };
}

pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
    allocator.free(self.value);
}
