const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/lib/root.zig"),
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

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

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

}
