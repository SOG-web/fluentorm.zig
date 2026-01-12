const std = @import("std");

const QueryBuilder = @import("../src/query.zig").QueryBuilder;

test "query builder" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.select(&.{ .id, .name }).where(.{
        .field = .id,
        .operator = .eq,
        .value = "1",
    }).orWhere(.{
        .field = .name,
        .operator = .eq,
        .value = "1",
    }).where(.{
        .field = .name,
        .operator = .eq,
        .value = "2",
    }).orderBy(.{
        .field = .id,
        .direction = .asc,
    }).limit(1);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    std.debug.print("working \n {s} \n", .{sql});

    try std.testing.expectEqualStrings("SELECT id, name FROM users WHERE id = 1 OR name = 1 AND name = 2 ORDER BY id ASC LIMIT 1", sql);
}

test "query builder with pagination" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.paginate(3, 25);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users LIMIT 25 OFFSET 50", sql);
}

test "query builder with distinct" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.distinct().select(&.{.name});
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT DISTINCT name FROM users", sql);
}

test "query builder with join" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.innerJoin("posts", "users.id = posts.user_id").where(.{
        .field = .id,
        .operator = .eq,
        .value = "$1",
    });
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users INNER JOIN posts ON users.id = posts.user_id WHERE id = $1", sql);
}

test "query builder with group by and having" {
    const allocator = std.testing.allocator;

    const Order = struct {
        id: i64,
        status: []const u8,

        pub fn tableName() []const u8 {
            return "orders";
        }
    };

    const FieldEnum = enum { id, status };
    const OrderQuery = QueryBuilder(Order, Order, FieldEnum);
    var query = OrderQuery.init();
    defer query.deinit();
    _ = query.selectRaw("status, COUNT(*) as count").groupBy(&.{.status}).having("COUNT(*) > 5");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT status, COUNT(*) as count FROM orders GROUP BY status HAVING COUNT(*) > 5", sql);
}

test "query builder with whereBetween" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        age: i32,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, age };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.whereBetween(.age, "$1", "$2", .integer);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE age BETWEEN $1 AND $2", sql);
}

test "query builder with whereIn" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        status: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, status };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.whereIn(.status, &.{ "active", "pending" }, .string);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE status IN ('active', 'pending')", sql);
}

test "query builder with whereNotIn" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        status: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, status };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.whereNotIn(.status, &.{ "deleted", "banned" }, .string);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE status NOT IN ('deleted', 'banned')", sql);
}

test "query builder with whereNotBetween" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        age: i32,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, age };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.whereNotBetween(.age, "13", "17", .integer);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE age NOT BETWEEN 13 AND 17", sql);
}

test "query builder with whereRaw" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        created_at: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, created_at };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.whereRaw("created_at > NOW() - INTERVAL '7 days'");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE created_at > NOW() - INTERVAL '7 days'", sql);
}

test "query builder with orWhereRaw" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        role: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, role };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.where(.{ .field = .role, .operator = .eq, .value = "'user'" })
        .orWhereRaw("role = 'admin' AND id < 100");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE role = 'user' OR role = 'admin' AND id < 100", sql);
}

test "query builder with whereNull" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        verified_at: ?[]const u8, // Using verified_at instead of deleted_at to avoid soft delete auto-filter

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, verified_at };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.whereNull(.verified_at);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE verified_at IS NULL", sql);
}

test "query builder with whereNotNull" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        email_verified_at: ?[]const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, email_verified_at };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.whereNotNull(.email_verified_at);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE email_verified_at IS NOT NULL", sql);
}

test "query builder with whereExists" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    // Find users who have at least one order
    _ = query.whereExists("SELECT 1 FROM orders WHERE orders.user_id = users.id");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE EXISTS (SELECT 1 FROM orders WHERE orders.user_id = users.id)", sql);
}

test "query builder with whereNotExists" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    // Find users who have never been banned
    _ = query.whereNotExists("SELECT 1 FROM bans WHERE bans.user_id = users.id");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE NOT EXISTS (SELECT 1 FROM bans WHERE bans.user_id = users.id)", sql);
}

test "query builder with whereSubquery - IN operator" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    // Find users who are premium members
    // SQL: SELECT * FROM users WHERE id IN (SELECT user_id FROM premium_members)
    _ = query.whereSubquery(.id, .in, "SELECT user_id FROM premium_members");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE id IN (SELECT user_id FROM premium_members)", sql);
}

