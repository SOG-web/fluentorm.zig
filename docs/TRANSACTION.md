# Transaction Documentation

FluentORM provides a generic `Transaction` system that works with any model, allowing you to perform multiple model operations atomically within a single database transaction.

## Quick Start

```zig
const Transaction = @import("transaction.zig").Transaction;
const Executor = @import("executor.zig").Executor;

// Begin a transaction
var tx = try Transaction.begin(pool);
defer tx.deinit(); // Auto-rollback if not committed

// Use any model with tx.executor()
const user_id = try Users.insert(tx.executor(), allocator, .{
    .email = "alice@example.com",
    .name = "Alice",
    .password_hash = "hash",
});

// Query within the same transaction
var query = Users.query();
const user = try query
    .where(.{ .field = .id, .operator = .eq, .value = .{ .string = "$1" } })
    .first(tx.executor(), allocator, .{user_id});

// Operations on different models
_ = try Posts.insert(tx.executor(), allocator, .{
    .user_id = user_id,
    .title = "First Post",
    .content = "Hello!",
});

// Raw SQL
try tx.exec("UPDATE stats SET user_count = user_count + 1", .{});

// Commit all changes atomically
try tx.commit();
```

## API Reference

### Transaction Struct

#### `begin(pool: *pg.Pool) !Transaction`

Acquires a connection from the pool and starts a transaction (`BEGIN`).

```zig
var tx = try Transaction.begin(pool);
```

#### `executor() Executor`

Returns an `Executor` that can be passed to any model method. This is how you use models within the transaction.

```zig
const user_id = try Users.insert(tx.executor(), allocator, data);
const posts = try Posts.query().fetch(tx.executor(), allocator, .{});
```

#### `commit() !void`

Commits the transaction (`COMMIT`) and releases the connection back to the pool.

```zig
try tx.commit();
```

**Errors:**

- `error.TransactionAlreadyCommitted` - Already committed
- `error.TransactionAlreadyRolledBack` - Already rolled back

#### `rollback() !void`

Rolls back the transaction (`ROLLBACK`) and releases the connection.

```zig
try tx.rollback();
```

#### `deinit()`

Automatically rolls back if not committed or rolled back. Use with `defer`:

```zig
var tx = try Transaction.begin(pool);
defer tx.deinit(); // Safe cleanup
```

#### `exec(sql: []const u8, args: anytype) !void`

Execute raw SQL within the transaction:

```zig
try tx.exec("UPDATE counters SET value = value + 1 WHERE name = $1", .{"visits"});
```

#### `query(sql: []const u8, args: anytype) !pg.Result`

Execute a raw query within the transaction:

```zig
var result = try tx.query("SELECT * FROM logs WHERE level = $1", .{"error"});
defer result.deinit();
```

## The Executor Type

The `Executor` is a union type that abstracts over `*pg.Pool` and `*pg.Conn`:

```zig
pub const Executor = union(enum) {
    pool: *pg.Pool,
    conn: *pg.Conn,
};
```

### Creating Executors

```zig
// From a pool (for non-transactional operations)
const exec = Executor.fromPool(pool);

// From a transaction
const exec = tx.executor();
```

### Using with Models

All model methods accept `Executor` as their first argument:

```zig
// Non-transactional
const user = try Users.findById(Executor.fromPool(pool), allocator, id);

// Transactional
const user = try Users.findById(tx.executor(), allocator, id);
```

## Common Patterns

### Error Handling with Auto-Rollback

```zig
fn createUserWithProfile(pool: *pg.Pool, allocator: Allocator) !void {
    var tx = try Transaction.begin(pool);
    defer tx.deinit(); // Rollback on error

    const user_id = try Users.insert(tx.executor(), allocator, .{...});

    // If this fails, deinit() will rollback the user insert
    try Profiles.insert(tx.executor(), allocator, .{
        .user_id = user_id,
        ...
    });

    try tx.commit();
}
```

### Multi-Model Operations

```zig
var tx = try Transaction.begin(pool);
defer tx.deinit();

// Work with multiple models
const order_id = try Orders.insert(tx.executor(), allocator, order_data);

for (items) |item| {
    try OrderItems.insert(tx.executor(), allocator, .{
        .order_id = order_id,
        .product_id = item.product_id,
        .quantity = item.quantity,
    });
}

// Update inventory
for (items) |item| {
    try tx.exec(
        "UPDATE products SET stock = stock - $1 WHERE id = $2",
        .{item.quantity, item.product_id}
    );
}

try tx.commit();
```

### Querying Within Transactions

```zig
var tx = try Transaction.begin(pool);
defer tx.deinit();

// Insert and verify
const user_id = try Users.insert(tx.executor(), allocator, .{...});

var query = Users.query();
defer query.deinit();

const user = try query
    .where(.{ .field = .id, .operator = .eq, .value = .{ .string = "$1" } })
    .first(tx.executor(), allocator, .{user_id});

if (user == null) {
    return error.InsertVerificationFailed;
}

try tx.commit();
```

## Migration from Old API

If you were using the old model-specific Transaction API:

**Before (deprecated):**

```zig
var tx = try Transaction(Users).begin(conn);
const user_id = try tx.insert(allocator, data);
```

**After (new generic API):**

```zig
var tx = try Transaction.begin(pool);
defer tx.deinit();
const user_id = try Users.insert(tx.executor(), allocator, data);
try tx.commit();
```

Key changes:

1. `Transaction` is no longer parameterized by model type
2. Pass `pool` instead of `conn` to `begin()`
3. Use `tx.executor()` with any model's methods
4. Explicit `tx.commit()` required
