# Base Model

The base model provides common CRUD (Create, Read, Update, Delete) and DDL operations for all generated models.

## Overview

Every generated model automatically includes methods from the base model, providing a consistent interface for database operations. Models are generated from your schema definitions using the TableSchema builder API.

## Generated Structure

When you run `zig build generate-models`, FluentORM generates:

- **Model files** (e.g., `users.zig`, `posts.zig`) with CRUD operations
- **base.zig** - Common utilities and CRUD implementations
- **query.zig** - Query builder for type-safe filtering
- **executor.zig** - Unified database executor (Pool or Conn)
- **transaction.zig** - Generic transaction support
- **root.zig** - Barrel export for easy imports

## The Executor Type

All model methods accept an `Executor` as their first argument. The executor abstracts over `*pg.Pool` (for direct operations) and `*pg.Conn` (for transactions):

```zig
const Executor = @import("executor.zig").Executor;

// Direct pool access
const user = try Users.findById(Executor.fromPool(pool), allocator, id);

// Within a transaction
var tx = try Transaction.begin(pool);
const user = try Users.findById(tx.executor(), allocator, id);
```

## CRUD Operations

### ⚠️ Memory Management for Insert Operations

**CRITICAL**: All insert operations (`insert`, `insertMany`, `upsert`) return **allocated UUID strings** that **MUST** be freed to prevent memory leaks:

```zig
// ✅ Correct: Free the returned ID
const user_id = try Users.insert(Executor.fromPool(pool), allocator, .{
    .email = "alice@example.com",
    .name = "Alice",
});
defer allocator.free(user_id);  // MUST free!

// ❌ Memory leak: ID not freed
_ = try Users.insert(Executor.fromPool(pool), allocator, .{...});  // LEAKS MEMORY
```

#### Multiple Inserts

When inserting multiple records, **each returned ID must be freed**:

```zig
const user1_id = try Users.insert(db, allocator, .{...});
defer allocator.free(user1_id);  // Free first ID

const user2_id = try Users.insert(db, allocator, .{...});
defer allocator.free(user2_id);  // Free second ID

const user3_id = try Users.insert(db, allocator, .{...});
defer allocator.free(user3_id);  // Free third ID
```

#### insertMany Return Value

`insertMany` returns a **slice** of allocated UUID strings:

```zig
const ids = try Users.insertMany(db, allocator, &.{
    .{ .name = "Alice", .email = "alice@example.com" },
    .{ .name = "Bob", .email = "bob@example.com" },
});
defer allocator.free(ids);  // Frees the slice AND all individual IDs
```

### Create (Insert)

Insert a new record and get back the primary key:

```zig
const user_id = try Users.insert(Executor.fromPool(pool), allocator, .{
    .email = "alice@example.com",
    .name = "Alice",
    .password_hash = "hashed_password",
});
defer allocator.free(user_id);  // MUST free!
```

**Note**: Fields marked with `.create_input = .excluded` (like auto-generated UUIDs and timestamps) are automatically excluded from the insert input struct.

#### Insert and Return Full Object

```zig
const user = try Users.insertAndReturn(Executor.fromPool(pool), allocator, .{
    .email = "alice@example.com",
    .name = "Alice",
    .password_hash = "hashed_password",
});
defer allocator.free(user);
```

### Read (Query)

#### Find by ID

```zig
if (try Users.findById(Executor.fromPool(pool), allocator, user_id)) |user| {
    defer allocator.free(user);
    std.debug.print("Found user: {s}\n", .{user.name});
}
```

Returns `null` if not found or if the record is soft-deleted.

#### Query with conditions

```zig
var query = Users.query();
defer query.deinit();

const users = try query
    .where(.{ .field = .email, .operator = .eq, .value = .{ .string = "$1" } })
    .fetch(Executor.fromPool(pool), allocator, .{"alice@example.com"});
defer allocator.free(users);
```

#### Fetch all records

```zig
const all_users = try Users.findAll(Executor.fromPool(pool), allocator, false);
defer allocator.free(all_users);
```

To include soft-deleted records, pass `true`:

```zig
const all_including_deleted = try Users.findAll(Executor.fromPool(pool), allocator, true);
defer allocator.free(all_including_deleted);
```

### Update

Update specific fields for a record:

```zig
try Users.update(Executor.fromPool(pool), user_id, .{
    .name = "Alice Smith",
    .email = "alice.smith@example.com",
});
```

**Note**: Fields marked with `.update_input = false` (like `created_at`, auto-generated IDs) are excluded from the update input struct.

#### Update and Return

```zig
const updated_user = try Users.updateAndReturn(Executor.fromPool(pool), allocator, user_id, .{
    .name = "Alice Smith",
});
defer allocator.free(updated_user);
```

### Upsert

Insert a record, or update if a unique constraint violation occurs:

```zig
const user_id = try Users.upsert(Executor.fromPool(pool), allocator, .{
    .email = "alice@example.com",
    .name = "Alice",
    .password_hash = "hashed_password",
});
defer allocator.free(user_id);
```

**Requirement**: Your schema must have at least one unique constraint (besides the primary key).

#### Upsert and Return

```zig
const user = try Users.upsertAndReturn(Executor.fromPool(pool), allocator, .{
    .email = "alice@example.com",
    .name = "Alice",
    .password_hash = "hashed_password",
});
defer allocator.free(user);
```

### Delete

#### Soft Delete

If your schema includes a `deleted_at` field, you can use soft deletes:

```zig
try Users.softDelete(Executor.fromPool(pool), user_id);
```

Soft-deleted records are automatically excluded from queries by default. Use `.withDeleted()` on queries to include them.

#### Hard Delete

Permanently removes the record:

