const Lexer = @import("Lexer.zig");
const std = @import("std");
const Variable = @import("Variable.zig");

/// Parses a stream or file into tokens so they can be destructured to create a 'build.zig' file.
const Self = @This();

lexer: Lexer,
variables: std.StringHashMapUnmanaged(Variable),

pub fn init(stream: []const u8) Self {
    return .{
        .lexer = .initStream(stream),
        .variables = .empty,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    var it = self.variables.valueIterator();
    while (it.next()) |variable| {
        variable.deinit(allocator);
    }
    self.variables.deinit(allocator);
}

pub fn begin(self: *Self, allocator: std.mem.Allocator) !void {
    var last_token: ?Lexer.Token = null;

    while (self.lexer.nextToken()) |token| {
        switch (token.token_type) {
            .equals => {
                const last = last_token orelse unreachable;
                try self.parseVariable(allocator, last);
            },
            else => {},
        }

        last_token = token;
    }
}

fn parseVariable(self: *Self, allocator: std.mem.Allocator, name_token: Lexer.Token) !void {
    var value = std.ArrayListUnmanaged(u8).empty;

    while (self.lexer.nextToken()) |token| {
        switch (token.token_type) {
            .ident => {
                if (value.items.len > 0) {
                    try value.append(allocator, ' ');
                }

                try value.appendSlice(allocator, token.data);
            },
            else => break,
        }
    }

    const variable = Variable.init(
        try allocator.dupe(u8, name_token.data),
        try value.toOwnedSlice(allocator),
    );

    try self.variables.put(allocator, variable.name, variable);
}

test "parser" {
    const stream = 
    \\cflags = -Wall
    \\
    \\rule cc
    \\command = gcc $cflags -c $in -o $out
    \\
    \\build foo.o: cc foo.c
    ;

    const allocator = std.testing.allocator;

    var parser = Self.init(stream);
    defer parser.deinit(allocator);

    try parser.begin(allocator);

    try std.testing.expectEqual(2, parser.variables.count());
    try std.testing.expectEqualStrings("cflags", parser.variables.get("cflags").?.name);
    try std.testing.expectEqualStrings("-Wall", parser.variables.get("cflags").?.value);
    try std.testing.expectEqualStrings("command", parser.variables.get("command").?.name);
    try std.testing.expectEqualStrings("gcc $cflags -c $in -o $out", parser.variables.get("command").?.value);
}
