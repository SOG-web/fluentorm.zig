# Query Builder Documentation

The `QueryBuilder` provides a fluent API for constructing complex SQL queries in a type-safe manner with automatic memory management.

## Quick Start

```zig
const users = try Users.query()
    .where(.{
        .field = .age,
        .operator = .gt,
        .value = .{ .string = "$1" },
    })
    .orderBy(.{
        .field = .created_at,
        .direction = .desc,
    })
    .limit(10)
    .fetch(&pool, allocator, .{18});
defer allocator.free(users);
```

## ⚠️ Memory Management

**CRITICAL**: Always call `defer query.deinit()` after creating a query object to prevent memory leaks:

```zig
// ✅ Correct: proper cleanup
var query = Users.query();
defer query.deinit();
const users = try query.fetch(&pool, allocator, .{});

// ❌ Memory leak: query not cleaned up
const users = try Users.query().fetch(&pool, allocator, .{});
```

### Query Initialization Options

The ORM provides three ways to initialize queries:

#### 1. `query()` - Standard (Most Common)

Creates a query with its own internal arena allocator:

```zig
var query = Users.query();
defer query.deinit();  // MUST call deinit to free the arena
```

#### 2. `initWithAllocator(backing_allocator)` - Custom Backing Allocator

Creates a query with a custom backing allocator for its arena:

```zig
var query = Users.queryBuilder.initWithAllocator(gpa.allocator());
defer query.deinit();
```

#### 3. `initWithArena(arena: *ArenaAllocator)` - External Arena

Uses an externally-managed arena (e.g., from an HTTP request handler):

```zig
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();  // You manage the arena lifecycle

var query = Users.queryBuilder.initWithArena(&arena);
// NO deinit needed - query doesn't own the arena
```

> [!TIP]
> Use `initWithArena` in HTTP handlers where you have a request-scoped arena. The query automatically detects it doesn't own the arena and won't call `deinit()` on it.

## Performance: Reusing Query Builders

For better performance when executing multiple queries, reuse query builder instances with `reset()` instead of creating new ones:

```zig
// ✅ Efficient: reuse query builder
var query = Users.query();
defer query.deinit();

// First query
const active_users = try query
    .where(.{ .field = .is_active, .operator = .eq, .value = .{ .boolean = true } })
    .fetch(&pool, allocator, .{});

// Reset and reuse for second query (avoids re-allocating internal buffers)
query.reset();

const admins = try query
    .where(.{ .field = .role, .operator = .eq, .value = .{ .string = "'admin'" } })
    .fetch(&pool, allocator, .{});
```

```zig
// ❌ Less efficient: creates new query builder each iteration
for (user_ids) |id| {
    var query = Users.query();  // allocates new buffers each iteration
    defer query.deinit();
    const user = try query.where(...).first(&pool, allocator, .{id});
}

// ✅ Better: reuse with reset
var query = Users.query();
defer query.deinit();
for (user_ids) |id| {
    const user = try query.where(...).first(&pool, allocator, .{id});
    query.reset();  // reuse internal buffers
}
```

> [!TIP]
> The `reset()` method clears all query state (WHERE, ORDER BY, LIMIT, etc.) but keeps the internal arena allocator, avoiding repeated memory allocations.

## SELECT Methods

### `select(fields: []const Field)`

Specifies which columns to retrieve. Defaults to `SELECT *` if not called.

```zig
.select(&.{ .id, .name })
```

### `distinct()`

Enable DISTINCT on the query.

```zig
var query = Users.query();
defer query.deinit();
_ = query.distinct().select(&.{ .email });
const unique_emails = try query.fetch(&pool, allocator, .{});
```

> [!IMPORTANT] > `distinct()` requires a mutable reference, so it cannot be chained on temporary values. Store the query in a variable first.

### `selectAggregate(agg: AggregateType, field: Field, alias: []const u8)`

Select with an aggregate function.

