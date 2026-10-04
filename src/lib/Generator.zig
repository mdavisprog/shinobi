const Artifact = @import("Artifact.zig");
const BuildStatement = @import("BuildStatement.zig");
const cmake = @import("cmake.zig");
const Parser = @import("Parser.zig");
const Rule = @import("Rule.zig");
const std = @import("std");
const Variable = @import("Variable.zig");

/// List of possible errors.
pub const Error = error{
    InvalidRule,
};

/// List of options to control the generator.
pub const Options = struct {
    /// Prints the summary of what has been parsed.
    print_summary: bool = false,

    /// The configuration used to generate a 'build.ninja' file if the generator
    /// is given a directory path and the directory contains a 'CMakeLists.txt' file.
    configuration: std.builtin.OptimizeMode = .ReleaseFast,

    /// Path containing the cmake binary.
    cmake_bin_path: ?[]const u8 = null,
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

    const resolved_path = try resolvePath(allocator, io, path, options);
    defer allocator.free(resolved_path);

    std.log.info("Attempting to parse ninja file '{s}'", .{resolved_path});

    var parser = try Parser.initFile(allocator, io, resolved_path);
    defer parser.deinit(allocator, io);

    try parser.begin(allocator, io);

    std.log.info("Generating 'build.zig' file", .{});

    const dir = std.fs.path.dirname(resolved_path) orelse {
        std.log.err("Failed to retrieve directory of ninja file '{s}'!", .{resolved_path});
        return;
    };

    const absolute_dir = try std.Io.Dir.cwd().realPathFileAlloc(io, dir, allocator);
    defer allocator.free(absolute_dir);

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
    try writeArtifacts(allocator, &writer.interface, artifacts, absolute_dir);
    try writeFooter(&writer.interface);

    if (options.print_summary) {
        parser.printSummary();
    }
}

