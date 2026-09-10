const Artifact = @import("Artifact.zig");
const BuildStatement = @import("BuildStatement.zig");
const Parser = @import("Parser.zig");
const Rule = @import("Rule.zig");
const std = @import("std");
const Variable = @import("Variable.zig");

/// List of possible errors.
pub const Error = error{
    InvalidRule,
};

/// List of options to control generator.
pub const Options = struct {
    print_summary: bool = false,
};

/// Manages parsing a 'ninja' file and emitting a 'build.zig' file.
const Self = @This();

pub fn generate(
    self: Self,
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    options: Options,
) !void {
    _ = self;

    var parser = try Parser.initFile(allocator, io, path);
    defer parser.deinit(allocator, io);

    try parser.begin(allocator, io);

    std.log.info("Generating 'build.zig' file", .{});

    const dir = std.fs.path.dirname(path) orelse {
        std.log.err("Failed to retrieve directory of ninja file '{s}'!", .{path});
        return;
    };

    const output_path = try std.fs.path.join(allocator, &.{ dir, "build.zig" });
    defer allocator.free(output_path);

    var artifacts = try gatherArtifacts(allocator, parser);
    defer artifacts.deinit(allocator);

    const file = if (std.fs.path.isAbsolute(output_path))
        try std.Io.Dir.createFileAbsolute(io, output_path, .{})
    else
        try std.Io.Dir.cwd().createFile(io, output_path, .{});
    defer file.close(io);

    var buffer: [1024]u8 = undefined;
    var writer = file.writer(io, &buffer);

    try writeHeader(&writer.interface);
    try writeBuildVars(&writer.interface);
    try writeArtifacts(allocator, &writer.interface, artifacts, dir);
    try writeFooter(&writer.interface);

    if (options.print_summary) {
        parser.printSummary();
    }
}

fn gatherArtifacts(allocator: std.mem.Allocator, parser: Parser) !Artifact.Collection {
    var artifacts = Artifact.Collection{};

    for (parser.builds.items) |build| {
        var artifact = Artifact{};
        artifact.flags = try getFlags(allocator, build, parser);

        var is_compile_command = false;
        var it = artifact.flags.keyIterator();
        while (it.next()) |flag| {
            if (std.mem.eql(u8, flag.*, "-c")) {
                is_compile_command = true;
                break;
            }
        }

        artifact.output_type = blk: {
            if (is_compile_command) {
                break :blk .object;
            }

            for (build.outputs.items) |output| {
                const ext = std.fs.path.extension(output);
                if (std.mem.eql(u8, ext, ".lib") or std.mem.eql(u8, ext, ".a")) {
                    break :blk .library;
                }
            }

            break :blk .executable;
        };

        for (build.inputs.items) |input| {
            switch (artifact.output_type) {
                .object => {
                    if (isValidSourceFile(input)) {
                        try artifact.inputs.append(allocator, input);
                    }
                },
                else => {
                    try artifact.inputs.append(allocator, input);
                },
            }
        }

        if (artifact.inputs.items.len == 0) {
            artifact.deinit(allocator);
            continue;
        }

        for (build.outputs.items) |output| {
            try artifact.outputs.append(allocator, output);
        }

        it = artifact.flags.keyIterator();
        while (it.next()) |flag| {
            if (!isValidFlag(flag.*)) {
                _ = artifact.flags.remove(flag.*);
            }
        }

        try artifacts.add(allocator, artifact);
    }

    return artifacts;
}

fn getFlags(
    allocator: std.mem.Allocator,
    build: BuildStatement,
    parser: Parser,
) !std.StringHashMapUnmanaged(void) {
    var flags = std.StringHashMapUnmanaged(void).empty;

    const command = getVariable("command", build, parser) orelse return flags;

    try parseFlags(allocator, command.value, &flags);

    var tokens = std.mem.tokenizeAny(u8, command.value, " ");
    while (tokens.next()) |token| {
        if (std.mem.startsWith(u8, token, "$")) {
            const name = token[1..];

            const variable = getVariable(name, build, parser) orelse continue;
            try parseFlags(allocator, variable.value, &flags);
        }
    }

    return flags;
}

