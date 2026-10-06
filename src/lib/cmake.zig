const builtin = @import("builtin");
const std = @import("std");

/// The build directory where cmake artifacts will be written.
pub const build_path = "Build";

/// Represents the configuration to be passed in via '-DCMAKE_BUILD_TYPE'.
pub const BuildType = enum {
    debug,
    release,
    rel_with_deb_info,
    min_size_rel,
    custom,

    pub fn fromOptimizeMode(mode: std.builtin.OptimizeMode) BuildType {
        return switch (mode) {
            .Debug => .debug,
            else => .release,
        };
    }

    pub fn toStr(self: BuildType) []const u8 {
        return switch (self) {
            .debug => "Debug",
            .release => "Release",
            .rel_with_deb_info => "RelWithDebInfo",
            .min_size_rel => "MinSizeRel",
            .custom => "",
        };
    }
};

/// List of options for controlling 'cmake' to generate a 'build.ninja' file.
pub const Options = struct {
    /// The build type to use
    build_type: BuildType = .release,

    /// Path containing the cmake executable
    bin_path: ?[]const u8 = null,

    /// Should more information about the 'cmake' command execution be printed?
    verbose: bool = false,
};

/// Result from generating a 'build.ninja' using 'cmake'.
pub const GenerateResult = struct {
    pub const fail = GenerateResult{};

    /// Did it succeed?
    success: bool = false,

    /// The caller owns this memory. Uses same allocator given to function.
    /// The path to the generated 'build.ninja' file.
    ninja_path: ?[]const u8 = null,

    pub fn deinit(self: GenerateResult, allocator: std.mem.Allocator) void {
        allocator.free(self.ninja_path);
    }
};

/// List of arguments to be passed to the 'cmake' command. Keeps track of arguments
/// that needed a memory allocation will be properly freed on 'deinit'.
const Arguments = struct {
    allocator: std.mem.Allocator,
    list: std.ArrayListUnmanaged([]const u8) = .empty,
    free: std.ArrayListUnmanaged(usize) = .empty,

    fn init(allocator: std.mem.Allocator) Arguments {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *Arguments) void {
        for (self.free.items) |index| {
            self.allocator.free(self.list.items[index]);
        }

        self.list.deinit(self.allocator);
        self.free.deinit(self.allocator);
    }

    fn append(self: *Arguments, arg: []const u8) !void {
        try self.list.append(self.allocator, arg);
    }

    fn appendFormat(self: *Arguments, comptime fmt: []const u8, args: anytype) !void {
        const buffer = try std.fmt.allocPrint(self.allocator, fmt, args);
        try self.list.append(self.allocator, buffer);
        try self.free.append(self.allocator, self.list.items.len - 1);
    }
};

pub fn generate(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    options: Options,
) !GenerateResult {
    std.log.info("Running 'cmake' to generate 'build.ninja' file.", .{});

    var arguments = Arguments.init(allocator);
    defer arguments.deinit();

    const bin_path = options.bin_path orelse "";
    try arguments.appendFormat("{s}{s}", .{ bin_path, exeName() });
    try arguments.append("-G Ninja");
    try arguments.append("-B");
    try arguments.appendFormat("{s}/{s}", .{ path, build_path });
    try arguments.append("-S");
    try arguments.append(path);
    try arguments.append("'-DCMAKE_C_COMPILER=zig cc'");
    try arguments.append("'-DCMAKE_CXX_COMPILER=zig c++'");
    try arguments.append("-DCMAKE_MAKE_PROGRAM=ninja");
    try arguments.appendFormat("-DCMAKE_BUILD_TYPE={s}", .{options.build_type.toStr()});

    var command = std.ArrayListUnmanaged(u8).empty;
    defer command.deinit(allocator);

    for (arguments.list.items) |arg| {
        try command.appendSlice(allocator, arg);
        try command.append(allocator, ' ');
    }

    std.log.info("Running command '{s}'", .{command.items});

    const result = std.process.run(allocator, io, .{
        .argv = arguments.list.items,
    }) catch |err| {
        switch (err) {
            std.process.RunError.FileNotFound => {
                std.log.err("'cmake' executable was not found!", .{});
                return .fail;
            },
            else => return err,
        }
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const dir_or_error = if (std.fs.path.isAbsolute(path))
        std.Io.Dir.openDirAbsolute(io, path, .{})
    else
        std.Io.Dir.cwd().openDir(io, path, .{});

    const dir = dir_or_error catch {
        printResult(result);
        return .fail;
    };
    defer dir.close(io);

    dir.access(io, build_path ++ "/build.ninja", .{}) catch |err| {
        std.log.err("Failed to generate 'build.ninja' file: {}", .{err});
        printResult(result);
        return .fail;
    };

    if (result.term != .exited or options.verbose) {
        printResult(result);
    }

    return .{
        .success = true,
        .ninja_path = try std.fmt.allocPrint(allocator, "{s}/{s}/build.ninja", .{ path, build_path }),
    };
}

fn exeName() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "cmake.exe",
        else => "cmake",
    };
}

fn printResult(result: std.process.RunResult) void {
    std.log.warn("stdout\n{s}", .{result.stdout});
    std.log.err("stderr\n{s}", .{result.stderr});
}
