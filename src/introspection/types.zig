// Database Introspection Types
// Represents the structure of database objects extracted from PostgreSQL system catalogs

const std = @import("std");
const types = @import("../types.zig");
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
    pub fn toFieldType(self: IntrospectedColumn) types.FieldType {
        const base_type = types.mapPgTypeToFieldType(self.udt_name, self.data_type);
        if (self.is_nullable) {
            return base_type.toOptional();
        }
        return base_type;
    }

    /// Determine auto-generation type based on column properties
    pub fn getAutoGenerateType(self: IntrospectedColumn) types.AutoGenerateType {
        return types.determineAutoGenerateType(self.column_default, self.is_identity, self.identity_generation);
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

    pub fn toOnDeleteAction(self: IntrospectedForeignKey) types.ReferentialAction {
        return types.ReferentialAction.fromSql(self.on_delete);
    }

    pub fn toOnUpdateAction(self: IntrospectedForeignKey) types.ReferentialAction {
        return types.ReferentialAction.fromSql(self.on_update);
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
