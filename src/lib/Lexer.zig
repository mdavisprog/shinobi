const std = @import("std");

/// List of possible tokens that can be lexed from a stream.
pub const Token = struct {
    pub const Type = enum {
        build,
        rule,
        ident,
        equals,
        new_line,
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

pub fn initStream(stream: []const u8) Self {
    return .{ .stream = stream };
}

pub fn nextToken(self: *Self) ?Token {
    self.skipWhitespaces();

    const start = self.current;

    var is_new_line = false;
    while (self.current < self.stream.len) : (self.current += 1) {
        const ch = self.stream[self.current];

        if (isWhitespace(ch)) {
            break;
        }

        if (is_new_line) {
            if (!isWhitespace(ch)) {
                break;
            }
        }

        if (ch == '\n') {
            if (start < self.current) {
                break;
            } else {
                is_new_line = true;
            }
        }
    }

    const slice = self.stream[start..self.current];

    if (std.mem.eql(u8, slice, "build")) {
        return .init(.build, slice);
    } else if (std.mem.eql(u8, slice, "rule")) {
        return .init(.rule, slice);
    } else if (std.mem.eql(u8, slice, "=")) {
        return .init(.equals, slice);
    } else if (std.mem.eql(u8, slice, "\n")) {
        return .init(.new_line, slice);
    } else if (slice.len > 0) {
        return .init(.ident, slice);
    }

    return null;
}

fn skipWhitespaces(self: *Self) void {
    while (self.current < self.stream.len) : (self.current += 1) {
        if (!isWhitespace(self.stream[self.current])) {
            break;
        }
    }
}

fn isWhitespace(char: u8) bool {
    return char == ' ' or char == '\t' or char == '\r';
}

test "lexer" {
    const stream = 
    \\cflags = -Wall
    \\
    \\rule cc
    \\command = gcc $cflags -c $in -o $out
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
