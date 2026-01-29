// Database Introspector
// Connects to PostgreSQL and extracts complete schema information

const std = @import("std");
const pg = @import("pg");

const queries = @import("queries.zig");
const types = @import("types.zig");

pub const IntrospectorError = error{
    ConnectionFailed,
    SchemaNotFound,
    QueryFailed,
    InvalidData,
    OutOfMemory,
};

pub const IntrospectorOptions = struct {
    schema_name: []const u8 = queries.DEFAULT_SCHEMA,
    include_tables: ?[]const []const u8 = null, // null means all tables
    exclude_tables: []const []const u8 = &.{}, // Additional tables to exclude
};

pub const Introspector = struct {
    allocator: std.mem.Allocator,
    pool: *pg.Pool,
    options: IntrospectorOptions,

    pub fn init(allocator: std.mem.Allocator, pool: *pg.Pool, options: IntrospectorOptions) Introspector {
        return Introspector{
            .allocator = allocator,
            .pool = pool,
            .options = options,
        };
    }

    /// Introspect the entire database schema
    pub fn introspect(self: *Introspector) !types.IntrospectedDatabase {
        var db = types.IntrospectedDatabase.init(self.allocator);
        errdefer db.deinit();

        // Get all tables
        const tables = try self.getTables();
        defer {
            for (tables) |t| {
                self.allocator.free(t.name);
                self.allocator.free(t.schema_name);
            }
            self.allocator.free(tables);
        }

        // Introspect each table
        for (tables) |table_info| {
            const table = try self.introspectTable(table_info.name);
            try db.tables.append(self.allocator, table);
        }

        return db;
    }

    /// Introspect a single table
    pub fn introspectTable(self: *Introspector, table_name: []const u8) !types.IntrospectedTable {
        var table = try types.IntrospectedTable.init(self.allocator, table_name, self.options.schema_name);
        errdefer table.deinit();

        // Get columns
        try self.fetchColumns(&table);

        // Get primary key
        try self.fetchPrimaryKey(&table);

        // Get foreign keys
        try self.fetchForeignKeys(&table);

        // Get unique constraints
        try self.fetchUniqueConstraints(&table);

        // Get indexes
        try self.fetchIndexes(&table);

        return table;
    }

    const TableInfo = struct {
        name: []const u8,
        schema_name: []const u8,
    };

    fn getTables(self: *Introspector) ![]TableInfo {
        var result = self.pool.query(queries.TABLES_QUERY, .{self.options.schema_name}) catch {
            return IntrospectorError.QueryFailed;
        };
        defer result.deinit();

        var tables = std.ArrayList(TableInfo){};
        errdefer {
            for (tables.items) |t| {
                self.allocator.free(t.name);
                self.allocator.free(t.schema_name);
            }
            tables.deinit(self.allocator);
        }

        while (try result.next()) |row| {
            const table_name = row.get([]const u8, 0);
            const schema_name = row.get([]const u8, 1);

            // Skip excluded tables
            if (queries.isExcludedTable(table_name)) continue;
            if (self.isUserExcluded(table_name)) continue;

            // Check if in include list (if specified)
            if (self.options.include_tables) |include_list| {
                var found = false;
                for (include_list) |include_name| {
                    if (std.mem.eql(u8, table_name, include_name)) {
                        found = true;
                        break;
                    }
                }
                if (!found) continue;
            }

            try tables.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, table_name),
                .schema_name = try self.allocator.dupe(u8, schema_name),
            });
        }

        return tables.toOwnedSlice(self.allocator);
    }

    fn isUserExcluded(self: *Introspector, table_name: []const u8) bool {
        for (self.options.exclude_tables) |excluded| {
            if (std.mem.eql(u8, table_name, excluded)) {
                return true;
            }
        }
        return false;
    }

    fn fetchColumns(self: *Introspector, table: *types.IntrospectedTable) !void {
        var result = self.pool.query(
            queries.COLUMNS_QUERY,
            .{ self.options.schema_name, table.table_name },
        ) catch {
            return IntrospectorError.QueryFailed;
        };
        defer result.deinit();

        while (try result.next()) |row| {
            const column = types.IntrospectedColumn{
                .name = try self.allocator.dupe(u8, row.get([]const u8, 0)),
                .data_type = try self.allocator.dupe(u8, row.get([]const u8, 1)),
                .udt_name = try self.allocator.dupe(u8, row.get([]const u8, 2)),
                .is_nullable = blk: {
                    const nullable_str = row.get([]const u8, 3);
                    break :blk std.mem.eql(u8, nullable_str, "YES");
                },
                .column_default = if (row.get(?[]const u8, 4)) |def|
                    try self.allocator.dupe(u8, def)
                else
                    null,
                .is_identity = blk: {
                    const identity_str = row.get([]const u8, 5);
                    break :blk std.mem.eql(u8, identity_str, "YES");
                },
                .identity_generation = if (row.get(?[]const u8, 6)) |gen|
                    try self.allocator.dupe(u8, gen)
                else
                    null,
                .character_maximum_length = row.get(?i32, 7),
                .numeric_precision = row.get(?i32, 8),
                .numeric_scale = row.get(?i32, 9),
                .ordinal_position = row.get(i32, 10),
            };
            try table.columns.append(self.allocator, column);
        }
    }

    fn fetchPrimaryKey(self: *Introspector, table: *types.IntrospectedTable) !void {
        var result = self.pool.query(
            queries.PRIMARY_KEY_QUERY,
            .{ self.options.schema_name, table.table_name },
        ) catch {
            return IntrospectorError.QueryFailed;
        };
        defer result.deinit();

        var pk: ?types.IntrospectedPrimaryKey = null;

        while (try result.next()) |row| {
            const constraint_name = row.get([]const u8, 0);
            const column_name = row.get([]const u8, 1);

            if (pk == null) {
                pk = types.IntrospectedPrimaryKey{
                    .constraint_name = try self.allocator.dupe(u8, constraint_name),
                    .columns = std.ArrayList([]const u8){},
                };
            }

            try pk.?.columns.append(self.allocator, try self.allocator.dupe(u8, column_name));
        }

        table.primary_key = pk;
    }

    fn fetchForeignKeys(self: *Introspector, table: *types.IntrospectedTable) !void {
        var result = self.pool.query(
            queries.FOREIGN_KEYS_QUERY,
            .{ self.options.schema_name, table.table_name },
        ) catch {
            return IntrospectorError.QueryFailed;
        };
        defer result.deinit();

        while (try result.next()) |row| {
            const fk = types.IntrospectedForeignKey{
                .constraint_name = try self.allocator.dupe(u8, row.get([]const u8, 0)),
                .column_name = try self.allocator.dupe(u8, row.get([]const u8, 1)),
                .foreign_table_schema = try self.allocator.dupe(u8, row.get([]const u8, 2)),
                .foreign_table_name = try self.allocator.dupe(u8, row.get([]const u8, 3)),
                .foreign_column_name = try self.allocator.dupe(u8, row.get([]const u8, 4)),
                .on_delete = try self.allocator.dupe(u8, row.get([]const u8, 5)),
                .on_update = try self.allocator.dupe(u8, row.get([]const u8, 6)),
            };
            try table.foreign_keys.append(self.allocator, fk);
        }
    }

    fn fetchUniqueConstraints(self: *Introspector, table: *types.IntrospectedTable) !void {
        var result = self.pool.query(
            queries.UNIQUE_CONSTRAINTS_QUERY,
            .{ self.options.schema_name, table.table_name },
        ) catch {
            return IntrospectorError.QueryFailed;
        };
        defer result.deinit();

        var constraint_map = std.StringHashMap(*types.IntrospectedUnique).init(self.allocator);
        defer constraint_map.deinit();

        while (try result.next()) |row| {
            const constraint_name = row.get([]const u8, 0);
            const column_name = row.get([]const u8, 1);

            if (constraint_map.get(constraint_name)) |uc| {
                try uc.columns.append(self.allocator, try self.allocator.dupe(u8, column_name));
            } else {
                var uc = try self.allocator.create(types.IntrospectedUnique);
                uc.* = types.IntrospectedUnique{
                    .constraint_name = try self.allocator.dupe(u8, constraint_name),
                    .columns = std.ArrayList([]const u8){},
                };
                try uc.columns.append(self.allocator, try self.allocator.dupe(u8, column_name));
                try constraint_map.put(constraint_name, uc);
                try table.unique_constraints.append(self.allocator, uc.*);
            }
        }

        // Clean up allocated constraint pointers
        var iter = constraint_map.valueIterator();
        while (iter.next()) |uc| {
            self.allocator.destroy(uc.*);
        }
    }

    fn fetchIndexes(self: *Introspector, table: *types.IntrospectedTable) !void {
        var result = self.pool.query(
            queries.INDEXES_QUERY,
            .{ self.options.schema_name, table.table_name },
        ) catch {
            return IntrospectorError.QueryFailed;
        };
        defer result.deinit();

        var index_map = std.StringHashMap(usize).init(self.allocator);
        defer index_map.deinit();

        while (try result.next()) |row| {
            const index_name = row.get([]const u8, 0);
            const column_name = row.get([]const u8, 1);
            const is_unique = row.get(bool, 2);
            const is_primary = row.get(bool, 3);
            const index_type = row.get([]const u8, 4);

            if (index_map.get(index_name)) |idx_pos| {
                // Add column to existing index
                try table.indexes.items[idx_pos].columns.append(
                    self.allocator,
                    try self.allocator.dupe(u8, column_name),
                );
            } else {
                // Create new index
                var idx = types.IntrospectedIndex{
                    .index_name = try self.allocator.dupe(u8, index_name),
                    .columns = std.ArrayList([]const u8){},
                    .is_unique = is_unique,
                    .is_primary = is_primary,
                    .index_type = try self.allocator.dupe(u8, index_type),
                };
                try idx.columns.append(self.allocator, try self.allocator.dupe(u8, column_name));

                const pos = table.indexes.items.len;
                try table.indexes.append(self.allocator, idx);
                try index_map.put(try self.allocator.dupe(u8, index_name), pos);
            }
        }

        // Free duplicated keys from index_map
        var key_iter = index_map.keyIterator();
        while (key_iter.next()) |key| {
            self.allocator.free(key.*);
        }
    }
};

