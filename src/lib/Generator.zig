const BuildStatement = @import("BuildStatement.zig");
const Parser = @import("Parser.zig");
const std = @import("std");

/// Manages parsing a 'ninja' file and emitting a 'build.zig' file.
const Self = @This();

pub fn generate(
    self: Self,
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !void {
    _ = self;

    var parser = try Parser.initFile(allocator, io, path);
    defer parser.deinit(allocator, io);

    try parser.begin(allocator);

    std.log.info("Generating 'build.zig' file", .{});

    const dir = std.fs.path.dirname(path) orelse {
        std.log.err("Failed to retrieve directory of ninja file '{s}'!", .{path});
        return;
    };

    const output_path = try std.fs.path.join(allocator, &.{ dir, "build.zig" });
    defer allocator.free(output_path);

    const file = if (std.fs.path.isAbsolute(output_path))
        try std.Io.Dir.createFileAbsolute(io, output_path, .{})
    else
        try std.Io.Dir.cwd().createFile(io, output_path, .{});
    defer file.close(io);

    var buffer: [1024]u8 = undefined;
    var writer = file.writer(io, &buffer);

    try writeHeader(&writer.interface);
    try writeBuildVars(&writer.interface);
    try writeCreateModule(&writer.interface);
    try writeInputs(&writer.interface, parser.builds);
    try writeFooter(&writer.interface);
}

fn writeHeader(writer: *std.Io.Writer) !void {
    try writer.print("const std = @import(\"std\");\n", .{});
    try writer.print("\n", .{});
    try writer.print("pub fn build(b: *std.Build) !void {{\n", .{});
    try writer.flush();
}

fn writeFooter(writer: *std.Io.Writer) !void {
    try writer.print("}}\n", .{});
    try writer.flush();
}

fn writeBuildVars(writer: *std.Io.Writer) !void {
    try writer.print("    const target = b.standardTargetOptions(.{{}});\n", .{});
    try writer.print("    const optimize = b.standardOptimizeOption(.{{}});\n\n", .{});
    try writer.flush();
}

fn writeCreateModule(writer: *std.Io.Writer) !void {
    try writer.print("    const module = b.createModule(.{{\n", .{});
    try writer.print("        .target = target,\n", .{});
    try writer.print("        .optimize = optimize,\n", .{});
    try writer.print("    }});\n", .{});
    try writer.flush();
}

fn writeInputs(writer: *std.Io.Writer, builds: std.ArrayListUnmanaged(BuildStatement)) !void {
    try writer.print("    module.addCSourceFiles(.{{\n", .{});
    try writer.print("        .files = &.{{\n", .{});
    try writer.flush();

    for (builds.items) |build| {
        for (build.inputs.items) |input| {
            const ext = std.fs.path.extension(input);
            if (!(std.mem.eql(u8, ext, ".c") or
                std.mem.eql(u8, ext, ".cpp"))) {
                continue;
            }

            const stem = std.fs.path.stem(input);
            if (std.mem.eql(u8, stem, "CMakeCCompilerABI") or
                std.mem.eql(u8, stem, "CMakeCXXCompilerABI")) {
                continue;
            }

            try writer.print("            \"{s}\",\n", .{input});
            try writer.flush();
        }
    }

    try writer.print("        }},\n", .{});
    try writer.print("        .flags = &.{{\n", .{});
    try writer.print("        }},\n", .{});
    try writer.print("    }});\n", .{});
    try writer.flush();
}
