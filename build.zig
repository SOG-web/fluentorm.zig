const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Schema type definitions module
    const schema_mod = b.addModule("schema", .{
        .root_source_file = b.path("src/schema.zig"),
        .target = target,
    });

    const pg = b.dependency("pg", .{
        .target = target,
        .optimize = optimize,
    });

    // Generator executable - Standalone model generator
    const gen_exe = b.addExecutable(.{
        .name = "zig-model-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/generate_model.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "schema", .module = schema_mod },
                .{ .name = "pg", .module = pg.module("pg") },
            },
        }),
    });

    b.installArtifact(gen_exe);

    // Run step for local testing
    const run_cmd = b.addRunArtifact(gen_exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the generator");
    run_step.dependOn(&run_cmd.step);

    // Help step
    const help_step = b.step("help", "Show help information");
    _ = help_step;
}
