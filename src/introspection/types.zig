// Database Introspection Types
// Represents the structure of database objects extracted from PostgreSQL system catalogs

const std = @import("std");
const schema = @import("../schema.zig");

/// Represents a database column extracted from introspection
pub const IntrospectedColumn = struct {
    name: []const u8,
    data_type: []const u8,
    udt_name: []const u8, // PostgreSQL underlying type
    is_nullable: bool,
    column_default: ?[]const u8,
    is_identity: bool,
    identity_generation: ?[]const u8, // 'ALWAYS' or 'BY DEFAULT'
    character_maximum_length: ?i32,
    numeric_precision: ?i32,
    numeric_scale: ?i32,
    ordinal_position: i32,

    /// Convert PostgreSQL type to ORM FieldType
    pub fn toFieldType(self: IntrospectedColumn) schema.FieldType {
        const base_type = mapPgTypeToFieldType(self.udt_name, self.data_type);
        if (self.is_nullable) {
            return toOptional(base_type);
        }
        return base_type;
    }

    /// Determine auto-generation type based on column properties
    pub fn getAutoGenerateType(self: IntrospectedColumn) schema.AutoGenerateType {
        // Check for serial/identity columns
        if (self.is_identity) {
            return .increments;
        }

        // Check default value patterns
        if (self.column_default) |default| {
            if (std.mem.indexOf(u8, default, "nextval(") != null) {
                return .increments;
            }
            if (std.mem.indexOf(u8, default, "uuid_generate") != null or
                std.mem.indexOf(u8, default, "gen_random_uuid") != null)
            {
                return .uuid;
            }
            if (std.mem.eql(u8, default, "CURRENT_TIMESTAMP") or
                std.mem.eql(u8, default, "now()") or
                std.mem.indexOf(u8, default, "CURRENT_TIMESTAMP") != null)
            {
                return .timestamp;
            }
        }

        return .none;
    }
};

/// Represents a primary key constraint
pub const IntrospectedPrimaryKey = struct {
    constraint_name: []const u8,
    columns: std.ArrayList([]const u8),

    pub fn deinit(self: *IntrospectedPrimaryKey, allocator: std.mem.Allocator) void {
        for (self.columns.items) |col| {
            allocator.free(col);
        }
        self.columns.deinit(allocator);
        allocator.free(self.constraint_name);
    }
};

/// Represents a foreign key constraint
pub const IntrospectedForeignKey = struct {
    constraint_name: []const u8,
    column_name: []const u8,
    foreign_table_schema: []const u8,
    foreign_table_name: []const u8,
    foreign_column_name: []const u8,
    on_delete: []const u8,
    on_update: []const u8,

    pub fn toOnDeleteAction(self: IntrospectedForeignKey) schema.OnDeleteAction {
        return mapActionString(self.on_delete);
    }

    pub fn toOnUpdateAction(self: IntrospectedForeignKey) schema.OnUpdateAction {
        return mapActionStringUpdate(self.on_update);
    }

    pub fn deinit(self: *IntrospectedForeignKey, allocator: std.mem.Allocator) void {
        allocator.free(self.constraint_name);
        allocator.free(self.column_name);
        allocator.free(self.foreign_table_schema);
        allocator.free(self.foreign_table_name);
        allocator.free(self.foreign_column_name);
        allocator.free(self.on_delete);
        allocator.free(self.on_update);
    }
};

/// Represents a unique constraint
pub const IntrospectedUnique = struct {
    constraint_name: []const u8,
    columns: std.ArrayList([]const u8),

    pub fn deinit(self: *IntrospectedUnique, allocator: std.mem.Allocator) void {
        for (self.columns.items) |col| {
            allocator.free(col);
        }
        self.columns.deinit(allocator);
        allocator.free(self.constraint_name);
    }
};