```zig
.selectAggregate(.sum, .amount, "total_amount")
```

### `selectRaw(raw_sql: []const u8)`

Select raw SQL expression.

```zig
.selectRaw("COUNT(*) AS total")
.selectRaw("(SELECT count(*) FROM orders WHERE orders.user_id = users.id) AS order_count")
```

## WHERE Methods

### `where(clause: WhereClause)`

Adds a `WHERE` clause. Multiple calls are combined with `AND`.

```zig
.where(.{
    .field = .status,
    .operator = .eq,
    .value = .{ .string = "$1" },
})
```

### `orWhere(clause: WhereClause)`

Adds an `OR` condition to the `WHERE` clause.

```zig
.orWhere(.{
    .field = .status,
    .operator = .eq,
    .value = .{ .string = "$2" },
})
```

### `whereNull(field: Field)`

Adds a WHERE NULL clause.

```zig
var query = Users.query();
defer query.deinit();
_ = query.whereNull(.deleted_at);
const active_users = try query.fetch(&pool, allocator, .{});
```

### `whereNotNull(field: Field)`

Adds a WHERE NOT NULL clause.

```zig
var query = Users.query();
defer query.deinit();
_ = query.whereNotNull(.email_verified_at);
const verified_users = try query.fetch(&pool, allocator, .{});
```

### `whereIn(field: Field, values: []const []const u8)`

Adds a WHERE IN clause.

> [!IMPORTANT]
> Do NOT include quotes around values - the ORM adds them automatically:

```zig
// ✅ Correct: no quotes
var query = Users.query();
defer query.deinit();
_ = query.whereIn(.status, &.{ "active", "pending" });

// ❌ Wrong: double-quoted
_ = query.whereIn(.status, &.{ "'active'", "'pending'" });  // Results in SQL: 'active'
```

### `whereNotIn(field: Field, values: []const []const u8)`

Adds a WHERE NOT IN clause.

```zig
.whereNotIn(.status, &.{ "deleted", "banned" })
```

### `whereBetween(field: Field, low: WhereValue, high: WhereValue, valueType: InType)`

Adds a BETWEEN clause.

```zig
.whereBetween(.age, .{ .string = "$1" }, .{ .string = "$2" }, .string)
```

### `whereNotBetween(field: Field, low: WhereValue, high: WhereValue, valueType: InType)`

Adds a NOT BETWEEN clause.

```zig
.whereNotBetween(.age, .{ .integer = 13 }, .{ .integer = 17 }, .integer)
```

### `whereRaw(raw_sql: []const u8)`

Adds a raw WHERE clause.

```zig
.whereRaw("created_at > NOW() - INTERVAL '7 days'")
```

### `orWhereRaw(raw_sql: []const u8)`

Adds an OR raw WHERE clause.

```zig
.orWhereRaw("status = 'vip' OR role = 'admin'")
```

### `whereExists(subquery: []const u8)`

Adds a WHERE EXISTS subquery.

```zig
.whereExists("SELECT 1 FROM orders WHERE orders.user_id = users.id")
```

### `whereNotExists(subquery: []const u8)`

Adds a WHERE NOT EXISTS subquery.

```zig
.whereNotExists("SELECT 1 FROM bans WHERE bans.user_id = users.id")
```

### `whereSubquery(field: Field, operator: Operator, subquery: []const u8)`

Adds a subquery in WHERE clause.

```zig
.whereSubquery(.id, .in, "SELECT user_id FROM premium_users")
```

## JOIN Methods

### `join(comptime join_clause: JoinClause)`

Adds a JOIN clause.

```zig
.join(.{
    .join_type = .inner,
    .join_table = .posts,
    .join_field = .{ .posts = .user_id },
    .join_operator = .eq,
    .base_field = .{ .users = .id },
    .select = &.{ "title", "created_at" }
})
```

## Include Methods (Eager Loading)

