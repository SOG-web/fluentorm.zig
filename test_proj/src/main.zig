const std = @import("std");

const test_proj = @import("test_proj");

const models = @import("models/generated/root.zig");

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    try test_proj.bufferedPrint();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var user = models.Users.query;
    _ = user.select(&.{.id}).where(.{
        .field = .name,
        .operator = .eq,
        .value = .{ .string = "rou" },
    }).where(.{
        .field = .is_active,
        .operator = .eq,
        .value = .{ .boolean = true },
    });
    _ = user.include(.{
        .comments = .{
            .model_name = .comments,
            .where = &.{
                .{
                    .where_type = .@"and",
                    .field = .user_id,
                    .operator = .eq,
                    .value = .{ .string = "rou" },
                },
                .{
                    .where_type = .@"or",
                    .field = .is_approved,
                    .operator = .eq,
                    .value = .{ .boolean = true },
                },
                .{
                    .where_type = .@"and",
                    .field = .user_id,
                    .operator = .eq,
                    .value = .{ .string = "rou" },
                },
                .{
                    .where_type = .@"and",
                    .field = .user_id,
                    .operator = .eq,
                    .value = .{ .string = "rou" },
                },
                .{
                    .where_type = .@"or",
                    .field = .is_approved,
                    .operator = .eq,
                    .value = .{ .boolean = true },
                },
            },
        },
    });

    const sql = try user.buildSql(arena.allocator());
    std.debug.print("testing {s}\n", .{sql});
}