/// Represents an index
pub const IntrospectedIndex = struct {
    index_name: []const u8,
    columns: std.ArrayList([]const u8),
    is_unique: bool,
    is_primary: bool,
    index_type: []const u8, // btree, hash, gist, etc.

    pub fn deinit(self: *IntrospectedIndex, allocator: std.mem.Allocator) void {
        for (self.columns.items) |col| {
            allocator.free(col);
        }
        self.columns.deinit(allocator);
        allocator.free(self.index_name);
        allocator.free(self.index_type);
    }
};

/// Represents a complete table schema from introspection
pub const IntrospectedTable = struct {
    table_name: []const u8,
    table_schema: []const u8,
    columns: std.ArrayList(IntrospectedColumn),
    primary_key: ?IntrospectedPrimaryKey,
    foreign_keys: std.ArrayList(IntrospectedForeignKey),
    unique_constraints: std.ArrayList(IntrospectedUnique),
    indexes: std.ArrayList(IntrospectedIndex),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, table_name: []const u8, table_schema_name: []const u8) !IntrospectedTable {
        return IntrospectedTable{
            .table_name = try allocator.dupe(u8, table_name),
            .table_schema = try allocator.dupe(u8, table_schema_name),
            .columns = std.ArrayList(IntrospectedColumn){},
            .primary_key = null,
            .foreign_keys = std.ArrayList(IntrospectedForeignKey){},
            .unique_constraints = std.ArrayList(IntrospectedUnique){},
            .indexes = std.ArrayList(IntrospectedIndex){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *IntrospectedTable) void {
        // Free columns
        for (self.columns.items) |col| {
            self.allocator.free(col.name);
            self.allocator.free(col.data_type);
            self.allocator.free(col.udt_name);
            if (col.column_default) |def| self.allocator.free(def);
            if (col.identity_generation) |gen| self.allocator.free(gen);
        }
        self.columns.deinit(self.allocator);

        // Free primary key
        if (self.primary_key) |*pk| {
            pk.deinit(self.allocator);
        }

        // Free foreign keys
        for (self.foreign_keys.items) |*fk| {
            fk.deinit(self.allocator);
        }
        self.foreign_keys.deinit(self.allocator);

        // Free unique constraints
        for (self.unique_constraints.items) |*uc| {
            uc.deinit(self.allocator);
        }
        self.unique_constraints.deinit(self.allocator);

        // Free indexes
        for (self.indexes.items) |*idx| {
            idx.deinit(self.allocator);
        }
        self.indexes.deinit(self.allocator);

        self.allocator.free(self.table_name);
        self.allocator.free(self.table_schema);
    }

    /// Check if a column is part of the primary key
    pub fn isPrimaryKeyColumn(self: *const IntrospectedTable, column_name: []const u8) bool {
        if (self.primary_key) |pk| {
            for (pk.columns.items) |pk_col| {
                if (std.mem.eql(u8, pk_col, column_name)) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Check if a column has a unique constraint (single-column)
    pub fn isUniqueColumn(self: *const IntrospectedTable, column_name: []const u8) bool {
        for (self.unique_constraints.items) |uc| {
            if (uc.columns.items.len == 1 and std.mem.eql(u8, uc.columns.items[0], column_name)) {
                return true;
            }
        }
        // Also check unique indexes
        for (self.indexes.items) |idx| {
            if (idx.is_unique and !idx.is_primary and idx.columns.items.len == 1) {
                if (std.mem.eql(u8, idx.columns.items[0], column_name)) {
                    return true;
                }
            }
        }
        return false;
    }
};

/// Complete database schema from introspection
pub const IntrospectedDatabase = struct {
    tables: std.ArrayList(IntrospectedTable),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) IntrospectedDatabase {
        return IntrospectedDatabase{
            .tables = std.ArrayList(IntrospectedTable){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *IntrospectedDatabase) void {
        for (self.tables.items) |*table| {
            table.deinit();
        }
        self.tables.deinit(self.allocator);
    }

    pub fn getTable(self: *const IntrospectedDatabase, table_name: []const u8) ?*const IntrospectedTable {
        for (self.tables.items) |*table| {
            if (std.mem.eql(u8, table.table_name, table_name)) {
                return table;
            }
        }
        return null;
    }
};

// Helper functions for type mapping

fn mapPgTypeToFieldType(udt_name: []const u8, data_type: []const u8) schema.FieldType {
    // Map PostgreSQL types to ORM FieldTypes
    if (std.mem.eql(u8, udt_name, "uuid")) return .uuid;
    if (std.mem.eql(u8, udt_name, "text")) return .text;
    if (std.mem.eql(u8, udt_name, "varchar") or std.mem.eql(u8, data_type, "character varying")) return .text;
    if (std.mem.eql(u8, udt_name, "char") or std.mem.eql(u8, data_type, "character")) return .text;
    if (std.mem.eql(u8, udt_name, "bool") or std.mem.eql(u8, udt_name, "boolean")) return .bool;
    if (std.mem.eql(u8, udt_name, "int2") or std.mem.eql(u8, udt_name, "smallint")) return .i16;
    if (std.mem.eql(u8, udt_name, "int4") or std.mem.eql(u8, udt_name, "integer") or std.mem.eql(u8, udt_name, "serial")) return .i32;
    if (std.mem.eql(u8, udt_name, "int8") or std.mem.eql(u8, udt_name, "bigint") or std.mem.eql(u8, udt_name, "bigserial")) return .i64;
    if (std.mem.eql(u8, udt_name, "float4") or std.mem.eql(u8, udt_name, "real")) return .f32;
    if (std.mem.eql(u8, udt_name, "float8") or std.mem.eql(u8, udt_name, "double precision")) return .f64;
    if (std.mem.eql(u8, udt_name, "numeric") or std.mem.eql(u8, udt_name, "decimal")) return .f64;
    if (std.mem.eql(u8, udt_name, "timestamp") or std.mem.eql(u8, udt_name, "timestamptz") or
        std.mem.indexOf(u8, data_type, "timestamp") != null) return .timestamp;
    if (std.mem.eql(u8, udt_name, "json")) return .json;
    if (std.mem.eql(u8, udt_name, "jsonb")) return .jsonb;
    if (std.mem.eql(u8, udt_name, "bytea")) return .binary;

    // Default to text for unknown types
    return .text;
}

fn toOptional(field_type: schema.FieldType) schema.FieldType {
    return switch (field_type) {
        .uuid => .uuid_optional,
        .text => .text_optional,
        .bool => .bool_optional,
        .i16 => .i16_optional,
        .i32 => .i32_optional,
        .i64 => .i64_optional,
        .f32 => .f32_optional,
        .f64 => .f64_optional,
        .timestamp => .timestamp_optional,
        .json => .json_optional,
        .jsonb => .jsonb_optional,
        .binary => .binary_optional,
        else => field_type, // Already optional
    };
}

fn mapActionString(action: []const u8) schema.OnDeleteAction {
    if (std.mem.eql(u8, action, "CASCADE") or std.mem.eql(u8, action, "c")) return .cascade;
    if (std.mem.eql(u8, action, "SET NULL") or std.mem.eql(u8, action, "n")) return .set_null;
    if (std.mem.eql(u8, action, "SET DEFAULT") or std.mem.eql(u8, action, "d")) return .set_default;
    if (std.mem.eql(u8, action, "RESTRICT") or std.mem.eql(u8, action, "r")) return .restrict;
    return .no_action;
}

fn mapActionStringUpdate(action: []const u8) schema.OnUpdateAction {
    if (std.mem.eql(u8, action, "CASCADE") or std.mem.eql(u8, action, "c")) return .cascade;
    if (std.mem.eql(u8, action, "SET NULL") or std.mem.eql(u8, action, "n")) return .set_null;
    if (std.mem.eql(u8, action, "SET DEFAULT") or std.mem.eql(u8, action, "d")) return .set_default;
    if (std.mem.eql(u8, action, "RESTRICT") or std.mem.eql(u8, action, "r")) return .restrict;
    return .no_action;
}
