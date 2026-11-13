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
    const test_runner = std.Build.Step.Compile.TestRunner{
        .path = b.path("tests/runner.zig"),
        .mode = .simple,
    };

    const test_lib = b.addTest(.{
        .name = "test-library",
        .root_module = lib,
        .test_runner = test_runner,
    });

    const test_root_dir = try std.fmt.allocPrint(b.allocator, "{f}/tests", .{b.root});
    defer b.allocator.free(test_root_dir);

    const test_suite_options = b.addOptions();
    test_suite_options.addOption([]const u8, "root_dir", test_root_dir);

    const test_suite = b.addTest(.{
        .name = "test-suite",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("tests/suite.zig"),
            .imports = &.{
                .{ .name = "shinobi", .module = lib },
            },
        }),
        .test_runner = test_runner,
    });
    test_suite.root_module.addOptions("options", test_suite_options);

    const test_step = b.step("test", "Run tests");
    const test_lib_artifact = b.addRunArtifact(test_lib);
    const test_suite_artifact = b.addRunArtifact(test_suite);
    test_step.dependOn(&test_lib_artifact.step);
    test_step.dependOn(&test_suite_artifact.step);

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
