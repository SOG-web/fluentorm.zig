# Database Introspection (db pull)

The database introspection feature allows you to generate Zig model schemas by connecting to an existing PostgreSQL database and extracting its schema information.

## Overview

The `db pull` command:
1. Connects to your PostgreSQL database
2. Reads table structures, columns, indexes, and relationships
3. Generates Zig schema definition files that can be used with FluentORM

This is useful when:
- You have an existing database and want to use FluentORM
- You're migrating from another ORM or framework
- You want to reverse-engineer a database schema

## Usage

### Basic Usage

```bash
# Using environment variable
export DATABASE_URL="postgresql://user:password@localhost:5432/mydb"
zig build db-pull

# Or with command line argument
zig build db-pull -- --database-url postgresql://user:password@localhost:5432/mydb
```

### Command Line Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--database-url` | `-d` | PostgreSQL connection URL | `DATABASE_URL` env |
| `--schema` | `-s` | Database schema to introspect | `public` |
| `--output` | `-o` | Output directory for models | `src/models/generated` |
| `--schemas-dir` | | Output directory for schema files | `schemas` |
| `--include` | | Comma-separated tables to include | All tables |
| `--exclude` | | Comma-separated tables to exclude | None |
| `--env-file` | | Path to .env file | `.env` |
| `--no-schemas` | | Skip generating schema files | false |
| `--report-only` | | Only show report, no file generation | false |
| `--help` | `-h` | Show help message | |

### Examples

```bash
# Introspect specific tables only
zig build db-pull -- --include users,posts,comments

# Exclude certain tables
zig build db-pull -- --exclude temp_data,logs,migrations

# Use a different schema
zig build db-pull -- --schema myapp

# Just see what would be generated
zig build db-pull -- --report-only

# Custom output directories
zig build db-pull -- --output src/db/models --schemas-dir src/db/schemas
```

## Generated Files

### Schema Files

For each table, a schema definition file is generated in the schemas directory:

```zig
// schemas/users.zig
const fluentzig = @import("fluentorm");
const TableSchema = fluentzig.TableSchema;

pub fn define(self: *TableSchema) void {
    self.uuidPrimaryKey(.{
        .name = "id",
        .primary_key = true,
    });
    self.string(.{
        .name = "email",
        .unique = true,
    });
    self.string(.{
        .name = "password_hash",
        .redacted = true,
    });
    self.timestamp(.{
        .name = "created_at",
    });

    // Foreign Key Relationships
    self.belongsTo(.{
        .name = "fk_users_organization",
        .column = "organization_id",
        .references_table = "organizations",
        .references_column = "id",
        .on_delete = .cascade,
        .on_update = .no_action,
    });
}
```

### Registry File

A `registry.zig` file is generated that imports all schemas:

```zig
// schemas/registry.zig
const fluentzig = @import("fluentorm");

const users_schema = @import("users.zig");
const posts_schema = @import("posts.zig");

pub const schemas = [_]fluentzig.SchemaBuilder{
    .{ .name = "users", .builder_fn = users_schema.define },
    .{ .name = "posts", .builder_fn = posts_schema.define },
};
```

## Type Mapping

PostgreSQL types are automatically mapped to Zig types:

| PostgreSQL | Zig Type | FluentORM Field |
|------------|----------|-----------------|
| `uuid` | `[]const u8` | `.uuid` |
| `text`, `varchar`, `char` | `[]const u8` | `.text` |
| `boolean` | `bool` | `.bool` |
| `smallint`, `int2` | `i16` | `.i16` |
| `integer`, `int4`, `serial` | `i32` | `.i32` |
| `bigint`, `int8`, `bigserial` | `i64` | `.i64` |
| `real`, `float4` | `f32` | `.f32` |
| `double precision`, `numeric` | `f64` | `.f64` |
| `timestamp`, `timestamptz` | `i64` | `.timestamp` |
| `json` | `[]const u8` | `.json` |
| `jsonb` | `[]const u8` | `.jsonb` |
| `bytea` | `[]const u8` | `.binary` |

Nullable columns are mapped to optional types (e.g., `?[]const u8`).

## Auto-Detection

The introspector automatically detects:

### Primary Keys
Columns in PRIMARY KEY constraints are marked with `.primary_key = true`.

### Auto-Generated Fields
- `SERIAL`/`BIGSERIAL` columns → `.auto_generate_type = .increments`
- UUID with `gen_random_uuid()` default → `.auto_generate_type = .uuid`
- Timestamp with `CURRENT_TIMESTAMP` default → `.auto_generate_type = .timestamp`

### Relationships
- Foreign key constraints are converted to `belongsTo` relationships
- Inverse relationships (`hasMany`) are inferred from other tables' foreign keys

### Redacted Fields
Fields with names containing `password`, `secret`, `token`, `api_key`, or `private_key` are automatically marked as `.redacted = true`.

## Excluded Tables

The following tables are automatically excluded from introspection:
- `schema_migrations`
- `_prisma_migrations`
- `knex_migrations` / `knex_migrations_lock`
- `typeorm_metadata`
- `ar_internal_metadata`
- `__diesel_schema_migrations`
- `flyway_schema_history`
- `databasechangelog` / `databasechangeloglock`

Use `--exclude` to add more tables to exclude.

## Workflow

After running `db pull`:

1. Review the generated schema files in `schemas/`
2. Make any necessary adjustments (e.g., adding custom relationships)
3. Run `zig build generate-models` to generate the full model code
4. Use the generated models in your application

## Programmatic Usage

You can also use the introspection module programmatically:

```zig
const std = @import("std");
const fluentorm = @import("fluentorm");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create connection pool
    var pool = try fluentorm.introspection.introspector.createPool(
        allocator,
        "postgresql://user:pass@localhost:5432/mydb",
    );
    defer pool.deinit();

    // Introspect database
    var intro = fluentorm.introspection.Introspector.init(allocator, pool, .{
        .schema_name = "public",
    });
    var db = try intro.introspect();
    defer db.deinit();

    // Generate report
    const report = try fluentorm.introspection.generator.generateReport(allocator, &db);
    defer allocator.free(report);
    std.debug.print("{s}\n", .{report});

    // Convert to TableSchema
    const schemas = try fluentorm.introspection.converter.convertDatabase(allocator, &db, .{});
    defer {
        for (schemas) |*s| s.deinit();
        allocator.free(schemas);
    }
}
```

## Troubleshooting

### Connection Issues

```
❌ Failed to connect to database
```

- Verify your DATABASE_URL is correct
- Check that PostgreSQL is running
- Ensure your user has permission to access the database

### No Tables Found

- Check that you're using the correct schema (default is `public`)
- Verify your user has SELECT permission on `information_schema`

### Missing Relationships

Foreign key relationships are only detected if they exist as actual database constraints. If your application uses "soft" foreign keys without constraints, you'll need to add the relationships manually to the generated schema files.
