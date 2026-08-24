pub const Generator = @import("Generator.zig");
pub const Parser = @import("Parser.zig");

const std = @import("std");

test "lib" {
    _ = @import("Lexer.zig");
    _ = @import("Parser.zig");
}