### `include(rel: IncludeClauseInput)`

Eagerly loads related models using efficient JSONB aggregation queries. This prevents Cartesian products for `hasMany` relationships and allows filtering and selecting specific fields.

```zig
// Basic include - loads all fields
.include(.{
    .posts = .{ .model_name = .posts }
})

// With filtering
.include(.{
    .comments = .{
        .model_name = .comments,
        .where = &.{.{
            .where_type = .@"and",
            .field = .is_approved,
            .operator = .eq,
            .value = .{ .boolean = true }
        }}
    }
})

// With custom field selection
.include(.{
    .posts = .{
        .model_name = .posts,
        .select = &.{ "id", "title", "created_at" }
    }
})
```

#### Multiple Includes

You can include multiple relationships in a single query:

```zig
var query = Users.query();
defer query.deinit();
_ = query
    .include(.{ .posts = .{ .model_name = .posts } })
    .include(.{ .comments = .{ .model_name = .comments } });

// Use fetchWithRel for typed parsing
const users = try query.fetchWithRel(
    Users.Rel.UsersWithAllRelations,
    &pool,
    allocator,
    .{}
);

// OR use fetchAs for custom projections
const UserWithJson = struct {
    name: []const u8,
    posts: ?[]const u8,    // Raw JSONB string
    comments: ?[]const u8,
};
const results = try query.fetchAs(UserWithJson, &pool, allocator, .{});
```

> [!NOTE]
>
> - For `hasMany` relationships, the ORM uses correlated subqueries with `jsonb_agg` to prevent Cartesian products
> - Timestamps in included data are automatically cast to microsecond epochs for JSON compatibility
> - Use `fetchWithRel` for type-safe parsing or `fetchAs` for custom handling

## GROUP BY / HAVING Methods

### `groupBy(fields: []const Field)`

Adds GROUP BY clause.

```zig
.groupBy(&.{ .status, .role })
```

### `groupByRaw(raw_sql: []const u8)`

Adds GROUP BY with raw SQL.

```zig
.groupByRaw("DATE(created_at)")
```

### `having(condition: []const u8)`

Adds HAVING clause.

```zig
.having("COUNT(*) > $1")
```

### `havingAggregate(agg: AggregateType, field: Field, operator: Operator, value: []const u8)`

Adds HAVING with aggregate function.

```zig
.havingAggregate(.count, .id, .gt, "$1")
```

## ORDER BY Methods

### `orderBy(clause: OrderByClause)`

Sets the `ORDER BY` clause.

```zig
var query = Users.query();
defer query.deinit();
_ = query.orderBy(.{
    .field = .created_at,
    .direction = .desc, // .asc or .desc
});
```

> [!IMPORTANT]
> Like `distinct()`, `orderBy()` requires a mutable reference and cannot be chained on temporaries.

### `orderByRaw(raw_sql: []const u8)`

Adds raw ORDER BY clause.

```zig
.orderByRaw("RANDOM()")
```

## LIMIT / OFFSET Methods

### `limit(n: u64)`

Sets the `LIMIT` clause.

```zig
.limit(20)
```

### `offset(n: u64)`

Sets the `OFFSET` clause.

```zig
.offset(10)
```

### `paginate(page: u64, per_page: u64)`

Paginate results (convenience method for limit + offset).

```zig
.paginate(2, 20) // Page 2 with 20 items per page
```

## Soft Delete Methods

### `withDeleted()`

Includes soft-deleted records (where `deleted_at` is not null) in the results.

```zig
.withDeleted()
```

### `onlyDeleted()`

Only get soft-deleted records.

```zig
.onlyDeleted()
```

## Execution Methods

All execution methods return `Result` types for detailed error handling. See [ERROR_HANDLING.md](ERROR_HANDLING.md) for details.

### `fetch(db: Executor, allocator: Allocator, args: anytype) Result([]Model)`

