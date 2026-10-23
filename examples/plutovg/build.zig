const std = @import("std");
const shinobi = @import("shinobi.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    try shinobi.add_directory(b, "external/plutovg", .{
        .target = target,
        .configuration = optimize,
    });

    const plutovg_bindings = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("plutovg.zig"),
        .imports = &.{
            .{ .name = "plutovg", .module = b.modules.get("plutovg").? },
        },
    });

    const exe = b.addExecutable(.{
        .name = "smiley",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("main.zig"),
            .imports = &.{
                .{ .name = "plutovg", .module = plutovg_bindings },
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
}
