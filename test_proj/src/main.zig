const std = @import("std");

const fluentorm = @import("fluentorm");
const pg = @import("pg");
const test_proj = @import("test_proj");

const Executor = @import("models/generated/executor.zig").Executor;
const models = @import("models/generated/root.zig").Client;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 10 }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // 1. Initialize DB Pool
    const pool = try pg.Pool.init(allocator, .{
        .size = 5,
        .connect = .{
            .host = "localhost",
            .port = 5432,
        },
        .auth = .{
            .username = "postgres",
            .password = "postgres",
            .database = "fluentorm",
        },
    });
    defer pool.deinit();

    const db = Executor.fromPool(pool);

    // 2. Seed Data
    std.debug.print("Seeding data...\n", .{});

    // Clear existing data (optional, but good for a clean example)
    try models.Comments.truncate(db);
    std.debug.print("Truncated comments\n", .{});
    try models.Posts.truncate(db);
    std.debug.print("Truncated posts\n", .{});
    try models.Users.truncate(db);
    std.debug.print("Truncated users\n", .{});

    std.debug.print("Seeding new data...\n", .{});

    const user_id = try models.Users.insert(db, allocator, models.Users.CreateInput{
        .name = "rou",
        .email = "rou@example.com",
        .password_hash = "hashed_password",
        .bid = null,
        .is_active = true,
    });
    defer allocator.free(user_id);

    std.debug.print("Seeding new data 2...\n", .{});

    const user_id_hex = try pg.uuidToHex(&user_id[0..16].*);

    std.debug.print("User ID: {s}\n", .{user_id_hex});

    const post_id = try models.Posts.insert(db, allocator, models.Posts.CreateInput{
        .title = "Hello Zig",
        .content = "Zig is awesome!",
        .user_id = &user_id_hex,
        .is_published = true,
    });
    defer allocator.free(post_id);

    std.debug.print("Seeding new data 3...\n", .{});

    const post_id_hex = try pg.uuidToHex(&post_id[0..16].*);

    const comment_id1 = try models.Comments.insert(db, allocator, models.Comments.CreateInput{
        .post_id = &post_id_hex,
        .user_id = &user_id_hex,
        .content = "This is a comment by rou",
        .is_approved = true,
    });
    defer allocator.free(comment_id1);

    const comment_id2 = try models.Comments.insert(db, allocator, models.Comments.CreateInput{
        .post_id = &post_id_hex,
        .user_id = &user_id_hex,
        .content = "Another one",
        .is_approved = false,
    });
    defer allocator.free(comment_id2);

    const comment_id3 = try models.Comments.insert(db, allocator, models.Comments.CreateInput{
        .post_id = &post_id_hex,
        .user_id = &user_id_hex,
        .content = "Another one approved",
        .is_approved = true,
    });
    defer allocator.free(comment_id3);

    // 3. Query with Include
    std.debug.print("Querying with include...\n", .{});

    var query = models.Users.query();
    defer query.deinit();
    _ = query.where(.{
        .field = .name,
        .operator = .eq,
        .value = .{ .string = "rou" },
    });

    _ = query.include(.{
        .comments = .{
            .model_name = .comments,
            .where = &.{
                .{
                    .where_type = .@"and",
                    .field = .is_approved,
                    .operator = .eq,
                    .value = .{ .boolean = true },
                },
            },
        },
    });

    // We use fetchWithRel to correctly parse the JSONB columns into slices of models
    const users_with_comments = try query.fetchWithRel(
        models.Rel.Users.UsersWithComments,
        db,
        arena_allocator,
        .{},
    );

    for (users_with_comments) |u| {
        const id_hex = try pg.uuidToHex(u.id);
        std.debug.print("User: {s} (ID: {s})\n", .{ u.name, &id_hex });
        if (u.comments) |comments| {
            for (comments) |c| {
                std.debug.print("  - Comment: {s} (Approved: {any})\n", .{ c.content, c.is_approved });
            }
        } else {
            std.debug.print("  - No comments found.\n", .{});
        }
    }

    // 4. Test fetch() (standard models)
    std.debug.print("\n--- Testing fetch() ---\n", .{});
    var query_fetch = models.Users.query();
    defer query_fetch.deinit();
    const all_users = try query_fetch.fetch(db, arena_allocator, .{});
    std.debug.print("Found {d} users via fetch().\n", .{all_users.len});
    for (all_users) |u| {
        std.debug.print(" - User: {s} (Email: {s})\n", .{ u.name, u.email });
    }

    // 5. Test fetchAs() with custom projection
    std.debug.print("\n--- Testing fetchAs() with custom select and include ---\n", .{});
    const UserSummary = struct {
        name: []const u8,
        comment_count: i64,
    };

    var query_as = models.Users.query();
    defer query_as.deinit();
    _ = query_as
        .select(&.{.name})
        .selectRaw("(SELECT count(*) FROM comments WHERE comments.user_id = users.id) AS comment_count");

    const summaries = try query_as.fetchAs(UserSummary, db, arena_allocator, .{});
    for (summaries) |s| {
        std.debug.print("Summary -> User: {s}, Comments: {d}\n", .{ s.name, s.comment_count });
    }

    // 6. Test fetchAs() using include and custom select
    std.debug.print("\n--- Testing fetchAs() with include and JSON string result ---\n", .{});
    const UserWithJsonComments = struct {
        name: []const u8,
        comments: ?[]const u8, // The jsonb_agg result as a raw string
    };

    var query_as_rel = models.Users.query();
    defer query_as_rel.deinit();
    _ = query_as_rel
        .select(&.{.name})
        .include(.{
        .comments = .{
            .model_name = .comments,
            .select = &.{.content},
            .where = &.{
                .{ .field = .is_approved, .operator = .eq, .value = .{ .boolean = true } },
            },
        },
    });

    const results = try query_as_rel.fetchAs(UserWithJsonComments, db, arena_allocator, .{});
    for (results) |res| {
        std.debug.print("User: {s}\n", .{res.name});
        if (res.comments) |json| {
            std.debug.print("  Raw JSON Comments: {s}\n", .{json});
        }
    }

    // 7. Test fetchWithRel with multiple includes
    std.debug.print("\n--- Testing fetchWithRel() with multiple includes (Posts & Comments) ---\n", .{});
    var query_multi = models.Users.query();
    defer query_multi.deinit();
    _ = query_multi
        .include(.{ .posts = .{ .model_name = .posts } })
        .include(.{ .comments = .{ .model_name = .comments } });

    const multi_results = try query_multi.fetchWithRel(
        models.Rel.Users.UsersWithAllRelations,
        db,
        arena_allocator,
        .{},
    );

    for (multi_results) |u| {
        std.debug.print("User: {s}\n", .{u.name});
        if (u.posts) |posts| {
            std.debug.print("  Posts: {d}\n", .{posts.len});
            for (posts) |p| {
                std.debug.print("    - {s}\n", .{p.title});
            }
        }
        if (u.comments) |comments| {
            std.debug.print("  Comments: {d}\n", .{comments.len});
        }
    }

    // 8. Test fetchAs() with multiple includes (Raw JSON strings)
    std.debug.print("\n--- Testing fetchAs() with multiple includes (Raw JSON) ---\n", .{});
    const UserFullJson = struct {
        name: []const u8,
        posts: ?[]const u8,
        comments: ?[]const u8,
    };

    var query_full_as = models.Users.query();
    defer query_full_as.deinit();
    _ = query_full_as
        .select(&.{.name})
        .include(.{ .posts = .{ .model_name = .posts } })
        .include(.{ .comments = .{ .model_name = .comments } });

    const full_json_results = try query_full_as.fetchAs(UserFullJson, db, arena_allocator, .{});
    for (full_json_results) |res| {
        std.debug.print("User: {s}\n", .{res.name});
        std.debug.print("  Posts JSON: {s}\n", .{res.posts orelse "[]"});
        std.debug.print("  Comments JSON: {s}\n", .{res.comments orelse "[]"});
    }
}
