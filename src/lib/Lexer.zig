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

/// Struct to analyze a buffer stream to be parsed into tokens.
const Self = @This();

reader: std.Io.Reader,
token: std.ArrayListUnmanaged(u8) = .empty,
start_of_line: bool = true,

pub fn initStream(stream: []const u8) Self {
    return .{
        .reader = .fixed(stream),
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.token.deinit(allocator);
}

pub fn nextToken(self: *Self, allocator: std.mem.Allocator) !?Token {
    self.token.clearRetainingCapacity();

    var found_token = false;
    outer: while (true) : (self.reader.toss(1)) {
        const ch = self.reader.peekByte() catch |err| {
            if (err == error.EndOfStream) {
                break :outer;
            }

            return err;
        };

        switch (ch) {
            ' ', '\t' => {
                // This is an indentation
                if (self.start_of_line) {
                    self.start_of_line = false;
                    while (true) {
                        const space = self.reader.peekByte() catch |err| {
                            if (err == error.EndOfStream) {
                                break;
                            }

                            return err;
                        };

                        if (space != ' ' and space != '\t') {
                            return .init(.indent, "");
                        }

                        self.reader.toss(1);
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
                if (!found_token) {
                    found_token = true;
                    try self.token.append(allocator, ch);
                    self.reader.toss(1);
                }

                break :outer;
            },
            else => {
                self.start_of_line = false;
                found_token = true;
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
    } else if (slice.len > 0) {
        return .init(.ident, slice);
    }

    return null;
}

fn advance(self: *Self) !?u8 {
    const result = self.reader.takeByte() catch |err| {
        if (err == error.EndOfStream) {
            return null;
        }

        return err;
    };

    return result;
}

test "lexer" {
    const stream = 
    \\cflags = -Wall
    \\
    \\rule cc
    \\    command = gcc $cflags -c $in -o $out
    \\
    \\build foo.o: cc foo.c
    ;

    const allocator = std.testing.allocator;

    var lexer = Self.initStream(stream);
    defer lexer.deinit(allocator);

    try expectEqualToken(allocator, .init(.ident, "cflags"), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.equals, "="), try lexer.nextToken(allocator));
    try expectEqualToken(allocator, .init(.ident, "-Wall"), try lexer.nextToken(allocator));
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
