const std = @import("std");

/// List of possible tokens that can be lexed from a stream.
pub const Token = struct {
    pub const Type = enum {
        build,
        rule,
        ident,
        equals,
        new_line,
        indent,
        colon,
        comment,
        include,
    };

    token_type: Type,
    data: []const u8,

    pub fn deinit(self: Token, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }

    fn init(token_type: Type, data: []const u8) Token {
        return .{ .token_type = token_type, .data = data };
    }
};

const Source = union(enum) {
    stream: std.Io.Reader,
    file: struct {
        handle: std.Io.File,
        buffer: []u8,
        reader: std.Io.File.Reader,
    },

    fn initStream(stream: []const u8) Source {
        return .{ .stream = .fixed(stream) };
    }

    fn initFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Source {
        const handle = if (std.fs.path.isAbsolute(path))
            try std.Io.Dir.openFileAbsolute(io, path, .{})
        else
            try std.Io.Dir.cwd().openFile(io, path, .{});

        const buffer = try allocator.alloc(u8, 1024);
        const reader = handle.reader(io, buffer);

        return .{
            .file = .{
                .handle = handle,
                .buffer = buffer,
                .reader = reader,
            },
        };
    }

    fn deinit(self: *Source, allocator: std.mem.Allocator, io: std.Io) void {
        switch (self.*) {
            .stream => {},
            .file => |file| {
                file.handle.close(io);
                allocator.free(file.buffer);
            },
        }
    }

    fn peekByte(self: *Source) !u8 {
        switch (self.*) {
            .stream => |*reader| {
                return reader.peekByte();
            },
            .file => |*file| {
                return file.reader.interface.peekByte();
            },
        }
    }

    fn toss(self: *Source, n: usize) void {
        switch (self.*) {
            .stream => |*reader| {
                reader.toss(n);
            },
            .file => |*file| {
                file.reader.interface.toss(n);
            },
        }
    }
};

/// Struct to analyze a buffer stream to be parsed into tokens.
const Self = @This();

source: Source,
token: std.ArrayListUnmanaged(u8) = .empty,
start_of_line: bool = true,

pub fn initStream(stream: []const u8) Self {
    return .{
        .source = .initStream(stream),
    };
}

pub fn initFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Self {
    return .{
        .source = try .initFile(allocator, io, path),
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator, io: std.Io) void {
    self.token.deinit(allocator);
    self.source.deinit(allocator, io);
}

pub fn nextToken(self: *Self, allocator: std.mem.Allocator) !?Token {
    self.token.clearRetainingCapacity();

    var is_escaped = false;
    var found_token = false;
    outer: while (true) : (self.source.toss(1)) {
        const ch = self.source.peekByte() catch |err| {
            if (err == error.EndOfStream) {
                break :outer;
            }

            return err;
        };

        switch (ch) {
            ' ', '\t' => {
                if (is_escaped) {
                    is_escaped = false;
                    try self.token.append(allocator, ch);
                    continue;
                }

                // This is an indentation
                if (self.start_of_line) {
                    self.start_of_line = false;
                    while (true) {
                        const space = self.source.peekByte() catch |err| {
                            if (err == error.EndOfStream) {
                                break;
                            }

                            return err;
                        };

                        if (space != ' ' and space != '\t') {
                            return .init(.indent, "");
                        }

                        self.source.toss(1);
                    }
                }

                if (!found_token) {
                    continue;
                } else {
                    break :outer;
                }
            },
            '\r' => {
                continue;
            },
            '\n', ':' => {
                if (is_escaped) {
                    is_escaped = false;

                    if (ch == ':') {
                        try self.token.append(allocator, ch);
                    }
                } else {
                    if (!found_token) {
                        found_token = true;
                        try self.token.append(allocator, ch);
                        self.source.toss(1);
                    }

                    break :outer;
                }
            },
            '#' => {
                try self.token.append(allocator, ch);

                if (self.start_of_line) {
                    self.source.toss(1);

                    while (true) {
                        const next = self.source.peekByte() catch |err| {
                            if (err == error.EndOfStream) {
                                break :outer;
                            }

                            return err;
                        };

                        if (next != '\n') {
                            try self.token.append(allocator, next);
                            self.source.toss(1);
                        } else {
                            break :outer;
                        }
                    }
                }
            },
            '$' => {
                self.start_of_line = false;
                found_token = true;
                is_escaped = true;
                try self.token.append(allocator, ch);
            },
            else => {
                self.start_of_line = false;
                found_token = true;
                is_escaped = false;
                try self.token.append(allocator, ch);
            },
        }
    }

    const slice = try self.token.toOwnedSlice(allocator);

    if (std.mem.eql(u8, slice, "build")) {
        return .init(.build, slice);
    } else if (std.mem.eql(u8, slice, "rule")) {
        return .init(.rule, slice);
    } else if (std.mem.eql(u8, slice, "=")) {
        return .init(.equals, slice);
    } else if (std.mem.eql(u8, slice, "\n")) {
        self.start_of_line = true;
        return .init(.new_line, slice);
    } else if (std.mem.eql(u8, slice, ":")) {
        return .init(.colon, slice);
    } else if (std.mem.eql(u8, slice, "include")) {
        return .init(.include, slice);
    } else if (std.mem.startsWith(u8, slice, "#")) {
        return .init(.comment, slice);
    } else if (slice.len > 0) {
        return .init(.ident, slice);
    }

    return null;
}

test "lexer" {
    const stream =
        \\cflags = -Wall
        \\# not_a_var = true
        \\
        \\include Dir/rules.ninja
        \\
        \\rule cc
        \\    command = gcc $cflags -c $in -o $out
        \\
        \\build foo.o: cc foo.c
        \\
        \\build bar.o: cc C$:\Some$ Folder\bar.c
    ;

    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var lexer = Self.initStream(stream);
    defer lexer.deinit(allocator, io);

    try expectEqualToken(allocator, .init(.ident, "cflags"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.equals, "="), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "-Wall"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.new_line, "\n"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.comment, "# not_a_var = true"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.new_line, "\n"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.new_line, "\n"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.include, "include"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "Dir/rules.ninja"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.new_line, "\n"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.new_line, "\n"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.rule, "rule"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "cc"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.new_line, "\n"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.indent, ""), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "command"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.equals, "="), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "gcc"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "$cflags"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "-c"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "$in"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "-o"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "$out"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.new_line, "\n"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.new_line, "\n"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.build, "build"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "foo.o"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.colon, ":"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "cc"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "foo.c"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.new_line, "\n"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.new_line, "\n"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.build, "build"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "bar.o"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.colon, ":"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "cc"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "C$:\\Some$ Folder\\bar.c"), try lexer.nextToken(allocator));
}

fn expectEqualTokenType(expected: Token.Type, actual: Token.Type) !void {
    try std.testing.expectEqual(expected, actual);
}

fn expectEqualToken(allocator: std.mem.Allocator, expected: Token, actual: ?Token) !void {
    const actual_ = actual orelse unreachable;
    defer actual_.deinit(allocator);

    try expectEqualTokenType(expected.token_type, actual_.token_type);
    try std.testing.expectEqualStrings(expected.data, actual_.data);
}