Executes the query and returns a slice of models.

```zig
var query = Users.query();
defer query.deinit();

const result = query
    .where(.{ .field = .is_active, .operator = .eq, .value = .{ .boolean = true } })
    .fetch(db, allocator, .{});

switch (result) {
    .ok => |users| {
        defer allocator.free(users);
        for (users) |user| {
            std.debug.print("User: {s}\n", .{user.name});
        }
    },
    .err => |e| e.log(),
}

// Or use unwrap() for simple propagation:
const users = try query.fetch(db, allocator, .{}).unwrap();
defer allocator.free(users);
```

> [!IMPORTANT] > `fetch` returns `.err` with `CustomProjectionNotSupported` if your query contains:
>
> - **JOINs** (`innerJoin`, `leftJoin`, `rightJoin`, `fullJoin`)
> - **GROUP BY** clauses (`groupBy`, `groupByRaw`)
> - **HAVING** clauses (`having`, `havingAggregate`)
> - **Aggregate functions** (`selectAggregate`)
> - **Raw selects with aliases** (e.g., `selectRaw("COUNT(*) AS total")`)
> - **Select columns** (e.g., `select(&.{.id, .name})`)
>
> For these cases, use `fetchAs` with a custom struct or `fetchRaw` for direct result access.

### `fetchAs(comptime R: type, db: Executor, allocator: Allocator, args: anytype) Result([]R)`

Executes the query and returns a slice of a custom result type.

```zig
const UserSummary = struct {
    name: []const u8,
    post_count: i64,
};

var query = Users.query();
defer query.deinit();
_ = query
    .select(&.{.name})
    .selectRaw("(SELECT count(*) FROM posts WHERE posts.user_id = users.id) AS post_count");

const result = query.fetchAs(UserSummary, db, allocator, .{});
switch (result) {
    .ok => |summaries| {
        defer allocator.free(summaries);
        // use summaries
    },
    .err => |e| e.log(),
}
```

### `fetchWithRel(comptime R: type, db: Executor, allocator: Allocator, args: anytype) Result([]R)`

Fetches results with included relationships, parsing JSONB columns into typed structures.

```zig
var query = Users.query();
defer query.deinit();
_ = query.include(.{
    .posts = .{ .model_name = .posts },
});

const result = query.fetchWithRel(Users.Rel.UsersWithPosts, db, allocator, .{});
switch (result) {
    .ok => |users| {
        defer allocator.free(users);
        for (users) |user| {
            std.debug.print("User: {s}\n", .{user.name});
        }
    },
    .err => |e| e.log(),
}
```

> [!TIP]
> Each model has a `Rel` namespace with explicit relation types:
>
> - `Users.Rel.UsersWithPosts` - User with posts loaded
> - `Users.Rel.UsersWithComments` - User with comments loaded
> - `Users.Rel.UsersWithAllRelations` - User with all relations loaded

### `fetchRaw(db: *pg.Pool, args: anytype) !pg.Result`

Executes the query and returns the raw `pg.Result`. Use this for complex queries when you need full control over result processing.

> [!NOTE]
> The caller is responsible for calling `result.deinit()` when done.

```zig
var result = try Users.query()
    .selectRaw("users.*, posts.title")
    .join(.{ ... })
    .fetchRaw(&pool, .{});
defer result.deinit();

while (try result.next()) |row| {
    const user_id = row.get(i64, 0);
    const user_name = row.get([]const u8, 1);
    const post_title = row.get([]const u8, 2);
    // ...
}
```

### `first(db: Executor, allocator: Allocator, args: anytype) Result(?Model)`

Executes the query with `LIMIT 1` and returns the first result or `null`.

```zig
var query = Users.query();
defer query.deinit();
_ = query
    .where(.{ .field = .email, .operator = .eq, .value = .{ .string = "$1" } });

const result = query.first(db, allocator, .{email});
switch (result) {
    .ok => |maybe_user| {
        if (maybe_user) |user| {
            std.debug.print("Found: {s}\n", .{user.name});
        }
    },
    .err => |e| e.log(),
}
```

