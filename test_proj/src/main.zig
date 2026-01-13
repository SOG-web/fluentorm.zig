const std = @import("std");

const test_proj = @import("test_proj");

const models = @import("models/generated/root.zig");

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    try test_proj.bufferedPrint();

    var user = models.Users.query;
    _ = user.select(&.{.id}).where(.{
        .field = .name,
        .operator = .eq,
        .value = "rou",
    });
}