test "query builder with whereSubquery - NOT IN operator" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    // Find users who are NOT banned
    _ = query.whereSubquery(.id, .not_in, "SELECT user_id FROM banned_users");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM banned_users)", sql);
}

test "query builder with whereSubquery - comparison operator" {
    const allocator = std.testing.allocator;

    const Product = struct {
        id: i64,
        price: f64,

        pub fn tableName() []const u8 {
            return "products";
        }
    };

    const FieldEnum = enum { id, price };
    const ProductQuery = QueryBuilder(Product, Product, FieldEnum);
    var query = ProductQuery.init();
    defer query.deinit();
    // Find products priced above average
    // SQL: SELECT * FROM products WHERE price > (SELECT AVG(price) FROM products)
    _ = query.whereSubquery(.price, .gt, "SELECT AVG(price) FROM products");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM products WHERE price > (SELECT AVG(price) FROM products)", sql);
}

test "query builder with selectAggregate" {
    const allocator = std.testing.allocator;

    const Order = struct {
        id: i64,
        amount: f64,
        user_id: i64,

        pub fn tableName() []const u8 {
            return "orders";
        }
    };

    const FieldEnum = enum { id, amount, user_id };
    const OrderQuery = QueryBuilder(Order, Order, FieldEnum);
    var query = OrderQuery.init();
    defer query.deinit();
    _ = query.select(&.{.user_id})
        .selectAggregate(.sum, .amount, "total_spent")
        .selectAggregate(.count, .id, "order_count")
        .groupBy(&.{.user_id});
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT user_id, SUM(amount) AS total_spent, COUNT(id) AS order_count FROM orders GROUP BY user_id", sql);
}

test "query builder with multiple orderBy" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,
        created_at: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name, created_at };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.orderBy(.{ .field = .created_at, .direction = .desc })
        .orderBy(.{ .field = .name, .direction = .asc });
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users ORDER BY created_at DESC, name ASC", sql);
}

test "query builder with orderByRaw" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.orderByRaw("RANDOM()");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users ORDER BY RANDOM()", sql);
}

test "query builder with groupByRaw" {
    const allocator = std.testing.allocator;

    const Order = struct {
        id: i64,
        created_at: []const u8,
        amount: f64,

        pub fn tableName() []const u8 {
            return "orders";
        }
    };

    const FieldEnum = enum { id, created_at, amount };
    const OrderQuery = QueryBuilder(Order, Order, FieldEnum);
    var query = OrderQuery.init();
    defer query.deinit();
    _ = query.selectRaw("DATE(created_at) as order_date, SUM(amount) as daily_total")
        .groupByRaw("DATE(created_at)");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT DATE(created_at) as order_date, SUM(amount) as daily_total FROM orders GROUP BY DATE(created_at)", sql);
}

test "query builder with havingAggregate" {
    const allocator = std.testing.allocator;

    const Order = struct {
        id: i64,
        user_id: i64,
        amount: f64,

        pub fn tableName() []const u8 {
            return "orders";
        }
    };

    const FieldEnum = enum { id, user_id, amount };
    const OrderQuery = QueryBuilder(Order, Order, FieldEnum);
    var query = OrderQuery.init();
    defer query.deinit();
    // Find users who have spent more than $1000 total
    _ = query.select(&.{.user_id})
        .selectAggregate(.sum, .amount, "total")
        .groupBy(&.{.user_id})
        .havingAggregate(.sum, .amount, .gt, "1000");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id HAVING SUM(amount) > 1000", sql);
}

test "query builder with left join" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    // Get all users and their posts (if any)
    _ = query.leftJoin("posts", "users.id = posts.user_id");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users LEFT JOIN posts ON users.id = posts.user_id", sql);
}

test "query builder with right join" {
    const allocator = std.testing.allocator;

    const Post = struct {
        id: i64,
        user_id: i64,

        pub fn tableName() []const u8 {
            return "posts";
        }
    };

    const FieldEnum = enum { id, user_id };
    const PostQuery = QueryBuilder(Post, Post, FieldEnum);
    var query = PostQuery.init();
    defer query.deinit();
    _ = query.rightJoin("users", "posts.user_id = users.id");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM posts RIGHT JOIN users ON posts.user_id = users.id", sql);
}

test "query builder with full outer join" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.fullJoin("orders", "users.id = orders.user_id");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users FULL OUTER JOIN orders ON users.id = orders.user_id", sql);
}

