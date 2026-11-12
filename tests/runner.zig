const builtin = @import("builtin");
const std = @import("std");

const Writer = struct {
    handle: *std.Io.Writer,

    fn print(self: Writer, comptime format: []const u8, args: anytype) !void {
        try self.handle.print(format ++ "\n", args);
        try self.handle.flush();
    }
};

pub fn main(init: std.process.Init) !void {
    std.testing.io_instance = .init(init.gpa, .{
        .argv0 = .init(init.minimal.args),
        .environ = init.minimal.environ,
    });
    defer std.testing.io_instance.deinit();

    std.testing.allocator_instance = .init(std.heap.page_allocator, .{
        .check_write_after_free = true,
    });
    defer _ = std.testing.allocator_instance.deinit();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const writer = Writer{ .handle = &stdout_file_writer.interface };

    try writer.print("Running 'shinobi' test framework", .{});

    var pass: i32 = 0;
    var fail: i32 = 0;

    const test_functions = builtin.test_functions;
    try writer.print("\nRunning {} tests...", .{test_functions.len});
    for (builtin.test_functions) |item| {
        item.func() catch |err| {
            try writer.print("Test '{s}' failed with error: {}", .{
                item.name,
                err,
            });

            if (@errorReturnTrace()) |trace| {
                std.debug.dumpErrorReturnTrace(trace);
            }

            fail += 1;
            continue;
        };

        pass += 1;
    }

    if (fail == 0) {
        try writer.print("All tests passed!", .{});
    }
}
