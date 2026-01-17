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
    try models.Comments.truncate(db).unwrap();
    std.debug.print("Truncated comments\n", .{});
    try models.Posts.truncate(db).unwrap();
    std.debug.print("Truncated posts\n", .{});
    try models.Users.truncate(db).unwrap();
    std.debug.print("Truncated users\n", .{});

    std.debug.print("Seeding new data...\n", .{});

    const user1_result = models.Users.insert(db, allocator, models.Users.CreateInput{
        .name = "rou",
        .email = "rou@example.com",
        .password_hash = "hashed_password",
        .bid = "PRO_USER",
        .is_active = true,
    });

    const user1_id = switch (user1_result) {
        .ok => |id| id,
        .err => |err| {
            std.debug.print("Error: {any}", .{err});
            return err;
        },
    };

    defer allocator.free(user1_id);

    const user2_result = models.Users.insert(db, allocator, models.Users.CreateInput{
        .name = "alice",
        .email = "alice@example.com",
        .password_hash = "hashed_password",
        .bid = null,
        .is_active = true,
    });

    const user2_id = switch (user2_result) {
        .ok => |id| id,
        .err => |err| {
            std.debug.print("Error: {any}", .{err});
            return err;
        },
    };

    defer allocator.free(user2_id);

    const user3_result = models.Users.insert(db, allocator, models.Users.CreateInput{
        .name = "bob",
        .email = "bob@example.com",
        .password_hash = "hashed_password",
        .bid = "LITE_USER",
        .is_active = false,
    });

    const user3_id = switch (user3_result) {
        .ok => |id| id,
        .err => |err| {
            std.debug.print("Error: {any}", .{err});
            return err;
        },
    };

    defer allocator.free(user3_id);

    const user1_hex = try pg.uuidToHex(&user1_id[0..16].*);

    std.debug.print("User ID: {s}\n", .{user1_hex});

    const post1_result = models.Posts.insert(db, allocator, models.Posts.CreateInput{
        .title = "Hello Zig",
        .content = "Zig is awesome!",
        .user_id = &user1_hex,
        .is_published = true,
    });

    const post1_id = switch (post1_result) {
        .ok => |id| id,
        .err => |err| {
            std.debug.print("Error: {any}", .{err});
            return err;
        },
    };

    defer allocator.free(post1_id);

    const user2_hex = try pg.uuidToHex(&user2_id[0..16].*);
    const post2_result = models.Posts.insert(db, allocator, models.Posts.CreateInput{
        .title = "Post by Alice",
        .content = "I'm Alice",
        .user_id = &user2_hex,
        .is_published = true,
    });

    const post2_id = switch (post2_result) {
        .ok => |id| id,
        .err => |err| {
            std.debug.print("Error: {any}", .{err});
            return err;
        },
    };

    defer allocator.free(post2_id);

    const post1_hex = try pg.uuidToHex(&post1_id[0..16].*);

    const comment1_result = models.Comments.insert(db, allocator, models.Comments.CreateInput{
        .post_id = &post1_hex,
        .user_id = &user1_hex,
        .content = "This is a comment by rou",
        .is_approved = true,
    });

    const comment1_id = switch (comment1_result) {
        .ok => |id| id,
        .err => |err| {
            std.debug.print("Error: {any}", .{err});
            return err;
        },
    };

    defer allocator.free(comment1_id);

    const comment2_result = models.Comments.insert(db, allocator, models.Comments.CreateInput{
        .post_id = &post1_hex,
        .user_id = &user1_hex,
        .content = "Another one",
        .is_approved = false,
    });

    const comment2_id = switch (comment2_result) {
        .ok => |id| id,
        .err => |err| {
            std.debug.print("Error: {any}", .{err});
            return err;
        },
    };

    defer allocator.free(comment2_id);

    const comment3_result = models.Comments.insert(db, allocator, models.Comments.CreateInput{
        .post_id = &post1_hex,
        .user_id = &user1_hex,
        .content = "Another one approved",
        .is_approved = true,
    });

    const comment3_id = switch (comment3_result) {
        .ok => |id| id,
        .err => |err| {
            std.debug.print("Error: {any}", .{err});
            return err;
        },
    };

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

    // ============================================================================
    // TRANSACTION TESTS
    // ============================================================================
    std.debug.print("\n\n========================================\n", .{});
    std.debug.print("TRANSACTION TESTS\n", .{});
    std.debug.print("========================================\n\n", .{});

    const Transaction = @import("models/generated/transaction.zig").Transaction;

    // 13. Test Transaction Commit
    std.debug.print("--- Test 13: Transaction Commit ---\n", .{});
    {
        std.debug.print("Attempting to begin transaction...\n", .{});
        var tx = Transaction.begin(pool) catch |err| {
            std.debug.print("ERROR: Failed to begin transaction: {any}\n", .{err});
            return err;
        };
        defer tx.deinit();

        const tx_user_id = try models.Users.insert(tx.executor(), allocator, models.Users.CreateInput{
            .name = "tx_commit_user",
            .email = "tx_commit@example.com",
            .password_hash = "hashed_password",
            .bid = null,
            .is_active = true,
        }).unwrap();
        defer allocator.free(tx_user_id);

        // Commit the transaction
        try tx.commit();

        // Verify the user was created
        var verify_query = models.Users.query();
        defer verify_query.deinit();
        _ = verify_query.where(.{ .field = .name, .operator = .eq, .value = .{ .string = "tx_commit_user" } });
        const tx_users = try verify_query.fetch(db, arena_allocator, .{});
        std.debug.print("Users after commit: {d} (Expected 1)\n", .{tx_users.len});
    }

    // 14. Test Transaction Rollback
    std.debug.print("\n--- Test 14: Transaction Rollback ---\n", .{});
    {
        var tx = try Transaction.begin(pool);
        defer tx.deinit();

        const tx_user_id = try models.Users.insert(tx.executor(), allocator, models.Users.CreateInput{
            .name = "tx_rollback_user",
            .email = "tx_rollback@example.com",
            .password_hash = "hashed_password",
            .bid = null,
            .is_active = true,
        }).unwrap();
        defer allocator.free(tx_user_id);

        // Rollback the transaction
        try tx.rollback();

        // Verify the user was NOT created
        var verify_query = models.Users.query();
        defer verify_query.deinit();
        _ = verify_query.where(.{ .field = .name, .operator = .eq, .value = .{ .string = "tx_rollback_user" } });
        const tx_users = try verify_query.fetch(db, arena_allocator, .{});
        std.debug.print("Users after rollback: {d} (Expected 0)\n", .{tx_users.len});
    }

    // 15. Test Transaction with Multiple Operations
    std.debug.print("\n--- Test 15: Transaction with Multiple Operations ---\n", .{});
    {
        var tx = try Transaction.begin(pool);
        defer tx.deinit();

        // Create user
        const tx_user_id = try models.Users.insert(tx.executor(), allocator, models.Users.CreateInput{
            .name = "tx_multi_user",
            .email = "tx_multi@example.com",
            .password_hash = "hashed_password",
            .bid = "MULTI_USER",
            .is_active = true,
        }).unwrap();
        defer allocator.free(tx_user_id);

        const tx_user_hex = try pg.uuidToHex(&tx_user_id[0..16].*);

        // Create post for the user
        const tx_post_id = try models.Posts.insert(tx.executor(), allocator, models.Posts.CreateInput{
            .title = "Transaction Post",
            .content = "This post is part of a transaction",
            .user_id = &tx_user_hex,
            .is_published = true,
        }).unwrap();
        defer allocator.free(tx_post_id);

        const tx_post_hex = try pg.uuidToHex(&tx_post_id[0..16].*);

        // Create comment on the post
        const tx_comment_id = try models.Comments.insert(tx.executor(), allocator, models.Comments.CreateInput{
            .post_id = &tx_post_hex,
            .user_id = &tx_user_hex,
            .content = "This comment is part of a transaction",
            .is_approved = true,
        }).unwrap();
        defer allocator.free(tx_comment_id);

        // Commit all operations
        try tx.commit();

        // Verify all records were created
        var verify_user_query = models.Users.query();
        defer verify_user_query.deinit();
        _ = verify_user_query.where(.{ .field = .name, .operator = .eq, .value = .{ .string = "tx_multi_user" } });
        const tx_users = try verify_user_query.fetch(db, arena_allocator, .{});
        std.debug.print("Users created: {d} (Expected 1)\n", .{tx_users.len});

        var verify_post_query = models.Posts.query();
        defer verify_post_query.deinit();
        _ = verify_post_query.where(.{ .field = .title, .operator = .eq, .value = .{ .string = "Transaction Post" } });
        const tx_posts = try verify_post_query.fetch(db, arena_allocator, .{});
        std.debug.print("Posts created: {d} (Expected 1)\n", .{tx_posts.len});

        var verify_comment_query = models.Comments.query();
        defer verify_comment_query.deinit();
        _ = verify_comment_query.where(.{ .field = .content, .operator = .eq, .value = .{ .string = "This comment is part of a transaction" } });
        const tx_comments = try verify_comment_query.fetch(db, arena_allocator, .{});
        std.debug.print("Comments created: {d} (Expected 1)\n", .{tx_comments.len});
    }

    // 16. Test Transaction Rollback with Multiple Operations
    std.debug.print("\n--- Test 16: Transaction Rollback with Multiple Operations ---\n", .{});
    {
        var tx = try Transaction.begin(pool);
        defer tx.deinit();

        // Create user
        const tx_user_id = try models.Users.insert(tx.executor(), allocator, models.Users.CreateInput{
            .name = "tx_rollback_multi_user",
            .email = "tx_rollback_multi@example.com",
            .password_hash = "hashed_password",
            .bid = null,
            .is_active = true,
        }).unwrap();
        defer allocator.free(tx_user_id);

        const tx_user_hex = try pg.uuidToHex(&tx_user_id[0..16].*);

        // Create post for the user
        const tx_post_id = try models.Posts.insert(tx.executor(), allocator, models.Posts.CreateInput{
            .title = "Rollback Transaction Post",
            .content = "This post will be rolled back",
            .user_id = &tx_user_hex,
            .is_published = true,
        }).unwrap();
        defer allocator.free(tx_post_id);

        // Rollback all operations
        try tx.rollback();

        // Verify NO records were created
        var verify_user_query = models.Users.query();
        defer verify_user_query.deinit();
        _ = verify_user_query.where(.{ .field = .name, .operator = .eq, .value = .{ .string = "tx_rollback_multi_user" } });
        const tx_users = try verify_user_query.fetch(db, arena_allocator, .{});
        std.debug.print("Users after rollback: {d} (Expected 0)\n", .{tx_users.len});

        var verify_post_query = models.Posts.query();
        defer verify_post_query.deinit();
        _ = verify_post_query.where(.{ .field = .title, .operator = .eq, .value = .{ .string = "Rollback Transaction Post" } });
        const tx_posts = try verify_post_query.fetch(db, arena_allocator, .{});
        std.debug.print("Posts after rollback: {d} (Expected 0)\n", .{tx_posts.len});
    }

    // 17. Test Transaction Query Operations
    std.debug.print("\n--- Test 17: Transaction Query Operations ---\n", .{});
    {
        var tx = try Transaction.begin(pool);
        defer tx.deinit();

        // Create test users in transaction
        const tx_user1_id = try models.Users.insert(tx.executor(), allocator, models.Users.CreateInput{
            .name = "tx_query_user1",
            .email = "tx_query1@example.com",
            .password_hash = "hashed_password",
            .bid = "QUERY_USER",
            .is_active = true,
        }).unwrap();
        defer allocator.free(tx_user1_id);

        const tx_user2_id = try models.Users.insert(tx.executor(), allocator, models.Users.CreateInput{
            .name = "tx_query_user2",
            .email = "tx_query2@example.com",
            .password_hash = "hashed_password",
            .bid = "QUERY_USER",
            .is_active = true,
        }).unwrap();
        defer allocator.free(tx_user2_id);

        // Query within transaction
        var tx_query = models.Users.query();
        defer tx_query.deinit();
        _ = tx_query.where(.{ .field = .bid, .operator = .eq, .value = .{ .string = "QUERY_USER" } });
        const tx_users = try tx_query.fetch(tx.executor(), arena_allocator, .{});
        std.debug.print("Users in transaction query: {d} (Expected 2)\n", .{tx_users.len});

        // Commit
        try tx.commit();

        // Verify outside transaction
        var verify_query = models.Users.query();
        defer verify_query.deinit();
        _ = verify_query.where(.{ .field = .bid, .operator = .eq, .value = .{ .string = "QUERY_USER" } });
        const verify_users = try verify_query.fetch(db, arena_allocator, .{});
        std.debug.print("Users after commit: {d} (Expected 2)\n", .{verify_users.len});
    }

    // 18. Test Transaction Error Handling
    std.debug.print("\n--- Test 18: Transaction Error Handling ---\n", .{});
    {
        var tx = try Transaction.begin(pool);
        defer tx.deinit();

        // Create a valid user
        const tx_user_id = try models.Users.insert(tx.executor(), allocator, models.Users.CreateInput{
            .name = "tx_error_user",
            .email = "tx_error@example.com",
            .password_hash = "hashed_password",
            .bid = null,
            .is_active = true,
        }).unwrap();
        defer allocator.free(tx_user_id);

        // Try to create a duplicate email (should fail)
        const duplicate_result = models.Users.insert(tx.executor(), allocator, models.Users.CreateInput{
            .name = "tx_duplicate_user",
            .email = "tx_error@example.com", // Same email
            .password_hash = "hashed_password",
            .bid = null,
            .is_active = true,
        });

        const duplicate_id = switch (duplicate_result) {
            .ok => |id| id,
            .err => |err| {
                std.debug.print("Expected error on duplicate: {any}\n", .{err});
                err.log();
                return;
            },
        };

        if (duplicate_id) |dup_id| {
            allocator.free(dup_id);
            std.debug.print("ERROR: Duplicate insert should have failed!\n", .{});
        }

        // Rollback after error
        try tx.rollback();

        // Verify nothing was committed
        var verify_query = models.Users.query();
        defer verify_query.deinit();
        _ = verify_query.where(.{ .field = .email, .operator = .eq, .value = .{ .string = "tx_error@example.com" } });
        const tx_users = try verify_query.fetch(db, arena_allocator, .{});
        std.debug.print("Users after error rollback: {d} (Expected 0)\n", .{tx_users.len});
    }

    // 19. Test Auto-Rollback on deinit
    std.debug.print("\n--- Test 19: Auto-Rollback on deinit ---\n", .{});
    {
        {
            var tx = try Transaction.begin(pool);
            defer tx.deinit(); // Auto-rollback because we don't commit

            const tx_user_id = try models.Users.insert(tx.executor(), allocator, models.Users.CreateInput{
                .name = "tx_auto_rollback_user",
                .email = "tx_auto_rollback@example.com",
                .password_hash = "hashed_password",
                .bid = null,
                .is_active = true,
            });
            defer allocator.free(tx_user_id);

            // No commit - should auto-rollback when tx goes out of scope
        }

        // Verify the user was NOT created
        var verify_query = models.Users.query();
        defer verify_query.deinit();
        _ = verify_query.where(.{ .field = .name, .operator = .eq, .value = .{ .string = "tx_auto_rollback_user" } });
        const tx_users = try verify_query.fetch(db, arena_allocator, .{});
        std.debug.print("Users after auto-rollback: {d} (Expected 0)\n", .{tx_users.len});
    }

    std.debug.print("\n🎉 All transaction tests completed!\n", .{});
}