test "query builder with multiple joins" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    // Join users with posts and comments
    _ = query.innerJoin("posts", "users.id = posts.user_id")
        .leftJoin("comments", "posts.id = comments.post_id");
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users INNER JOIN posts ON users.id = posts.user_id LEFT JOIN comments ON posts.id = comments.post_id", sql);
}

test "query builder with offset only" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.offset(10);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users OFFSET 10", sql);
}

test "query builder with limit and offset" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.limit(20).offset(40);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users LIMIT 20 OFFSET 40", sql);
}

test "query builder paginate with page 0 defaults to page 1" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.paginate(0, 10); // Page 0 should become page 1
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users LIMIT 10 OFFSET 0", sql);
}

test "query builder paginate page 1" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    _ = query.paginate(1, 15);
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users LIMIT 15 OFFSET 0", sql);
}

test "query builder with soft delete - withDeleted" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,
        deleted_at: ?[]const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name, deleted_at };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    // Include soft-deleted records
    _ = query.withDeleted();
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    // No WHERE deleted_at IS NULL clause
    try std.testing.expectEqualStrings("SELECT * FROM users", sql);
}

test "query builder with soft delete - default excludes deleted" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,
        deleted_at: ?[]const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name, deleted_at };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    // Should automatically filter out soft-deleted records
    try std.testing.expectEqualStrings("SELECT * FROM users WHERE deleted_at IS NULL", sql);
}

test "query builder with soft delete - onlyDeleted" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        name: []const u8,
        deleted_at: ?[]const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, name, deleted_at };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();
    // Only get soft-deleted records
    _ = query.onlyDeleted();
    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE deleted_at IS NOT NULL", sql);
}

test "query builder with all operators" {
    const allocator = std.testing.allocator;

    const Product = struct {
        id: i64,
        name: []const u8,
        price: f64,

        pub fn tableName() []const u8 {
            return "products";
        }
    };

    const FieldEnum = enum { id, name, price };
    const ProductQuery = QueryBuilder(Product, Product, FieldEnum);

    // Test eq (=)
    {
        var query = ProductQuery.init();
        defer query.deinit();
        _ = query.where(.{ .field = .id, .operator = .eq, .value = "1" });
        const sql = try query.buildSql(allocator);
        defer allocator.free(sql);
        try std.testing.expectEqualStrings("SELECT * FROM products WHERE id = 1", sql);
    }

    // Test neq (!=)
    {
        var query = ProductQuery.init();
        defer query.deinit();
        _ = query.where(.{ .field = .id, .operator = .neq, .value = "1" });
        const sql = try query.buildSql(allocator);
        defer allocator.free(sql);
        try std.testing.expectEqualStrings("SELECT * FROM products WHERE id != 1", sql);
    }

    // Test gt (>)
    {
        var query = ProductQuery.init();
        defer query.deinit();
        _ = query.where(.{ .field = .price, .operator = .gt, .value = "100" });
        const sql = try query.buildSql(allocator);
        defer allocator.free(sql);
        try std.testing.expectEqualStrings("SELECT * FROM products WHERE price > 100", sql);
    }

    // Test gte (>=)
    {
        var query = ProductQuery.init();
        defer query.deinit();
        _ = query.where(.{ .field = .price, .operator = .gte, .value = "100" });
        const sql = try query.buildSql(allocator);
        defer allocator.free(sql);
        try std.testing.expectEqualStrings("SELECT * FROM products WHERE price >= 100", sql);
    }

    // Test lt (<)
    {
        var query = ProductQuery.init();
        defer query.deinit();
        _ = query.where(.{ .field = .price, .operator = .lt, .value = "50" });
        const sql = try query.buildSql(allocator);
        defer allocator.free(sql);
        try std.testing.expectEqualStrings("SELECT * FROM products WHERE price < 50", sql);
    }

    // Test lte (<=)
    {
        var query = ProductQuery.init();
        defer query.deinit();
        _ = query.where(.{ .field = .price, .operator = .lte, .value = "50" });
        const sql = try query.buildSql(allocator);
        defer allocator.free(sql);
        try std.testing.expectEqualStrings("SELECT * FROM products WHERE price <= 50", sql);
    }

    // Test like
    {
        var query = ProductQuery.init();
        defer query.deinit();
        _ = query.where(.{ .field = .name, .operator = .like, .value = "'%phone%'" });
        const sql = try query.buildSql(allocator);
        defer allocator.free(sql);
        try std.testing.expectEqualStrings("SELECT * FROM products WHERE name LIKE '%phone%'", sql);
    }

    // Test ilike (case-insensitive like)
    {
        var query = ProductQuery.init();
        defer query.deinit();
        _ = query.where(.{ .field = .name, .operator = .ilike, .value = "'%PHONE%'" });
        const sql = try query.buildSql(allocator);
        defer allocator.free(sql);
        try std.testing.expectEqualStrings("SELECT * FROM products WHERE name ILIKE '%PHONE%'", sql);
    }
}

