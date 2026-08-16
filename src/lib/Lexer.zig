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
    };

    token_type: Type,
    data: []const u8,

    fn init(token_type: Type, data: []const u8) Token {
        return .{ .token_type = token_type, .data = data };
    }
};

/// Struct to analyze a buffer stream to be parsed into tokens.
const Self = @This();

stream: []const u8,
current: usize = 0,
start_of_line: bool = true,

pub fn initStream(stream: []const u8) Self {
    return .{ .stream = stream };
}

pub fn nextToken(self: *Self) ?Token {
    if (self.current >= self.stream.len) return null;

    var start = self.current;

    var found_token = false;
    state: switch (self.stream[self.current]) {
        ' ', '\t' => {
            // This is an indentation
            if (self.start_of_line) {
                self.start_of_line = false;
                while (self.advance()) |ch| {
                    if (ch != ' ' and ch != '\t') {
                        return .init(.indent, "");
                    }
                }
            }

            if (!found_token) {
                if (self.advance()) |ch| {
                    start = self.current;
                    continue :state ch;
                } else {
                    break :state;
                }
            } else {
                break :state;
            }
        },
        '\r' => {
            if (self.advance()) |ch| continue :state ch else break :state;
        },
        '\n' => {
            if (!found_token) {
                found_token = true;
                self.current += 1;
            }

            break : state;
        },
        else => {
            self.start_of_line = false;
            found_token = true;
            if (self.advance()) |ch| continue :state ch else break :state;
        },
    }

    const slice = self.stream[start..self.current];

    if (std.mem.eql(u8, slice, "build")) {
        return .init(.build, slice);
    } else if (std.mem.eql(u8, slice, "rule")) {
        return .init(.rule, slice);
    } else if (std.mem.eql(u8, slice, "=")) {
        return .init(.equals, slice);
    } else if (std.mem.eql(u8, slice, "\n")) {
        self.start_of_line = true;
        return .init(.new_line, slice);
    } else if (slice.len > 0) {
        return .init(.ident, slice);
    }

    return null;
}

fn advance(self: *Self) ?u8 {
    if (self.current >= self.stream.len) {
        return null;
    }

    self.current += 1;

    return if (self.current < self.stream.len)
        self.stream[self.current]
    else
        null;
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

    var lexer = Self.initStream(stream);

    try expectEqualToken(.init(.ident, "cflags"), lexer.nextToken());
    try expectEqualToken(.init(.equals, "="), lexer.nextToken());
    try expectEqualToken(.init(.ident, "-Wall"), lexer.nextToken());
    try expectEqualToken(.init(.new_line, "\n"), lexer.nextToken());
    try expectEqualToken(.init(.new_line, "\n"), lexer.nextToken());
    try expectEqualToken(.init(.rule, "rule"), lexer.nextToken());
    try expectEqualToken(.init(.ident, "cc"), lexer.nextToken());
    try expectEqualToken(.init(.new_line, "\n"), lexer.nextToken());
    try expectEqualToken(.init(.indent, ""), lexer.nextToken());
    try expectEqualToken(.init(.ident, "command"), lexer.nextToken());
    try expectEqualToken(.init(.equals, "="), lexer.nextToken());
    try expectEqualToken(.init(.ident, "gcc"), lexer.nextToken());
    try expectEqualToken(.init(.ident, "$cflags"), lexer.nextToken());
    try expectEqualToken(.init(.ident, "-c"), lexer.nextToken());
    try expectEqualToken(.init(.ident, "$in"), lexer.nextToken());
    try expectEqualToken(.init(.ident, "-o"), lexer.nextToken());
    try expectEqualToken(.init(.ident, "$out"), lexer.nextToken());
    try expectEqualToken(.init(.new_line, "\n"), lexer.nextToken());
    try expectEqualToken(.init(.new_line, "\n"), lexer.nextToken());
    try expectEqualToken(.init(.build, "build"), lexer.nextToken());
    try expectEqualToken(.init(.ident, "foo.o:"), lexer.nextToken());
    try expectEqualToken(.init(.ident, "cc"), lexer.nextToken());
    try expectEqualToken(.init(.ident, "foo.c"), lexer.nextToken());
}

fn expectEqualTokenType(expected: Token.Type, actual: Token.Type) !void {
    try std.testing.expectEqual(expected, actual);
}

fn expectEqualToken(expected: Token, actual: ?Token) !void {
    const actual_ = actual orelse unreachable;
    try expectEqualTokenType(expected.token_type, actual_.token_type);
    try std.testing.expectEqualStrings(expected.data, actual_.data);
}
