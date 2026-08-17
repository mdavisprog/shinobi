const std = @import("std");
const Variable = @import("Variable.zig");

/// Defines a short name for a command line.
const Self = @This();

name: []const u8,
variables: std.StringHashMapUnmanaged(Variable),

pub fn init(name: []const u8) Self {
    return .{
        .name = name,
        .variables = .empty,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.name);

    var it = self.variables.valueIterator();
    while (it.next()) |variable| {
        variable.deinit(allocator);
    }
    self.variables.deinit(allocator);
}
