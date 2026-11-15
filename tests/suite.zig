const options = @import("options");
const shinobi = @import("shinobi");
const std = @import("std");

const g_allocator = std.testing.allocator;
const g_io = std.testing.io;

test "simple" {
    try generate(g_allocator, g_io, "ninja/simple.ninja");

    const script = try getBuildScript(g_allocator, g_io);
    defer g_allocator.free(script);

    try expectContents(script,
\\    const main = b.addExecutable(.{
\\        .name = "main",
\\        .root_module = b.createModule(.{
\\            .target = target,
\\            .optimize = optimize,
\\            .link_libc = true,
\\        }),
\\    });
\\    main.root_module.addCSourceFiles(.{
\\        .files = &.{
\\            "../src/main.c",
\\        },
\\        .flags = &.{
\\            "-Wall",
\\        },
\\    });
\\    b.installArtifact(main);
\\
);
}

test "include" {
    try generate(g_allocator, g_io, "ninja/include.ninja");

    const script = try getBuildScript(g_allocator, g_io);
    defer g_allocator.free(script);

    try expectContents(script,
\\    const clib = b.addLibrary(.{
\\        .name = "clib",
\\        .linkage = .static,
\\        .root_module = b.createModule(.{
\\            .target = target,
\\            .optimize = optimize,
\\            .link_libc = true,
\\        }),
\\    });
\\    clib.root_module.addCSourceFiles(.{
\\        .files = &.{
\\            "../src/clib.c",
\\        },
\\        .flags = &.{
\\            "-Wall",
\\            "-DEFINED_VALUE",
\\        },
\\    });
\\
\\    const main = b.addExecutable(.{
\\        .name = "main",
\\        .root_module = b.createModule(.{
\\            .target = target,
\\            .optimize = optimize,
\\            .link_libc = true,
\\        }),
\\    });
\\    main.root_module.addCSourceFiles(.{
\\        .files = &.{
\\            "../src/main.c",
\\        },
\\        .flags = &.{
\\            "-Wall",
\\            "-DEFINED_VALUE",
\\        },
\\    });
\\    main.root_module.linkLibrary(clib);
\\    b.installArtifact(main);
\\
);
}

test "subninja" {
    try generate(g_allocator, g_io, "ninja/subninja.ninja");

    const script = try getBuildScript(g_allocator, g_io);
    defer g_allocator.free(script);

    try expectContents(script,
\\    const clib = b.addLibrary(.{
\\        .name = "clib",
\\        .linkage = .static,
\\        .root_module = b.createModule(.{
\\            .target = target,
\\            .optimize = optimize,
\\            .link_libc = true,
\\        }),
\\    });
\\    clib.root_module.addCSourceFiles(.{
\\        .files = &.{
\\            "../src/clib.c",
\\        },
\\        .flags = &.{
\\            "-Wall",
\\        },
\\    });
\\
\\    const child = b.addLibrary(.{
\\        .name = "child",
\\        .linkage = .static,
\\        .root_module = b.createModule(.{
\\            .target = target,
\\            .optimize = optimize,
\\            .link_libc = true,
\\        }),
\\    });
\\    child.root_module.addCSourceFiles(.{
\\        .files = &.{
\\            "../src/clib.c",
\\        },
\\        .flags = &.{
\\            "-Wall",
\\            "-DEFINED_VALUE",
\\        },
\\    });
\\
\\    const main = b.addExecutable(.{
\\        .name = "main",
\\        .root_module = b.createModule(.{
\\            .target = target,
\\            .optimize = optimize,
\\            .link_libc = true,
\\        }),
\\    });
\\    main.root_module.addCSourceFiles(.{
\\        .files = &.{
\\            "../src/main.c",
\\        },
\\        .flags = &.{
\\            "-Wall",
\\            "-DEFINED_VALUE",
\\        },
\\    });
\\    main.root_module.linkLibrary(clib);
\\    main.root_module.linkLibrary(child);
\\    b.installArtifact(main);
\\
);
}

fn generate(allocator: std.mem.Allocator, io: std.Io, sub_path: []const u8) !void {
    const ninja_file = try getSubPath(allocator, sub_path);
    defer allocator.free(ninja_file);

    var shinobi_options = shinobi.Options{};
    try shinobi.generate(allocator, io, ninja_file, &shinobi_options);
}

fn getSubPath(allocator: std.mem.Allocator, sub_path: []const u8) ![]const u8 {
    return try std.fs.path.join(allocator, &.{
        options.root_dir,
        sub_path,
    });
}

fn getBuildScript(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    const path = try getSubPath(allocator, "ninja/build.zig");
    defer allocator.free(path);

    const file = try std.Io.Dir.openFileAbsolute(io, path, .{});
    defer file.close(io);

    var buffer: [1024]u8 = undefined;
    var reader = file.reader(io, &buffer);

    return try reader.interface.allocRemaining(allocator, .unlimited);
}

fn expectContents(src: []const u8, expect: []const u8) !void {
    const key = "b.standardOptimizeOption(.{});\n";
    const pos = std.mem.find(u8, src, key) orelse return;
    const end = std.mem.findLast(u8, src, "}") orelse return;

    const start = pos + key.len + 1;
    const contents = src[start..(end - 1)];

    try std.testing.expectEqualStrings(contents, expect);
}