```zig
try Users.hardDelete(Executor.fromPool(pool), user_id);
```

**Warning**: This is irreversible and bypasses any soft-delete logic.

## DDL Operations

Base models provide limited Data Definition Language (DDL) operations.

### Truncate Table

Remove all data but keep the table structure:

```zig
try Users.truncate(Executor.fromPool(pool));
```

**Warning**: This permanently deletes all data in the table.

### Check Table Existence

```zig
const exists = try Users.tableExists(Executor.fromPool(pool));
if (exists) {
    std.debug.print("Table exists\n", .{});
}
```

> **Note**: `createTable()`, `dropTable()`, and `createIndexes()` methods are not currently available. Use the generated SQL migration files to create/drop tables. See [MIGRATIONS.md](MIGRATIONS.md) for details.

## Utility Operations

### Count Records

```zig
const total_users = try Users.count(Executor.fromPool(pool), false);
std.debug.print("Total users: {d}\n", .{total_users});

// Include soft-deleted
const total_including_deleted = try Users.count(Executor.fromPool(pool), true);
```

### Convert Row to Model

Helper to convert a `pg.zig` row result into a model instance:

```zig
const user = try Users.fromRow(row, allocator);
```

### Get Table Name

```zig
const table_name = Users.tableName();
std.debug.print("Table: {s}\n", .{table_name});
```

## JSON Response Helpers

Generated models include JSON-safe response types that convert UUIDs from byte arrays to hex strings:

### JsonResponse

Includes all fields:

```zig
if (try Users.findById(&pool, allocator, user_id)) |user| {
    defer allocator.free(user);

    const json_response = try user.toJsonResponse();
    // json_response.id is now a [36]u8 hex string like "550e8400-e29b-41d4-a716-446655440000"
}
```

### JsonResponseSafe

Excludes fields marked with `.redacted = true` (like `password_hash`):

```zig
if (try Users.findById(&pool, allocator, user_id)) |user| {
    defer allocator.free(user);

    const safe_response = try user.toJsonResponseSafe();
    // password_hash is NOT included in this response
}
```

## Field Access

All model fields are accessible as struct members with proper Zig types:

```zig
std.debug.print("User: {s} ({s})\n", .{ user.name, user.email });
std.debug.print("Created at: {d}\n", .{user.created_at});
std.debug.print("Active: {}\n", .{user.is_active});
```

## Relationship Methods

If you've defined relationships in your schema, the generator creates typed methods for fetching related records.

### BelongsTo / HasOne (Many-to-One, One-to-One)

```zig
// Post belongs to User
if (try post.fetchPostAuthor(&pool, allocator)) |author| {
    defer allocator.free(author);
    std.debug.print("Author: {s}\n", .{author.name});
}

// Profile has one User
if (try profile.fetchProfileUser(&pool, allocator)) |user| {
    defer allocator.free(user);
    std.debug.print("User: {s}\n", .{user.name});
}
```

### HasMany (One-to-Many)

```zig
// User has many Posts (defined with t.hasMany())
const user_posts = try user.fetchPosts(&pool, allocator);
defer allocator.free(user_posts);

for (user_posts) |p| {
    std.debug.print("Post: {s}\n", .{p.title});
}

// User has many Comments
const user_comments = try user.fetchComments(&pool, allocator);
defer allocator.free(user_comments);
```

### Self-Referential Relationships

```zig
// Comment has parent comment (self-reference)
if (try comment.fetchParent(&pool, allocator)) |parent| {
    defer allocator.free(parent);
    std.debug.print("Reply to: {s}\n", .{parent.content});
}

// Comment has many replies (self-referential hasMany)
const replies = try comment.fetchReplies(&pool, allocator);
defer allocator.free(replies);
```

See [RELATIONSHIPS.md](RELATIONSHIPS.md) for more details on defining and querying relationships.

## Type Safety

FluentORM generates compile-time type-safe code:

- Field names are enum values (autocompletion support)
- PostgreSQL types map to appropriate Zig types
- Optional fields use Zig optionals (`?T`)
- Input structs only include allowed fields based on schema configuration

## Error Handling

All database operations return `Result` types that provide detailed error information:

### Using `switch` for Detailed Handling

```zig
const result = Users.insert(db, allocator, .{
    .email = "alice@example.com",
    .name = "Alice",
});

switch (result) {
    .ok => |user_id| {
        defer allocator.free(user_id);
        std.debug.print("Created user: {s}\n", .{user_id});
    },
    .err => |e| {
        if (e.isUniqueViolation()) {
            std.debug.print("Email already exists\n", .{});
            if (e.constraintName()) |c| {
                std.debug.print("Constraint: {s}\n", .{c});
            }
        } else {
            e.log(); // Log full error details
        }
    },
}
```

### Using `unwrap()` for Simple Propagation

```zig
// Propagates the underlying Zig error if Result is .err
const user_id = try Users.insert(db, allocator, .{
    .email = "alice@example.com",
    .name = "Alice",
}).unwrap();
defer allocator.free(user_id);
```

### OrmError Details

When an error occurs, `OrmError` provides:
- `code` - Categorized error type (UniqueViolation, ForeignKeyViolation, etc.)
- `message` - Human-readable error message
- `pg_error` - Full PostgreSQL error details (constraint, table, column, etc.)

### Common Error Codes

| Code | Description |
|------|-------------|
| `UniqueViolation` | Duplicate key (unique constraint failed) |
| `ForeignKeyViolation` | Referenced record doesn't exist |
| `NotNullViolation` | Required field was null |
| `NoRowsReturned` | Query returned no rows |

See [ERROR_HANDLING.md](ERROR_HANDLING.md) for complete documentation.

