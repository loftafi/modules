const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_filters = b.option([]const []const u8, "test-filter", "Skip tests that do not match any filter") orelse &[0][]const u8{};

    const praxis = b.dependency("praxis", .{});
    const praxis_module = praxis.module("praxis");

    const modules = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    modules.addImport("praxis", praxis_module);

    const cmd = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    cmd.addImport("praxis", praxis_module);
    cmd.addImport("modules", modules);

    const exe = b.addExecutable(.{
        .name = "modules",
        .root_module = cmd,
    });
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_module = modules,
        .filters = test_filters,
    });
    const run_tests = b.addRunArtifact(tests);

    const cmd_test = b.addTest(.{
        .root_module = cmd,
        .filters = test_filters,
    });
    const run_cmd_test = b.addRunArtifact(cmd_test);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_cmd_test.step);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Generate docs into zig-out/docs");
    docs_step.dependOn(&install_docs.step);
}
