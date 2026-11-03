const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("shinobi.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "shinobi",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/cli/main.zig"),
            .imports = &.{
                .{ .name = "lib", .module = lib },
            },
        }),
    });

    b.installArtifact(exe);

    // Set up the 'run' step.
    const run_step = b.step("run", "Runs the application.");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    // Set up the 'test' step.
    const test_step = b.step("test", "Run tests");
    const lib_test = b.addTest(.{
        .root_module = lib,
    });
    const lib_test_run = b.addRunArtifact(lib_test);
    test_step.dependOn(&lib_test_run.step);

    const exe_test = b.addTest(.{
        .root_module = exe.root_module,
    });
    const exe_test_run = b.addRunArtifact(exe_test);
    test_step.dependOn(&exe_test_run.step);

    try copyLibraryToExamples(b);
}

fn copyLibraryToExamples(b: *std.Build) !void {
    const root_path_cache = try std.fmt.allocPrint(b.allocator, "{f}", .{b.root});
    defer b.allocator.free(root_path_cache);

    const root_lib_path = try std.fs.path.join(b.allocator, &.{ root_path_cache, "shinobi.zig" });
    defer b.allocator.free(root_lib_path);

    std.log.info("Copying 'shinobi.zig' file to examples...", .{});

    const plutovg_path = try std.fs.path.join(b.allocator, &.{
        root_path_cache,
        "examples/plutovg/shinobi.zig",
    });
    defer b.allocator.free(plutovg_path);

    try std.Io.Dir.copyFileAbsolute(root_lib_path, plutovg_path, b.graph.io, .{});
}