### `firstAs(comptime R: type, db: Executor, allocator: Allocator, args: anytype) Result(?R)`

Executes the query with `LIMIT 1` and returns the first result mapped to a custom type.

```zig
const UserStats = struct { id: i64, post_count: i64 };

const result = Users.query()
    .select(&.{.id})
    .selectAggregate(.count, .id, "post_count")
    .firstAs(UserStats, db, allocator, .{user_id});

switch (result) {
    .ok => |stats| { ... },
    .err => |e| e.log(),
}
```

### `firstWithRel(comptime R: type, db: Executor, allocator: Allocator, args: anytype) Result(?R)`

Same as `fetchWithRel` but returns only the first result or `null`.

```zig
const result = Users.query()
    .include(.{ .posts = .{ .model_name = .posts } })
    .where(.{ .field = .id, .operator = .eq, .value = .{ .string = "$1" } })
    .firstWithRel(Users.Rel.UsersWithPosts, db, allocator, .{user_id});

switch (result) {
    .ok => |maybe_user| {
        if (maybe_user) |u| {
            std.debug.print("Found user {s}\n", .{u.name});
        }
    },
    .err => |e| e.log(),
}
```

### `firstRaw(db: Executor, args: anytype) !?pg.Result`

Executes the query with `LIMIT 1` and returns the raw `pg.Result`, or `null` if no rows found.

> [!NOTE]
> The caller is responsible for calling `result.deinit()` when done.

## Aggregate Methods

All aggregate methods return `Result` types:

### `count(db: Executor, args: anytype) Result(i64)`

Executes a `COUNT(*)` query based on the current filters.

```zig
var query = Users.query();
defer query.deinit();
_ = query.where(.{ .field = .is_active, .operator = .eq, .value = .{ .boolean = true } });

const result = query.count(db, .{});
switch (result) {
    .ok => |count| std.debug.print("Active users: {d}\n", .{count}),
    .err => |e| e.log(),
}
```

### `exists(db: Executor, args: anytype) Result(bool)`

Check if any records match the query.

```zig
const result = query.exists(db, .{email});
switch (result) {
    .ok => |has_user| {
        if (has_user) { ... }
    },
    .err => |e| e.log(),
}
```

### `pluck(db: Executor, allocator: Allocator, field: Field, args: anytype) Result([][]const u8)`

Get a single column as a slice.

```zig
const result = query.pluck(db, allocator, .name, .{});
switch (result) {
    .ok => |names| {
        defer allocator.free(names);
        for (names) |name| {
            std.debug.print("{s}\n", .{name});
        }
    },
    .err => |e| e.log(),
}
```

### `sum`, `avg`, `min`, `max` - `Result(f64)`

Get aggregate values for a column.

```zig
const result = Orders.query().sum(db, .amount, .{});
switch (result) {
    .ok => |total| std.debug.print("Total: {d}\n", .{total}),
    .err => |e| e.log(),
}
```

### `min(db: *pg.Pool, field: Field, args: anytype) !f64`

Get the minimum value of a column.

```zig
const min_price = try Products.query().min(&pool, .price, .{});
```

### `max(db: *pg.Pool, field: Field, args: anytype) !f64`

Get the maximum value of a column.

```zig
const max_price = try Products.query().max(&pool, .price, .{});
```

## SQL Generation

### `buildSql(allocator: Allocator) ![]const u8`

Constructs and returns the raw SQL string that will be executed. Useful for debugging or manual execution.

```zig
const sql = try query.buildSql(allocator);
defer allocator.free(sql);
std.debug.print("Generated SQL: {s}\n", .{sql});
```

## Types

### `Operator`

