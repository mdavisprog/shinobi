const lib = @import("lib");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();

    var maybe_path: ?[]const u8 = null;
    var options = lib.Generator.Options{};

    var index: usize = 0;
    while (args.next()) |arg| : (index += 1) {
        if (index == 1) {
            maybe_path = arg;
        }

        if (std.mem.eql(u8, arg, "--print-summary")) {
            options.print_summary = true;
        }
    }

    const path = maybe_path orelse {
        std.log.info("Please specify a 'build.ninja' file as the first argument.", .{});
        return;
    };

    const generator = lib.Generator{};

    std.log.info("Attempting to parse ninja file '{s}'", .{path});

    generator.generate(allocator, io, path, options) catch |err| {
        if (err == std.Io.File.OpenError.FileNotFound) {
            std.log.err("File '{s}' doesn't exist!", .{path});
        } else {
            return err;
        }
    };
}