fn gatherArtifacts(allocator: std.mem.Allocator, parser: Parser) !Artifact.Collection {
    var artifacts = Artifact.Collection{};

    for (parser.builds.items) |build| {
        var artifact = Artifact{};
        artifact.output_type = .other;
        artifact.flags = try getFlags(allocator, build, parser);

        var has_compile_command = false;
        var has_link_command = false;
        var has_clang_command = false;

        var it = artifact.flags.keyIterator();
        while (it.next()) |flag| {
            if (std.mem.eql(u8, flag.*, "-c")) {
                has_compile_command = true;
            }

            if (std.mem.containsAtLeast(u8, flag.*, 1, "llvm-ar")) {
                has_link_command = true;
            }

            if (std.mem.containsAtLeast(u8, flag.*, 1, "bin/ar")) {
                has_link_command = true;
            }

            if (std.mem.containsAtLeast(u8, flag.*, 1, "clang")) {
                has_clang_command = true;
            }
        }

        artifact.output_type = if (has_compile_command)
            .object
        else if (has_link_command)
            .library
        else if (has_clang_command)
            .executable
        else
            .other;

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

fn writeAddExecutable(writer: *std.Io.Writer, name: []const u8) !void {
    try writer.print("    const {s} = b.addExecutable(.{{\n", .{name});
    try writer.print("        .name = \"{s}\",\n", .{name});
    try writer.print("        .root_module = b.createModule(.{{\n", .{});
    try writer.print("            .target = target,\n", .{});
    try writer.print("            .optimize = optimize,\n", .{});
    try writer.print("            .link_libc = true,\n", .{});
    try writer.print("        }}),\n", .{});
    try writer.print("    }});\n", .{});
    try writer.flush();
}

fn writeArtifacts(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    artifacts: Artifact.Collection,
    build_dir: []const u8,
) !void {
    // Write all libraries first
    for (artifacts.list.items) |artifact| {
        if (artifact.output_type != .library) continue;

        try writeArtifact(allocator, writer, artifact, artifacts, build_dir);
        try writer.print("\n", .{});
    }

    // Write all executables next
    for (artifacts.list.items) |artifact| {
        if (artifact.output_type != .executable) continue;

        try writeArtifact(allocator, writer, artifact, artifacts, build_dir);
    }
}

fn writeArtifact(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    artifact: Artifact,
    artifacts: Artifact.Collection,
    build_dir: []const u8,
) !void {
    const name = artifact.getOutputName();

    switch (artifact.output_type) {
        .executable => {
            try writeAddExecutable(writer, name);
        },
        .library => {
            try writeAddModule(writer, name);
        },
        else => return,
    }

    var input_artifacts = std.ArrayListUnmanaged(Artifact).empty;
    defer input_artifacts.deinit(allocator);

    // Grab all artifacts needed to generate the library artifact.
    outer: for (artifact.inputs.items) |input| {
        const input_artifact = artifacts.getByOutput(input) orelse continue;
        if (input_artifact.inputs.items.len == 0) continue;

        for (input_artifact.inputs.items) |file| {
            if (!isValidSourceFile(file)) continue :outer;
        }

        try input_artifacts.append(allocator, input_artifact);
    }

    var written = std.ArrayListUnmanaged(Artifact).empty;
    defer written.deinit(allocator);

    var includes = std.ArrayListUnmanaged([]const u8).empty;
    defer includes.deinit(allocator);

    outer: for (input_artifacts.items) |input_artifact| {
        var flags = input_artifact.flags.keyIterator();
        while (flags.next()) |flag| {
            if (!std.mem.startsWith(u8, flag.*, "-I")) {
                continue;
            }

            const path = flag.*[2..];

            var found = false;
            for (includes.items) |include| {
                if (std.mem.eql(u8, path, include)) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                try includes.append(allocator, path);
            }
        }

        for (written.items) |item| {
            if (item.hasSameOutputs(input_artifact)) continue :outer;
        }

        try writer.print("    {s}{s}.addCSourceFiles(.{{\n", .{
            name,
            if (artifact.output_type == .executable) ".root_module" else "",
        });
        try writer.print("        .files = &.{{\n", .{});
        try writer.flush();

        try writeInputs(allocator, writer, input_artifact, build_dir);
        try written.append(allocator, input_artifact);

        for (input_artifacts.items) |inner| {
            if (input_artifact.hasSameOutputs(inner)) continue;

            if (input_artifact.hasSameFlags(inner)) {
                try writeInputs(allocator, writer, inner, build_dir);
                try written.append(allocator, inner);
            }
        }

        try writer.print("        }},\n", .{});
        try writer.print("        .flags = &.{{\n", .{});

        var it = input_artifact.flags.keyIterator();
        while (it.next()) |flag| {
            if (std.mem.startsWith(u8, flag.*, "-I")) {
                continue;
            }

            try writer.print("            \"{s}\",\n", .{flag.*});
            try writer.flush();
        }

        try writer.print("        }},\n", .{});
        try writer.print("    }});\n", .{});
        try writer.flush();

        try writeImports(allocator, writer, artifact);
    }

    for (includes.items) |include| {
        const relative = try std.fs.path.relative(allocator, ".", null, build_dir, include);
        defer allocator.free(relative);

        std.mem.replaceScalar(u8, relative, '\\', '/');

        try writer.print("    {s}{s}.addIncludePath(b.path(\"{s}\"));\n", .{
            artifact.getOutputName(),
            if (artifact.output_type == .executable) ".root_module" else "",
            relative,
        });
    }

    if (artifact.output_type == .executable) {
        try writer.print("    b.installArtifact({s});\n", .{name});
        try writer.flush();
    }
}

fn writeInputs(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    artifact: Artifact,
    build_dir: []const u8,
) !void {
    for (artifact.inputs.items) |file| {
        const relative = try std.fs.path.relative(allocator, ".", null, build_dir, file);
        defer allocator.free(relative);

        std.mem.replaceScalar(u8, relative, '\\', '/');

        try writer.print("            \"{s}\",\n", .{relative});
        try writer.flush();
    }
}

fn writeImports(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    artifact: Artifact,
) !void {
    switch (artifact.output_type) {
        .executable, .library => {},
        else => return,
    }

    var added = std.StringHashMapUnmanaged(void).empty;
    defer added.deinit(allocator);

    for (artifact.inputs.items) |input| {
        const ext = std.fs.path.extension(input);
        if (std.mem.eql(u8, ext, ".lib") or std.mem.eql(u8, ext, ".a")) {
            const name = std.fs.path.stem(input);

            if (added.contains(name)) continue;
            try added.put(allocator, name, {});

            try writer.print("    {s}{s}.addImport(\"{s}\", {s});\n", .{
                artifact.getOutputName(),
                if (artifact.output_type == .executable) ".root_module" else "",
                name,
                name,
            });
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
    if (std.mem.eql(u8, flag, "--dependent-lib=msvcrt")) return false;
    if (std.mem.eql(u8, flag, "-D_MT")) return false;
    if (std.mem.eql(u8, flag, "-O3")) return false;
    if (std.mem.eql(u8, flag, "-MT")) return false;
    if (std.mem.eql(u8, flag, "-Xclang")) return false;
    if (std.mem.eql(u8, flag, "-D_DLL")) return false;
    if (std.mem.eql(u8, flag, "-DNDEBUG")) return false;
    if (std.mem.eql(u8, flag, "-MD")) return false;
    if (std.mem.eql(u8, flag, "-MF")) return false;

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

fn resolvePath(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    options: Options,
) ![]const u8 {
    // Check if given path is a 'build.ninja' file or a directory.
    const extension = std.fs.path.extension(path);
    if (std.mem.eql(u8, extension, ".ninja")) {
        return allocator.dupe(u8, path);
    } else {
        const open_options = std.Io.Dir.OpenOptions{ .iterate = true };
        const dir = if (std.fs.path.isAbsolute(path))
            try std.Io.Dir.openDirAbsolute(io, path, open_options)
        else
            try std.Io.Dir.cwd().openDir(io, path, open_options);

        defer dir.close(io);

        var it = dir.iterate();
        while (try it.next(io)) |entry| {
            if (entry.kind != .file) continue;

            if (std.mem.eql(u8, entry.name, "build.ninja")) {
                std.log.info("Found 'build.ninja' file in given path.", .{});
                return std.fs.path.join(allocator, &.{ path, entry.name });
            } else if (std.mem.eql(u8, entry.name, "CMakeLists.txt")) {
                const cmake_options = cmake.Options{
                    .build_type = .fromOptimizeMode(options.configuration),
                    .bin_path = options.cmake_bin_path,
                };
                const result = try cmake.generate(
                    allocator,
                    io,
                    path,
                    cmake_options,
                );

                return result.ninja_path orelse std.Io.File.OpenError.FileNotFound;
            }
        }
    }

    return std.Io.File.OpenError.FileNotFound;
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
