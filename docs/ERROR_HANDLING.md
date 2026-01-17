# Error Handling

FluentORM provides a structured error handling system using `Result` types that give you detailed PostgreSQL error information when operations fail.

## Overview

All database operations return a `Result(T)` type instead of Zig error unions. This allows you to:
- Access detailed PostgreSQL error information (constraint names, table, column, etc.)
- Choose between detailed `switch` handling or simple `try` propagation
- Categorize errors with the `ErrorCode` enum

## The Result Type

```zig
const Result = union(enum) {
    ok: T,          // Success value
    err: OrmError,  // Detailed error info
};
```

### Handling Results with `switch`

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
        } else {
            e.log(); // Log full error details
        }
    },
}
```

### Using `unwrap()` for Simple Propagation

When you don't need detailed error handling at the call site:

```zig
const user_id = try Users.insert(db, allocator, .{
    .email = "alice@example.com",
    .name = "Alice",
}).unwrap();
defer allocator.free(user_id);
```

## OrmError Structure

```zig
pub const OrmError = struct {
    code: ErrorCode,           // Categorized error type
    message: []const u8,       // Error message
    err: ?anyerror,            // Underlying Zig error
    pg_error: ?pg.Error,       // Full PostgreSQL error details
};
```

### ErrorCode Enum

| Code | Description |
|------|-------------|
| `UniqueViolation` | Duplicate key (e.g., unique constraint failed) |
| `ForeignKeyViolation` | Referenced record doesn't exist |
| `NotNullViolation` | Required field was null |
| `CheckViolation` | Check constraint failed |
| `NoRowsReturned` | Query returned no rows when expected |
| `SyntaxError` | SQL syntax error |
| `UndefinedTable` | Table doesn't exist |
| `UndefinedColumn` | Column doesn't exist |
| `ConnectionError` | Database connection issue |
| `DatabaseError` | General database error |
| `Unknown` | Unrecognized error |

### Helper Methods

```zig
// Check error type
if (e.isUniqueViolation()) { ... }
if (e.isForeignKeyViolation()) { ... }
if (e.isNotNullViolation()) { ... }

// Access PostgreSQL error details
const constraint = e.constraintName();  // e.g., "users_email_key"
const table = e.tableName();            // e.g., "users"
const column = e.columnName();          // e.g., "email"
const detail = e.detail();              // e.g., "Key (email)=(x) already exists"
const hint = e.hint();                  // PostgreSQL hint if available
const pg_code = e.pgCode();             // e.g., "23505"

// Log error with full details
e.log();
```

## Common Patterns

### Handling Unique Constraint Violations

```zig
const result = Users.insert(db, allocator, .{
    .email = email,
    .name = name,
});

switch (result) {
    .ok => |id| {
        defer allocator.free(id);
        return .{ .success = true, .id = id };
    },
    .err => |e| {
        if (e.isUniqueViolation()) {
            if (e.constraintName()) |constraint| {
                if (std.mem.eql(u8, constraint, "users_email_key")) {
                    return .{ .error = "Email already registered" };
                }
            }
            return .{ .error = "Duplicate entry" };
        }
        e.log();
        return .{ .error = "Database error" };
    },
}
```

### Propagating Errors Up the Call Stack

```zig
pub fn createUser(db: Executor, allocator: Allocator, data: CreateInput) ![]const u8 {
    // unwrap() returns the underlying Zig error for propagation
    return try Users.insert(db, allocator, data).unwrap();
}
```

### Query Builder Error Handling

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
    .err => |e| {
        e.log();
    },
}
```

## PostgreSQL Error Details

When a PostgreSQL error occurs, `OrmError.pg_error` contains the full error from the database:

```zig
if (e.pg_error) |pge| {
    std.debug.print("PG Code: {s}\n", .{pge.code});
    std.debug.print("Message: {s}\n", .{pge.message});
    std.debug.print("Severity: {s}\n", .{pge.severity});
    
    if (pge.detail) |d| std.debug.print("Detail: {s}\n", .{d});
    if (pge.hint) |h| std.debug.print("Hint: {s}\n", .{h});
    if (pge.constraint) |c| std.debug.print("Constraint: {s}\n", .{c});
    if (pge.table) |t| std.debug.print("Table: {s}\n", .{t});
    if (pge.column) |c| std.debug.print("Column: {s}\n", .{c});
}
```

> [!NOTE]
> FluentORM uses `pg.Error` directly from pg.zig - no duplication of error structures.

## Methods Returning Result Types

### Base Model Methods

| Method | Return Type |
|--------|-------------|
| `insert` | `Result([]const u8)` |
| `insertMany` | `Result([][]const u8)` |
| `insertAndReturn` | `Result(Model)` |
| `findById` | `Result(?Model)` |
| `findAll` | `Result([]Model)` |
| `update` | `Result(void)` |
| `updateAndReturn` | `Result(Model)` |
| `upsert` | `Result([]const u8)` |
| `upsertAndReturn` | `Result(Model)` |
| `softDelete` | `Result(void)` |
| `hardDelete` | `Result(void)` |
| `truncate` | `Result(void)` |
| `count` | `Result(i64)` |

### Query Builder Methods

| Method | Return Type |
|--------|-------------|
| `fetch` | `Result([]Model)` |
| `fetchAs` | `Result([]R)` |
| `fetchWithRel` | `Result([]R)` |
| `first` | `Result(?Model)` |
| `firstAs` | `Result(?R)` |
| `firstWithRel` | `Result(?R)` |
| `delete` | `Result(void)` |
| `count` | `Result(i64)` |
| `exists` | `Result(bool)` |
| `pluck` | `Result([][]const u8)` |
| `sum`, `avg`, `min`, `max` | `Result(f64)` |
