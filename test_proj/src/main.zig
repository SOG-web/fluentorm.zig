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

    const user1_id = try models.Users.insert(db, allocator, models.Users.CreateInput{
        .name = "rou",
        .email = "rou@example.com",
        .password_hash = "hashed_password",
        .bid = "PRO_USER",
        .is_active = true,
    });
    defer allocator.free(user1_id);

    const user2_id = try models.Users.insert(db, allocator, models.Users.CreateInput{
        .name = "alice",
        .email = "alice@example.com",
        .password_hash = "hashed_password",
        .bid = null,
        .is_active = true,
    });
    defer allocator.free(user2_id);

    const user3_id = try models.Users.insert(db, allocator, models.Users.CreateInput{
        .name = "bob",
        .email = "bob@example.com",
        .password_hash = "hashed_password",
        .bid = "LITE_USER",
        .is_active = false,
    });
    defer allocator.free(user3_id);

    const user1_hex = try pg.uuidToHex(&user1_id[0..16].*);

    std.debug.print("User ID: {s}\n", .{user1_hex});

    const post1_id = try models.Posts.insert(db, allocator, models.Posts.CreateInput{
        .title = "Hello Zig",
        .content = "Zig is awesome!",
        .user_id = &user1_hex,
        .is_published = true,
    });
    defer allocator.free(post1_id);

    const user2_hex = try pg.uuidToHex(&user2_id[0..16].*);
    const post2_id = try models.Posts.insert(db, allocator, models.Posts.CreateInput{
        .title = "Post by Alice",
        .content = "I'm Alice",
        .user_id = &user2_hex,
        .is_published = true,
    });
    defer allocator.free(post2_id);

    const post1_hex = try pg.uuidToHex(&post1_id[0..16].*);

    const comment1_id = try models.Comments.insert(db, allocator, models.Comments.CreateInput{
        .post_id = &post1_hex,
        .user_id = &user1_hex,
        .content = "This is a comment by rou",
        .is_approved = true,
    });
    defer allocator.free(comment1_id);

    const comment2_id = try models.Comments.insert(db, allocator, models.Comments.CreateInput{
        .post_id = &post1_hex,
        .user_id = &user1_hex,
        .content = "Another one",
        .is_approved = false,
    });
    defer allocator.free(comment2_id);

    const comment3_id = try models.Comments.insert(db, allocator, models.Comments.CreateInput{
        .post_id = &post1_hex,
        .user_id = &user1_hex,
        .content = "Another one approved",
        .is_approved = true,
    });
    defer allocator.free(comment3_id);

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

    // 9. Test Filtering: whereIn, whereBetween, whereNull
    std.debug.print("\n--- Testing Filters: whereIn, whereBetween, whereNull ---\n", .{});

    // whereIn
    var query_in = models.Users.query();
    defer query_in.deinit();
    _ = query_in.whereIn(.name, &.{ "rou", "alice" });
    const users_in = try query_in.fetch(db, arena_allocator, .{});
    std.debug.print("whereInResult: {d} users found (Expected 2)\n", .{users_in.len});

    // whereNull
    var query_null = models.Users.query();
    defer query_null.deinit();
    _ = query_null.whereNull(.bid);
    const users_null = try query_null.fetch(db, arena_allocator, .{});
    std.debug.print("whereNullResult: {d} users found (Expected 1 - Alice)\n", .{users_null.len});

    // whereNotNull
    var query_not_null = models.Users.query();
    defer query_not_null.deinit();
    _ = query_not_null.whereNotNull(.bid);
    const users_not_null = try query_not_null.fetch(db, arena_allocator, .{});
    std.debug.print("whereNotNullResult: {d} users found (Expected 2 - rou, bob)\n", .{users_not_null.len});

    // 9. Test Aggregates: count, exists, sum, min, max
    std.debug.print("\n--- Testing Aggregates: count, exists, sum, min, max ---\n", .{});

    var count_query = models.Users.query();
    defer count_query.deinit();
    const total_users = try count_query.count(db, .{});
    std.debug.print("count(): {d} (Expected 3)\n", .{total_users});

    var exists_query = models.Users.query();
    defer exists_query.deinit();
    _ = exists_query.where(.{ .field = .name, .operator = .eq, .value = .{ .string = "rou" } });
    const has_rou = try exists_query.exists(db, .{});
    std.debug.print("exists(rou): {any} (Expected true)\n", .{has_rou});

    var active_count_query = models.Users.query();
    defer active_count_query.deinit();
    _ = active_count_query.where(.{ .field = .is_active, .operator = .eq, .value = .{ .boolean = true } });
    const is_active_count = try active_count_query.count(db, .{});
    std.debug.print("count(active): {d} (Expected 2)\n", .{is_active_count});

    // Test sum on a dummy field or raw
    // Since we don't have a numeric field in Users besides timestamp, let's check Comments counts per post
    var comment_count_query = models.Comments.query();
    defer comment_count_query.deinit();
    const comment_count_sum = try comment_count_query.count(db, .{});
    std.debug.print("Total comments: {d} (Expected 3)\n", .{comment_count_sum});

    // 10. Test Advanced Selection: first, pluck
    std.debug.print("\n--- Testing Selection: first, pluck ---\n", .{});

    var first_query = models.Users.query();
    defer first_query.deinit();
    _ = first_query.orderBy(.{ .field = .name, .direction = .asc });
    const first_user = try first_query.first(db, arena_allocator, .{});
    if (first_user) |u| {
        std.debug.print("first() user: {s} (Expected alice)\n", .{u.name});
    }

    // pluck
    var pluck_query = models.Users.query();
    defer pluck_query.deinit();
    _ = pluck_query.orderBy(.{ .field = .name, .direction = .asc });
    const names = try pluck_query.pluck(db, arena_allocator, .name, .{});
    std.debug.print("pluck(name): ", .{});
    for (names) |name| {
        std.debug.print("{s}, ", .{name});
    }
    std.debug.print("\n", .{});

    // 11. Test Grouping & Distinct
    std.debug.print("\n--- Testing Grouping & Distinct ---\n", .{});

    // distinct
    var distinct_query = models.Users.query();
    defer distinct_query.deinit();
    _ = distinct_query.distinct().select(&.{.email});
    const distinct_emails = try distinct_query.fetchAs(struct { email: []const u8 }, db, arena_allocator, .{});
    std.debug.print("distinct emails: {d} (Expected 3)\n", .{distinct_emails.len});

    // 12. Test final action: delete
    std.debug.print("\n--- Testing Action: delete ---\n", .{});
    var delete_query = models.Users.query();
    defer delete_query.deinit();
    _ = delete_query.where(.{ .field = .name, .operator = .eq, .value = .{ .string = "bob" } });
    try delete_query.delete(db, .{});

    var count_after_delete = models.Users.query();
    defer count_after_delete.deinit();
    const after_delete_count = try count_after_delete.count(db, .{});
    std.debug.print("Count after deleting bob: {d} (Expected 2)\n", .{after_delete_count});

    std.debug.print("\n🎉 All query tests completed!\n", .{});
}