- `.eq` (`=`)
- `.neq` (`!=`)
- `.gt` (`>`)
- `.gte` (`>=`)
- `.lt` (`<`)
- `.lte` (`<=`)
- `.like` (`LIKE`)
- `.ilike` (`ILIKE`)
- `.in` (`IN`)
- `.not_in` (`NOT IN`)
- `.is_null` (`IS NULL`)
- `.is_not_null` (`IS NOT NULL`)
- `.between` (`BETWEEN`)
- `.not_between` (`NOT BETWEEN`)

### `WhereValue`

```zig
union(enum) {
    string: []const u8,
    integer: i64,
    boolean: bool,
}
```

### `WhereClause`

```zig
struct {
    field: Field,
    operator: Operator,
    value: ?WhereValue = null, // Optional for IS NULL / IS NOT NULL
}
```

### `OrderByClause`

```zig
struct {
    field: Field,
    direction: enum { asc, desc },
}
```

### `JoinType`

- `.inner` (`INNER JOIN`)
- `.left` (`LEFT JOIN`)
- `.right` (`RIGHT JOIN`)
- `.full` (`FULL OUTER JOIN`)

### `AggregateType`

- `.count` (`COUNT`)
- `.sum` (`SUM`)
- `.avg` (`AVG`)
- `.min` (`MIN`)
- `.max` (`MAX`)

## Complex Query Examples

### Aggregated Results with `fetchAs`

When using JOINs, GROUP BY, or aggregates, you must use `fetchAs` with a custom struct:

```zig
const OrderStats = struct {
    user_id: i64,
    total: f64,
    order_count: i64,
};

var query = Orders.query();
defer query.deinit();

const results = try query
    .distinct()
    .select(&.{.user_id})
    .selectAggregate(.sum, .amount, "total")
    .selectAggregate(.count, .id, "order_count")
    .join(.{
        .join_type = .inner,
        .join_table = .users,
        .join_field = .{ .users = .id },
        .join_operator = .eq,
        .base_field = .{ .orders = .user_id },
    })
    .where(.{ .field = .status, .operator = .eq, .value = .{ .string = "'completed'" } })
    .whereBetween(.amount, .{ .integer = 10 }, .{ .integer = 10000 }, .integer)
    .groupBy(&.{.user_id})
    .havingAggregate(.sum, .amount, .gt, "100")
    .orderBy(.{ .field = .user_id, .direction = .asc })
    .paginate(2, 10)
    .fetchAs(OrderStats, &pool, allocator, .{});
defer allocator.free(results);

for (results) |stats| {
    std.debug.print("User {d}: total={d}, orders={d}\n", .{
        stats.user_id, stats.total, stats.order_count
    });
}
```

### Multiple Includes with fetchWithRel

```zig
var query = Users.query();
defer query.deinit();

_ = query
    .include(.{ .posts = .{ .model_name = .posts } })
    .include(.{ .comments = .{ .model_name = .comments } });

const users = try query.fetchWithRel(
    Users.Rel.UsersWithAllRelations,
    &pool,
    allocator,
    .{}
);
defer allocator.free(users);

for (users) |user| {
    std.debug.print("User: {s}\n", .{user.name});
    if (user.posts) |posts| {
        std.debug.print("  Posts: {d}\n", .{posts.len});
    }
    if (user.comments) |comments| {
        std.debug.print("  Comments: {d}\n", .{comments.len});
    }
}
```

### Simple Query with `fetch`

For basic queries without JOINs or aggregates, use `fetch` directly:

```zig
var query = Users.query();
defer query.deinit();

const active_users = try query
    .where(.{ .field = .status, .operator = .eq, .value = .{ .string = "'active'" } })
    .orderBy(.{ .field = .created_at, .direction = .desc })
    .limit(10)
    .fetch(&pool, allocator, .{});
defer allocator.free(active_users);

for (active_users) |user| {
    std.debug.print("User: {s}\n", .{user.name});
}
```
