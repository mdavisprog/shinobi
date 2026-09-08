const BuildStatement = @import("BuildStatement.zig");
const Lexer = @import("Lexer.zig");
const Rule = @import("Rule.zig");
const std = @import("std");
const Variable = @import("Variable.zig");

pub const Error = error{
    InvalidRule,
    InvalidInclude,
};

/// Parses a stream or file into tokens so they can be destructured to create a 'build.zig' file.
const Self = @This();

lexer: Lexer,
variables: std.StringHashMapUnmanaged(Variable) = .empty,
rules: std.StringHashMapUnmanaged(Rule) = .empty,
builds: std.ArrayListUnmanaged(BuildStatement) = .empty,

pub fn initStream(stream: []const u8) Self {
    return .{
        .lexer = .initStream(stream),
    };
}

pub fn initFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Self {
    return .{
        .lexer = try .initFile(allocator, io, path),
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator, io: std.Io) void {
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

    for (self.builds.items) |*build| {
        build.deinit(allocator);
    }
    self.builds.deinit(allocator);

    self.lexer.deinit(allocator, io);
}

pub fn begin(self: *Self, allocator: std.mem.Allocator, io: std.Io) anyerror!void {
    var last_token: ?Lexer.Token = null;
    defer if (last_token) |token| token.deinit(allocator);

    while (try self.lexer.nextToken(allocator)) |token| {
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
            .build => {
                const build = try self.parseBuild(allocator);
                try self.builds.append(allocator, build);
            },
            .include => {
                try self.parseInclude(allocator, io);
            },
            else => {},
        }

        if (last_token) |last| last.deinit(allocator);
        last_token = token;
    }
}

pub fn printSummary(self: Self) void {
    {
        std.log.info("Variables: {}", .{self.variables.count()});

        var it = self.variables.valueIterator();
        while (it.next()) |variable| {
            std.log.info("   {s} = {s}", .{ variable.name, variable.value });
        }
    }

    {
        std.log.info("Rules: {}", .{self.rules.count()});
        var it = self.rules.valueIterator();
        while (it.next()) |rule| {
            std.log.info("   {s} has {} variables", .{ rule.name, rule.variables.count() });

            var variables = rule.variables.valueIterator();
            while (variables.next()) |variable| {
                std.log.info("      {s} = {s}", .{ variable.name, variable.value });
            }
        }
    }

    {
        std.log.info("Builds: {}", .{self.builds.items.len});
        for (self.builds.items) |build| {
            std.log.info("   inputs: {}", .{build.inputs.items.len});
            for (build.inputs.items) |input| {
                std.log.info("      {s}", .{input});
            }

            std.log.info("   outputs: {}", .{build.outputs.items.len});
            for (build.outputs.items) |output| {
                std.log.info("      {s}", .{output});
            }

            if (build.rule) |rule| {
                std.log.info("   Rule: {s}", .{rule});
            }

            std.log.info("   variables: {}", .{build.variables.count()});
            var variables = build.variables.valueIterator();
            while (variables.next()) |variable| {
                std.log.info("      {s} = {s}", .{ variable.name, variable.value });
            }
        }
    }
}

fn parseVariable(self: *Self, allocator: std.mem.Allocator, name_token: Lexer.Token) !Variable {
    var value = std.ArrayListUnmanaged(u8).empty;

    var single_token = false;
    while (try self.lexer.nextToken(allocator)) |token| {
        defer token.deinit(allocator);

        switch (token.token_type) {
            .ident, .build => {
                if (value.items.len > 0 and !single_token) {
                    try value.append(allocator, ' ');
                }

                try value.appendSlice(allocator, token.data);
                single_token = false;
            },
            // ':' token is not escaped in variables. Add these tokens and mark
            // identifier as a single token.
            .colon => {
                try value.appendSlice(allocator, token.data);
                single_token = true;
            },
            else => break,
        }
    }

    return .init(
        try allocator.dupe(u8, name_token.data),
        try value.toOwnedSlice(allocator),
    );
}

fn parseVariableBlock(
    self: *Self,
    allocator: std.mem.Allocator,
    variables: *std.StringHashMapUnmanaged(Variable),
) !void {
    var last_token: ?Lexer.Token = null;
    defer if (last_token) |token| token.deinit(allocator);

    var parsing_variable = false;
    outer: while (try self.lexer.nextToken(allocator)) |token| {
        switch (token.token_type) {
            .equals => {
                const last = last_token orelse return Error.InvalidRule;
                const variable = try self.parseVariable(allocator, last);
                try variables.put(allocator, variable.name, variable);
                // The 'parseVariable' function will eat the '\n' token so need to mark
                // flag as false.
                parsing_variable = false;
            },
            .indent => {
                parsing_variable = true;
            },
            .new_line => {
                if (!parsing_variable) {
                    token.deinit(allocator);
                    break :outer;
                } else {
                    parsing_variable = false;
                }
            },
            else => {},
        }

        if (last_token) |last| last.deinit(allocator);
        last_token = token;
    }
}

fn parseRule(self: *Self, allocator: std.mem.Allocator) !Rule {
    const name = try self.lexer.nextToken(allocator) orelse return Error.InvalidRule;
    defer name.deinit(allocator);
    if (name.token_type != .ident) return Error.InvalidRule;

    var rule = Rule.init(try allocator.dupe(u8, name.data));
    errdefer rule.deinit(allocator);

    const new_line = try self.lexer.nextToken(allocator) orelse return Error.InvalidRule;
    defer new_line.deinit(allocator);
    if (new_line.token_type != .new_line) return Error.InvalidRule;

    try self.parseVariableBlock(allocator, &rule.variables);

    return rule;
}

