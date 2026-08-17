const Lexer = @import("Lexer.zig");
const Rule = @import("Rule.zig");
const std = @import("std");
const Variable = @import("Variable.zig");

pub const Error = error{
    InvalidRule,
};

/// Parses a stream or file into tokens so they can be destructured to create a 'build.zig' file.
const Self = @This();

lexer: Lexer,
variables: std.StringHashMapUnmanaged(Variable),
rules: std.StringHashMapUnmanaged(Rule),

pub fn init(stream: []const u8) Self {
    return .{
        .lexer = .initStream(stream),
        .variables = .empty,
        .rules = .empty,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    {
        var it = self.variables.valueIterator();
        while (it.next()) |variable| {
            variable.deinit(allocator);
        }
        self.variables.deinit(allocator);
    }

    {
        var it = self.rules.valueIterator();
        while (it.next()) |rule| {
            rule.deinit(allocator);
        }
        self.rules.deinit(allocator);
    }
}

pub fn begin(self: *Self, allocator: std.mem.Allocator) !void {
    var last_token: ?Lexer.Token = null;

    while (self.lexer.nextToken()) |token| {
        switch (token.token_type) {
            .equals => {
                const last = last_token orelse unreachable;
                const variable = try self.parseVariable(allocator, last);
                try self.variables.put(allocator, variable.name, variable);
            },
            .rule => {
                const rule = try self.parseRule(allocator);
                try self.rules.put(allocator, rule.name, rule);
            },
            else => {},
        }

        last_token = token;
    }
}

fn parseVariable(self: *Self, allocator: std.mem.Allocator, name_token: Lexer.Token) !Variable {
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

    return .init(
        try allocator.dupe(u8, name_token.data),
        try value.toOwnedSlice(allocator),
    );
}

fn parseRule(self: *Self, allocator: std.mem.Allocator) !Rule {
    const name = self.lexer.nextToken() orelse return Error.InvalidRule;
    if (name.token_type != .ident) return Error.InvalidRule;

    var rule = Rule.init(try allocator.dupe(u8, name.data));
    errdefer rule.deinit(allocator);

    const new_line = self.lexer.nextToken() orelse return Error.InvalidRule;
    if (new_line.token_type != .new_line) return Error.InvalidRule;

    var last_token: ?Lexer.Token = null;
    outer: while (self.lexer.nextToken()) |token| {
        switch (token.token_type) {
            .equals => {
                const last = last_token orelse return Error.InvalidRule;
                const variable = try self.parseVariable(allocator, last);
                try rule.variables.put(allocator, variable.name, variable);
            },
            .new_line => {
                break :outer;
            },
            else => {},
        }

        last_token = token;
    }

    return rule;
}

test "parser" {
    const stream = 
    \\cflags = -Wall
    \\
    \\rule cc
    \\    command = gcc $cflags -c $in -o $out
    \\
    \\build foo.o: cc foo.c
    ;

    const allocator = std.testing.allocator;

    var parser = Self.init(stream);
    defer parser.deinit(allocator);

    try parser.begin(allocator);

    try std.testing.expectEqual(1, parser.variables.count());
    try std.testing.expectEqualStrings("cflags", parser.variables.get("cflags").?.name);
    try std.testing.expectEqualStrings("-Wall", parser.variables.get("cflags").?.value);

    const rule = parser.rules.get("cc") orelse unreachable;
    try std.testing.expectEqual(1, parser.rules.count());
    try std.testing.expectEqual(1, rule.variables.count());
    try std.testing.expectEqualStrings("cc", rule.name);
    try std.testing.expectEqualStrings("command", rule.variables.get("command").?.name);
    try std.testing.expectEqualStrings("gcc $cflags -c $in -o $out", rule.variables.get("command").?.value);
}
