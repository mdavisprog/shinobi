const std = @import("std");
const Variable = @import("Variable.zig");

/// Contains the relationship between input and output files.
const Self = @This();

inputs: std.ArrayListUnmanaged([]const u8),
outputs: std.ArrayListUnmanaged([]const u8),
variables: std.StringHashMapUnmanaged(Variable),
rule: ?[]const u8,

pub fn init() Self {
    return .{
        .inputs = .empty,
        .outputs = .empty,
        .variables = .empty,
        .rule = null,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    for (self.inputs.items) |input| {
        allocator.free(input);
    }

    for (self.outputs.items) |output| {
        allocator.free(output);
    }

    self.inputs.deinit(allocator);
    self.outputs.deinit(allocator);

    if (self.rule) |rule| {
        allocator.free(rule);
    }

    var it = self.variables.valueIterator();
    while (it.next()) |variable| {
        variable.deinit(allocator);
    }
    self.variables.deinit(allocator);
}
