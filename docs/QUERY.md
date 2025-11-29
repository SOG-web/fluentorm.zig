# Query Builder Documentation

The `QueryBuilder` provides a fluent API for constructing complex SQL queries in a type-safe manner.

> [!NOTE]
> Due to [ZLS issue #2515](https://github.com/zigtools/zls/issues/2515), auto-complete for `Field` enums (e.g., `.id`, `.name`) does not work in editors. However, **type safety is strictly enforced**: using an invalid field name will result in a compile-time error.

## Usage

```zig
const users = try User.query()
    .where(.{
        .field = .age,
        .operator = .gt,
        .value = "$1",
    })
    .orderBy(.{
        .field = .created_at,
        .direction = .desc,
    })
    .limit(10)
    .fetch(&pool, allocator, .{18});
```

## Methods

### `select(fields: []const Field)`

Specifies which columns to retrieve. Defaults to `SELECT *` if not called.

```zig
.select(&.{ .id, .name })
```

### `where(clause: WhereClause)`

Adds a `WHERE` clause. Multiple calls are combined with `AND`.

```zig
.where(.{
    .field = .status,
    .operator = .eq,
    .value = "$1",
})
```

### `orWhere(clause: WhereClause)`

Adds an `OR` condition to the `WHERE` clause.

```zig
.orWhere(.{
    .field = .status,
    .operator = .eq,
    .value = "$2",
})
```

### `orderBy(clause: OrderByClause)`

Sets the `ORDER BY` clause.

```zig
.orderBy(.{
    .field = .created_at,
    .direction = .desc, // .asc or .desc
})
```

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

### `withDeleted()`

Includes soft-deleted records (where `deleted_at` is not null) in the results.

```zig
.withDeleted()
```

## Execution Methods

### `fetch(db: *pg.Pool, allocator: Allocator, args: anytype) ![]T`

Executes the query and returns a slice of models.

### `first(db: *pg.Pool, allocator: Allocator, args: anytype) !?T`

Executes the query with `LIMIT 1` and returns the first result or `null`.

### `count(db: *pg.Pool, args: anytype) !i64`

Executes a `COUNT(*)` query based on the current filters.

### `count(db: *pg.Pool, args: anytype) !i64`

Executes a `COUNT(*)` query based on the current filters.

## SQL Generation

### `buildSql(allocator: Allocator) ![]const u8`

Constructs and returns the raw SQL string that will be executed. Useful for debugging or manual execution.

```zig
const sql = try query.buildSql(allocator);
defer allocator.free(sql);
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

### `WhereClause`

```zig
struct {
    field: Field,
    operator: Operator,
    value: ?[]const u8 = null, // Optional for IS NULL / IS NOT NULL
}
```