/// Parsed database URL components
pub const DbUrlComponents = struct {
    host: []const u8,
    port: u16,
    database: []const u8,
    username: []const u8,
    password: ?[]const u8,
};

/// Parse a PostgreSQL connection URL
/// Format: postgresql://user:password@host:port/database
pub fn parseDbUrl(url: []const u8) !DbUrlComponents {
    // Skip protocol prefix
    var rest = url;
    if (std.mem.startsWith(u8, rest, "postgresql://")) {
        rest = rest[13..];
    } else if (std.mem.startsWith(u8, rest, "postgres://")) {
        rest = rest[11..];
    }

    // Find @ separator for credentials
    var username: []const u8 = "postgres";
    var password: ?[]const u8 = null;

    if (std.mem.indexOf(u8, rest, "@")) |at_pos| {
        const creds = rest[0..at_pos];
        rest = rest[at_pos + 1..];

        if (std.mem.indexOf(u8, creds, ":")) |colon_pos| {
            username = creds[0..colon_pos];
            password = creds[colon_pos + 1..];
        } else {
            username = creds;
        }
    }

    // Find / separator for database
    var host: []const u8 = "localhost";
    var port: u16 = 5432;
    var database: []const u8 = "postgres";

    if (std.mem.indexOf(u8, rest, "/")) |slash_pos| {
        const host_port = rest[0..slash_pos];
        database = rest[slash_pos + 1..];

        // Remove query params from database name
        if (std.mem.indexOf(u8, database, "?")) |q_pos| {
            database = database[0..q_pos];
        }

        if (std.mem.indexOf(u8, host_port, ":")) |colon_pos| {
            host = host_port[0..colon_pos];
            port = std.fmt.parseInt(u16, host_port[colon_pos + 1..], 10) catch 5432;
        } else {
            host = host_port;
        }
    } else {
        // No database specified, just host:port
        if (std.mem.indexOf(u8, rest, ":")) |colon_pos| {
            host = rest[0..colon_pos];
            port = std.fmt.parseInt(u16, rest[colon_pos + 1..], 10) catch 5432;
        } else {
            host = rest;
        }
    }

    return DbUrlComponents{
        .host = host,
        .port = port,
        .database = database,
        .username = username,
        .password = password,
    };
}

/// Create a connection pool from database URL
pub fn createPool(allocator: std.mem.Allocator, database_url: []const u8) !*pg.Pool {
    const components = parseDbUrl(database_url) catch {
        return IntrospectorError.ConnectionFailed;
    };

    return pg.Pool.init(allocator, .{
        .size = 1,
        .connect = .{
            .host = components.host,
            .port = components.port,
        },
        .auth = .{
            .username = components.username,
            .password = components.password,
            .database = components.database,
        },
    }) catch {
        return IntrospectorError.ConnectionFailed;
    };
}

/// Helper to run introspection from a database URL
pub fn introspectFromUrl(
    allocator: std.mem.Allocator,
    database_url: []const u8,
    options: IntrospectorOptions,
) !types.IntrospectedDatabase {
    var pool = try createPool(allocator, database_url);
    defer pool.deinit();

    var introspector = Introspector.init(allocator, pool, options);
    return introspector.introspect();
}