test "query builder complex query with all features" {
    const allocator = std.testing.allocator;

    const Order = struct {
        id: i64,
        user_id: i64,
        status: []const u8,
        amount: f64,
        created_at: []const u8,

        pub fn tableName() []const u8 {
            return "orders";
        }
    };

    const FieldEnum = enum { id, user_id, status, amount, created_at };
    const OrderQuery = QueryBuilder(Order, Order, FieldEnum);
    var query = OrderQuery.init();
    defer query.deinit();

    // Complex query: Get order statistics per user for completed orders
    // with total > 100, sorted by total descending, page 2 with 10 per page
    _ = query
        .distinct()
        .select(&.{.user_id})
        .selectAggregate(.sum, .amount, "total")
        .selectAggregate(.count, .id, "order_count")
        .innerJoin("users", "orders.user_id = users.id")
        .where(.{ .field = .status, .operator = .eq, .value = "'completed'" })
        .whereBetween(.amount, "10", "10000", .integer)
        .groupBy(&.{.user_id})
        .havingAggregate(.sum, .amount, .gt, "100")
        .orderBy(.{ .field = .user_id, .direction = .asc })
        .paginate(2, 10);

    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    const expected = "SELECT DISTINCT user_id, SUM(amount) AS total, COUNT(id) AS order_count " ++
        "FROM orders INNER JOIN users ON orders.user_id = users.id " ++
        "WHERE status = 'completed' AND amount BETWEEN 10 AND 10000 " ++
        "GROUP BY user_id HAVING SUM(amount) > 100 " ++
        "ORDER BY user_id ASC LIMIT 10 OFFSET 10";

    try std.testing.expectEqualStrings(expected, sql);
}

test "query builder with multiple having clauses" {
    const allocator = std.testing.allocator;

    const Order = struct {
        id: i64,
        user_id: i64,
        amount: f64,

        pub fn tableName() []const u8 {
            return "orders";
        }
    };

    const FieldEnum = enum { id, user_id, amount };
    const OrderQuery = QueryBuilder(Order, Order, FieldEnum);
    var query = OrderQuery.init();
    defer query.deinit();

    _ = query.select(&.{.user_id})
        .selectAggregate(.sum, .amount, "total")
        .groupBy(&.{.user_id})
        .having("COUNT(*) > 5")
        .having("SUM(amount) < 10000");

    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id HAVING COUNT(*) > 5 AND SUM(amount) < 10000", sql);
}

test "query builder with multiple group by fields" {
    const allocator = std.testing.allocator;

    const Order = struct {
        id: i64,
        user_id: i64,
        status: []const u8,
        amount: f64,

        pub fn tableName() []const u8 {
            return "orders";
        }
    };

    const FieldEnum = enum { id, user_id, status, amount };
    const OrderQuery = QueryBuilder(Order, Order, FieldEnum);
    var query = OrderQuery.init();
    defer query.deinit();

    _ = query.select(&.{ .user_id, .status })
        .selectAggregate(.sum, .amount, "total")
        .groupBy(&.{ .user_id, .status });

    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT user_id, status, SUM(amount) AS total FROM orders GROUP BY user_id, status", sql);
}

test "query builder chaining or conditions" {
    const allocator = std.testing.allocator;

    const User = struct {
        id: i64,
        role: []const u8,
        status: []const u8,

        pub fn tableName() []const u8 {
            return "users";
        }
    };

    const FieldEnum = enum { id, role, status };
    const UserQuery = QueryBuilder(User, User, FieldEnum);
    var query = UserQuery.init();
    defer query.deinit();

    // WHERE role = 'admin' OR role = 'moderator' OR role = 'superuser'
    _ = query.where(.{ .field = .role, .operator = .eq, .value = "'admin'" })
        .orWhere(.{ .field = .role, .operator = .eq, .value = "'moderator'" })
        .orWhere(.{ .field = .role, .operator = .eq, .value = "'superuser'" });

    const sql = try query.buildSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("SELECT * FROM users WHERE role = 'admin' OR role = 'moderator' OR role = 'superuser'", sql);
}
