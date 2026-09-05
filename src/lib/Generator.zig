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

/// Represents a compilation unit which consists of all of the files needed
/// and the associated flags for compiling these files.
const Unit = struct {
    files: std.ArrayListUnmanaged([]const u8) = .empty,
    flags: std.StringHashMapUnmanaged(void) = .empty,

    fn deinit(self: *Unit, allocator: std.mem.Allocator) void {
        self.files.deinit(allocator);
        self.flags.deinit(allocator);
    }
};

/// A collection of compilation units.
const Units = struct {
    collection: std.ArrayListUnmanaged(Unit) = .empty,

    fn deinit(self: *Units, allocator: std.mem.Allocator) void {
        for (self.collection.items) |*unit| {
            unit.deinit(allocator);
        }
        self.collection.deinit(allocator);
    }
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

    var units = try gatherUnits(allocator, parser);
    defer units.deinit(allocator);

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
    try writeUnits(allocator, &writer.interface, units, dir);
    try writeFooter(&writer.interface);

    if (options.print_summary) {
        parser.printSummary();
    }
}

fn gatherUnits(allocator: std.mem.Allocator, parser: Parser) !Units {
    var units = Units{};

    for (parser.builds.items) |build| {
        const rule_name = build.rule orelse continue;
        const rule = parser.rules.get(rule_name) orelse continue;

        var files = std.ArrayListUnmanaged([]const u8).empty;
        for (build.inputs.items) |input| {
            if (!isValidFile(input)) {
                continue;
            }

            try files.append(allocator, input);
        }

        if (files.items.len == 0) {
            files.deinit(allocator);
            continue;
        }

        const flags = try getFlags(allocator, rule, build, parser);

        try units.collection.append(allocator, .{
            .files = files,
            .flags = flags,
        });
    }

    return units;
}

fn getFlags(
    allocator: std.mem.Allocator,
    rule: Rule,
    build: BuildStatement,
    parser: Parser,
) !std.StringHashMapUnmanaged(void) {
    var flags = std.StringHashMapUnmanaged(void).empty;

    const command = rule.variables.get("command") orelse return Error.InvalidRule;

    try parseFlags(allocator, command.value, &flags);

    var tokens = std.mem.tokenizeAny(u8, command.value, " ");
    while (tokens.next()) |token| {
        if (std.mem.startsWith(u8, token, "$")) {
            const name = token[1..];

            const variable: ?Variable = blk: {
                if (build.variables.get(name)) |v| break :blk v;
                if (rule.variables.get(name)) |v| break :blk v;
                if (parser.variables.get(name)) |v| break :blk v;
                break :blk null;
            };

            const v = variable orelse continue;
            try parseFlags(allocator, v.value, &flags);
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
        if (!isValidFlag(token)) continue;

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

fn writeCreateModule(writer: *std.Io.Writer) !void {
    try writer.print("    const module = b.createModule(.{{\n", .{});
    try writer.print("        .target = target,\n", .{});
    try writer.print("        .optimize = optimize,\n", .{});
    try writer.print("    }});\n", .{});
    try writer.flush();
}

fn writeUnits(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    units: Units,
    build_dir: []const u8,
) !void {
    for (units.collection.items) |unit| {
        try writer.print("    module.addCSourceFiles(.{{\n", .{});
        try writer.print("        .files = &.{{\n", .{});
        try writer.flush();

        for (unit.files.items) |file| {
            const relative = try std.fs.path.relative(allocator, ".", null, build_dir, file);
            defer allocator.free(relative);

            std.mem.replaceScalar(u8, relative, '\\', '/');

            try writer.print("            \"{s}\",\n", .{relative});
            try writer.flush();
        }

        try writer.print("        }},\n", .{});
        try writer.print("        .flags = &.{{\n", .{});

        var it = unit.flags.keyIterator();
        while (it.next()) |flag| {
            try writer.print("            \"{s}\",\n", .{flag.*});
            try writer.flush();
        }

        try writer.print("        }},\n", .{});
        try writer.print("    }});\n", .{});
        try writer.flush();
    }
}

fn isValidFile(file: []const u8) bool {
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

    var units = try gatherUnits(allocator, parser);
    defer units.deinit(allocator);

    try std.testing.expectEqual(3, units.collection.items.len);

    const unit1 = units.collection.items[0];
    try std.testing.expectEqual(1, unit1.files.items.len);
    try std.testing.expectEqualStrings("foo.c", unit1.files.items[0]);
    try std.testing.expectEqual(1, unit1.flags.count());
    try std.testing.expect(unit1.flags.contains("-Werror"));

    const unit2 = units.collection.items[1];
    try std.testing.expectEqual(2, unit2.files.items.len);
    try std.testing.expectEqualStrings("bar1.c", unit2.files.items[0]);
    try std.testing.expectEqualStrings("bar2.c", unit2.files.items[1]);
    try std.testing.expectEqual(1, unit2.flags.count());
    try std.testing.expect(unit2.flags.contains("-Wall"));

    const unit3 = units.collection.items[2];
    try std.testing.expectEqual(1, unit3.files.items.len);
    try std.testing.expectEqualStrings("test.c", unit3.files.items[0]);
    try std.testing.expectEqual(2, unit3.flags.count());
    try std.testing.expect(unit3.flags.contains("-Werror"));
    try std.testing.expect(unit3.flags.contains("-Wformat"));
}
