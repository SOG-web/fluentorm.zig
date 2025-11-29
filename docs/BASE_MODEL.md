# Base Model Documentation

The `BaseModel` provides the core CRUD and DDL operations for all generated models.

## Generated Methods

Every generated model struct (e.g., `User`) has these static methods available.

### CRUD Operations

#### `findById(db: *pg.Pool, allocator: Allocator, id: []const u8) !?T`

Finds a single record by its primary key (UUID).

- Returns `null` if not found.
- Respects `deleted_at` if present (returns `null` for soft-deleted records).

#### `findAll(db: *pg.Pool, allocator: Allocator, include_deleted: bool) ![]T`

Returns all records in the table.

- `include_deleted`: If `true`, includes soft-deleted records.

#### `insert(db: *pg.Pool, allocator: Allocator, data: CreateInput) ![]const u8`

Inserts a new record.

- Returns the generated `id`.
- `CreateInput` is a generated struct containing all required and optional fields.

#### `insertAndReturn(db: *pg.Pool, allocator: Allocator, data: CreateInput) !T`

Inserts a record and returns the full model object.

#### `update(db: *pg.Pool, id: []const u8, data: UpdateInput) !void`

Updates an existing record.

- `UpdateInput` contains optional fields for all updatable columns.

#### `updateAndReturn(db: *pg.Pool, allocator: Allocator, id: []const u8, data: UpdateInput) !T`

Updates a record and returns the full updated model object.

#### `upsert(db: *pg.Pool, allocator: Allocator, data: CreateInput) ![]const u8`

Inserts a record, or updates it if a unique constraint violation occurs.

- Requires a unique index to be defined in the schema.
- Returns the `id`.

#### `upsertAndReturn(db: *pg.Pool, allocator: Allocator, data: CreateInput) !T`

Upserts and returns the full model object.

### Deletion

#### `softDelete(db: *pg.Pool, id: []const u8) !void`

Sets the `deleted_at` timestamp to the current time.

- **Requirement**: Schema must have a `deleted_at` field.

#### `hardDelete(db: *pg.Pool, id: []const u8) !void`

Permanently removes the record from the database.

### DDL Operations

#### `createTable(db: *pg.Pool) !void`

Creates the table if it does not exist.

#### `createIndexes(db: *pg.Pool) !void`

Creates all indexes defined in the schema.

#### `dropTable(db: *pg.Pool) !void`

Drops the table if it exists.

#### `truncate(db: *pg.Pool) !void`

Removes all data from the table but keeps the structure.

#### `tableExists(db: *pg.Pool) !bool`

Checks if the table exists in the database.

### Utilities

#### `count(db: *pg.Pool, include_deleted: bool) !i64`

Returns the total number of records.

#### `fromRow(row: anytype, allocator: Allocator) !T`

Helper to convert a `pg.zig` row result into a model instance.

#### `tableName() []const u8`

Returns the SQL table name.
