const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const llvm_dep = b.dependency("llvm", .{
        .target = target,
        .optimize = optimize,
    });
    const llvm_mod = llvm_dep.module("llvm");

    // Create a module for the main source
    const exe_module = b.addModule("zen-main", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add LLVM module to main module
    exe_module.addImport("llvm", llvm_mod);

    // Zen compiler executable
    const exe = b.addExecutable(.{
        .name = "zenc",
        .root_module = exe_module,
    });

    b.installArtifact(exe);

    // Run step for the compiler
    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the Zen compiler");
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Test step
    const test_module = b.addModule("zen-test", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_tests = b.addTest(.{
        .root_module = test_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