fn parseBuild(self: *Self, allocator: std.mem.Allocator) !BuildStatement {
    var build = BuildStatement.init();
    errdefer build.deinit(allocator);

    var parsing_outputs = true;
    var parsing_rule = true;
    outer: while (try self.lexer.nextToken(allocator)) |token| {
        defer token.deinit(allocator);

        switch (token.token_type) {
            .ident => {
                if (parsing_outputs) {
                    try build.outputs.append(allocator, try allocator.dupe(u8, token.data));
                } else {
                    if (parsing_rule) {
                        build.rule = try allocator.dupe(u8, token.data);
                        parsing_rule = false;
                    } else {
                        const input = try std.mem.replaceOwned(u8, allocator, token.data, "$", "");
                        std.mem.replaceScalar(u8, input, '\\', '/');
                        try build.inputs.append(allocator, input);
                    }
                }
            },
            .colon => {
                parsing_outputs = false;
            },
            else => {
                break :outer;
            },
        }
    }

    try self.parseVariableBlock(allocator, &build.variables);

    return build;
}

fn parseInclude(self: *Self, allocator: std.mem.Allocator, io: std.Io) anyerror!void {
    const path_token = try self.lexer.nextToken(allocator) orelse return Error.InvalidInclude;
    defer path_token.deinit(allocator);

    if (self.lexer.getPath()) |path| {
        if (std.fs.path.dirname(path)) |dir| {
            const include_path = try std.fs.path.join(allocator, &.{ dir, path_token.data });
            defer allocator.free(include_path);

            var parser = try Self.initFile(allocator, io, include_path);

            try parser.begin(allocator, io);
            try self.move(allocator, parser);

            // We do not want to free the allocated elements as they have been moved.
            // Just free the containers.
            parser.variables.deinit(allocator);
            parser.rules.deinit(allocator);
            parser.builds.deinit(allocator);
            parser.lexer.deinit(allocator, io);
        }
    } else {
    }
}

fn move(self: *Self, allocator: std.mem.Allocator, other: Self) !void {
    // Move variables
    {
        var it = other.variables.valueIterator();
        while (it.next()) |variable| {
            try self.variables.put(allocator, variable.name, variable.*);
        }
    }

    // Move rules
    {
        var it = other.rules.valueIterator();
        while (it.next()) |rule| {
            try self.rules.put(allocator, rule.name, rule.*);
        }
    }

    // Move builds
    {
        try self.builds.appendSlice(allocator, other.builds.items);
    }
}

test "parser" {
    const stream =
        \\cflags = -Wall
        \\
        \\rule cc
        \\    command = gcc $cflags -c $in -o $out
        \\    rulevar = 0
        \\
        \\build foo.o: cc foo.c
        \\    buildvar1 = true
        \\    buildvar2 = 5
        \\
        \\build bar.o: cc C$:\Some$ Folder\bar.c
    ;

    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var parser = Self.initStream(stream);
    defer parser.deinit(allocator, io);

    try parser.begin(allocator, io);

    try std.testing.expectEqual(1, parser.variables.count());
    try std.testing.expectEqualStrings("cflags", parser.variables.get("cflags").?.name);
    try std.testing.expectEqualStrings("-Wall", parser.variables.get("cflags").?.value);

    const rule = parser.rules.get("cc") orelse unreachable;
    try std.testing.expectEqual(1, parser.rules.count());
    try std.testing.expectEqual(2, rule.variables.count());
    try std.testing.expectEqualStrings("cc", rule.name);
    try std.testing.expectEqualStrings("command", rule.variables.get("command").?.name);
    try std.testing.expectEqualStrings("gcc $cflags -c $in -o $out", rule.variables.get("command").?.value);
    try std.testing.expectEqualStrings("rulevar", rule.variables.get("rulevar").?.name);
    try std.testing.expectEqualStrings("0", rule.variables.get("rulevar").?.value);

    const build1 = parser.builds.items[0];
    try std.testing.expectEqual(2, parser.builds.items.len);
    try std.testing.expectEqual(1, build1.outputs.items.len);
    try std.testing.expectEqual(1, build1.inputs.items.len);
    try std.testing.expectEqual(2, build1.variables.count());
    try std.testing.expectEqualStrings("cc", build1.rule.?);
    try std.testing.expectEqualStrings("foo.o", build1.outputs.items[0]);
    try std.testing.expectEqualStrings("foo.c", build1.inputs.items[0]);
    try std.testing.expectEqualStrings("buildvar1", build1.variables.get("buildvar1").?.name);
    try std.testing.expectEqualStrings("true", build1.variables.get("buildvar1").?.value);
    try std.testing.expectEqualStrings("buildvar2", build1.variables.get("buildvar2").?.name);
    try std.testing.expectEqualStrings("5", build1.variables.get("buildvar2").?.value);

    const build2 = parser.builds.items[1];
    try std.testing.expectEqual(1, build2.outputs.items.len);
    try std.testing.expectEqual(1, build2.inputs.items.len);
    try std.testing.expectEqual(0, build2.variables.count());
    try std.testing.expectEqualStrings("bar.o", build2.outputs.items[0]);
    try std.testing.expectEqualStrings("C:/Some Folder/bar.c", build2.inputs.items[0]);
}