fn parseFlags(
    allocator: std.mem.Allocator,
    stream: []const u8,
    flags: *std.StringHashMapUnmanaged(void),
    
) !void {
    var tokens = std.mem.tokenizeAny(u8, stream, " ");
    while (tokens.next()) |token| {
        try flags.put(allocator, token, {});
    }
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

fn writeAddModule(writer: *std.Io.Writer, name: []const u8) !void {
    try writer.print("    const {s} = b.addModule(\"{s}\", .{{\n", .{ name, name });
    try writer.print("        .target = target,\n", .{});
    try writer.print("        .optimize = optimize,\n", .{});
    try writer.print("    }});\n", .{});
    try writer.flush();
}

fn writeArtifacts(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    artifacts: Artifact.Collection,
    build_dir: []const u8,
) !void {
    for (artifacts.list.items) |artifact| {
        if (artifact.output_type != .library) continue;

        const output_path = artifact.getOutputName() orelse "module";
        const name = std.fs.path.stem(output_path);
        try writeAddModule(writer, name);

        for (artifact.inputs.items) |input| {
            const input_artifact = artifacts.getByOutput(input) orelse continue;
            if (input_artifact.inputs.items.len == 0) continue;

            try writer.print("    {s}.addCSourceFiles(.{{\n", .{name});
            try writer.print("        .files = &.{{\n", .{});
            try writer.flush();

            for (input_artifact.inputs.items) |file| {
                const relative = try std.fs.path.relative(allocator, ".", null, build_dir, file);
                defer allocator.free(relative);

                std.mem.replaceScalar(u8, relative, '\\', '/');

                try writer.print("            \"{s}\",\n", .{relative});
                try writer.flush();
            }

            try writer.print("        }},\n", .{});
            try writer.print("        .flags = &.{{\n", .{});

            var it = input_artifact.flags.keyIterator();
            while (it.next()) |flag| {
                try writer.print("            \"{s}\",\n", .{flag.*});
                try writer.flush();
            }

            try writer.print("        }},\n", .{});
            try writer.print("    }});\n", .{});
            try writer.flush();
        }

    }
}

fn isValidSourceFile(file: []const u8) bool {
    const stem = std.fs.path.stem(file);
    if (std.mem.eql(u8, stem, "CMakeCCompilerABI") or
        std.mem.eql(u8, stem, "CMakeCXXCompilerABI"))
    {
        return false;
    }

    const ext = std.fs.path.extension(file);
    if (!(std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".cpp"))) {
        return false;
    }

    return true;
}

fn isValidFlag(flag: []const u8) bool {
    if (!(std.mem.startsWith(u8, flag, "-") or std.mem.startsWith(u8, flag, "/"))) {
        return false;
    }

    // Ignore 'compile' and 'output' flag
    if (std.mem.eql(u8, flag, "-c")) return false;
    if (std.mem.eql(u8, flag, "-o")) return false;

    return true;
}

fn getVariable(name: []const u8, build: BuildStatement, parser: Parser) ?Variable {
    if (build.variables.get(name)) |variable| {
        return variable;
    }

    const rule_name = build.rule orelse return null;
    const rule = parser.rules.get(rule_name) orelse return null;
    if (rule.variables.get(name)) |variable| {
        return variable;
    }

    if (parser.variables.get(name)) |variable| {
        return variable;
    }

    return null;
}

test "generator gather files and flags" {
    const stream =
        \\cflags = -Wall
        \\
        \\rule cc
        \\    command = gcc $cflags -c $in -o $out
        \\    rulevar = 0
        \\
        \\rule cc2
        \\    command = gcc $cflags -c $in -o $out
        \\    cflags = -Werror -Wformat
        \\
        \\build foo.o: cc foo.c
        \\    cflags = -Werror
        \\
        \\build bar.o: cc bar1.c bar2.c
        \\
        \\build test.o: cc2 test.c
    ;

    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var parser = Parser.initStream(stream);
    defer parser.deinit(allocator, io);

    try parser.begin(allocator, io);

    var artifacts = try gatherArtifacts(allocator, parser);
    defer artifacts.deinit(allocator);

    try std.testing.expectEqual(3, artifacts.list.items.len);


    const artifact1 = artifacts.list.items[0];
    try std.testing.expectEqual(1, artifact1.inputs.items.len);
    try std.testing.expectEqualStrings("foo.c", artifact1.inputs.items[0]);
    try std.testing.expectEqual(1, artifact1.flags.count());
    try std.testing.expect(artifact1.flags.contains("-Werror"));

    const artifact2 = artifacts.list.items[1];
    try std.testing.expectEqual(2, artifact2.inputs.items.len);
    try std.testing.expectEqualStrings("bar1.c", artifact2.inputs.items[0]);
    try std.testing.expectEqualStrings("bar2.c", artifact2.inputs.items[1]);
    try std.testing.expectEqual(1, artifact2.flags.count());
    try std.testing.expect(artifact2.flags.contains("-Wall"));

    const artifact3 = artifacts.list.items[2];
    try std.testing.expectEqual(1, artifact3.inputs.items.len);
    try std.testing.expectEqualStrings("test.c", artifact3.inputs.items[0]);
    try std.testing.expectEqual(2, artifact3.flags.count());
    try std.testing.expect(artifact3.flags.contains("-Werror"));
    try std.testing.expect(artifact3.flags.contains("-Wformat"));
}
