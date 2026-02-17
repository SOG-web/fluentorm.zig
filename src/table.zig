const std = @import("std");

const schema = @import("schema.zig");
const Alter = schema.Alter;
const AutoGenerateType = schema.AutoGenerateType;
const Field = schema.Field;
const FieldType = schema.FieldType;
const HasManyRelationship = schema.HasManyRelationship;
const Index = schema.Index;
const InputMode = schema.InputMode;
const OnDeleteAction = schema.OnDeleteAction;
const OnUpdateAction = schema.OnUpdateAction;
const Relationship = schema.Relationship;

pub const FieldInput = struct {
    name: []const u8,

    // Constraints
    primary_key: bool = false,
    unique: bool = false,
    nullable: bool = false,

    // Generation hints
    create_input: ?InputMode = null,
    update_input: bool = true,

    // JSON response hints
    redacted: bool = false, // If true, field is excluded from toJsonResponseSafe()

    // SQL defaults
    default_value: ?[]const u8 = null,
    auto_generated: bool = false,
};

pub const TableSchema = @This();

name: []const u8,
fields: std.ArrayList(Field) = .{},
alters: std.ArrayList(Field) = .{},
indexes: std.ArrayList(Index) = .{},
drop_indexes: std.ArrayList([]const u8) = .{},
relationships: std.ArrayList(Relationship) = .{},
has_many_relationships: std.ArrayList(HasManyRelationship) = .{},
allocator: std.mem.Allocator,
err: ?anyerror = null,

pub fn create(name: []const u8, allocator: std.mem.Allocator, builder: *const fn (self: *TableSchema) void) !TableSchema {
    var self = TableSchema{
        .name = name,
        .allocator = allocator,
        .fields = std.ArrayList(Field){},
        .alters = std.ArrayList(Field){},
        .indexes = std.ArrayList(Index){},
        .relationships = std.ArrayList(Relationship){},
        .has_many_relationships = std.ArrayList(HasManyRelationship){},
    };

    builder(&self);

    if (self.err) |err| {
        self.deinit();
        return err;
    }

    return self;
}

/// Create an empty TableSchema without calling a builder function.
/// Useful for schema merging where multiple builders will be called.
pub fn createEmpty(name: []const u8, allocator: std.mem.Allocator) !TableSchema {
    return TableSchema{
        .name = name,
        .allocator = allocator,
        .fields = std.ArrayList(Field){},
        .alters = std.ArrayList(Field){},
        .indexes = std.ArrayList(Index){},
        .drop_indexes = std.ArrayList([]const u8){},
        .relationships = std.ArrayList(Relationship){},
        .has_many_relationships = std.ArrayList(HasManyRelationship){},
    };
}

pub fn deinit(self: *TableSchema) void {
    self.fields.deinit(self.allocator);
    self.alters.deinit(self.allocator);
    self.indexes.deinit(self.allocator);
    self.relationships.deinit(self.allocator);
    self.has_many_relationships.deinit(self.allocator);
}

pub fn getFieldByName(self: *TableSchema, field_name: []const u8) !*const Field {
    for (self.fields.items) |*f| {
        if (std.mem.eql(u8, f.name, field_name)) {
            return f;
        }
    }
    return error.FieldNotFound;
}

const IndT = struct {
    index: *Index,
    it: usize,
};

pub fn getIndexByName(self: *TableSchema, index_name: []const u8) !IndT {
    var it: usize = 0;
    for (self.indexes.items) |*i| {
        it += 1;
        if (std.mem.eql(u8, i.name, index_name)) {
            return .{ .index = i, .it = it };
        }
    }
    return error.IndexNotFound;
}

/// Generic field addition helper - eliminates code duplication across all type methods
fn addFieldInternal(self: *TableSchema, field: FieldInput, field_type: FieldType, auto_gen_type: AutoGenerateType, default_override: ?[]const u8) void {
    if (self.err != null) return;

    const actual_create_input = field.create_input orelse (if (field.nullable) InputMode.optional else InputMode.required);
    const final_default = default_override orelse field.default_value;

    self.fields.append(self.allocator, .{
        .name = field.name,
        .type = field_type,
        .primary_key = field.primary_key,
        .unique = field.unique,
        .not_null = !field.nullable,
        .create_input = actual_create_input,
        .update_input = field.update_input,
        .redacted = field.redacted,
        .default_value = final_default,
        .auto_generated = field.auto_generated or auto_gen_type != .none,
        .auto_generate_type = auto_gen_type,
    }) catch |err| {
        self.err = err;
    };
}

/// Add an auto-incrementing primary key field
fn addIncrementField(self: *TableSchema, field: FieldInput, field_type: FieldType) void {
    if (self.err != null) return;

    self.fields.append(self.allocator, .{
        .name = field.name,
        .type = field_type,
        .primary_key = field.primary_key,
        .unique = true,
        .not_null = true,
        .create_input = .optional,
        .update_input = false,
        .redacted = field.redacted,
        .default_value = null,
        .auto_generated = true,
        .auto_generate_type = .increments,
    }) catch |err| {
        self.err = err;
    };
}

// MARK: - Integer Types

pub fn bigInt(self: *TableSchema, field: FieldInput) void {
    const field_type: FieldType = if (field.nullable) .i64_optional else .i64;
    self.addFieldInternal(field, field_type, .none, null);
}

pub fn bigIncrements(self: *TableSchema, field: FieldInput) void {
    self.addIncrementField(field, .i64);
}

pub fn integer(self: *TableSchema, field: FieldInput) void {
    const field_type: FieldType = if (field.nullable) .i32_optional else .i32;
    self.addFieldInternal(field, field_type, .none, null);
}

pub fn increments(self: *TableSchema, field: FieldInput) void {
    self.addIncrementField(field, .i32);
}

// MARK: - Binary Type

pub fn binary(self: *TableSchema, field: FieldInput) void {
    const field_type: FieldType = if (field.nullable) .binary_optional else .binary;
    self.addFieldInternal(field, field_type, .none, null);
}

// MARK: - Boolean Type

pub fn boolean(self: *TableSchema, field: FieldInput) void {
    const field_type: FieldType = if (field.nullable) .bool_optional else .bool;
    self.addFieldInternal(field, field_type, .none, null);
}

// MARK: - Text Types

pub fn string(self: *TableSchema, field: FieldInput) void {
    const field_type: FieldType = if (field.nullable) .text_optional else .text;
    self.addFieldInternal(field, field_type, .none, null);
}

pub fn uuid(self: *TableSchema, field: FieldInput) void {
    const field_type: FieldType = if (field.nullable) .uuid_optional else .uuid;
    const default_value = field.default_value orelse "nil";
    self.addFieldInternal(field, field_type, .uuid, default_value);
}

// MARK: - Timestamp Types

pub fn dateTime(self: *TableSchema, field: FieldInput) void {
    const field_type: FieldType = if (field.nullable) .timestamp_optional else .timestamp;
    self.addFieldInternal(field, field_type, .timestamp, null);
}

/// Adds standard created_at and updated_at timestamp fields to the table schema.
pub fn timestamps(self: *TableSchema) void {
    if (self.err != null) return;

    const timestamp_fields = [_]Field{
        .{
            .name = "created_at",
            .type = .timestamp,
            .not_null = true,
            .create_input = .excluded,
            .update_input = false,
            .redacted = false,
            .default_value = "CURRENT_TIMESTAMP",
            .auto_generated = true,
            .auto_generate_type = .timestamp,
        },
        .{
            .name = "updated_at",
            .type = .timestamp,
            .not_null = true,
            .create_input = .excluded,
            .update_input = false,
            .redacted = false,
            .default_value = "CURRENT_TIMESTAMP",
            .auto_generated = true,
            .auto_generate_type = .timestamp,
        },
    };

    for (&timestamp_fields) |f| {
        self.fields.append(self.allocator, f) catch |err| {
            self.err = err;
            return;
        };
    }
}

pub fn softDelete(self: *TableSchema) void {
    if (self.err != null) return;
    self.fields.append(self.allocator, .{
        .name = "deleted_at",
        .type = .timestamp_optional,
        .not_null = false,
        .create_input = .excluded,
        .update_input = false,
        .redacted = false,
        .default_value = null,
        .auto_generated = false,
        .auto_generate_type = .timestamp,
    }) catch |err| {
        self.err = err;
    };
}

// MARK: - Float Types

pub fn float(self: *TableSchema, field: FieldInput) void {
    const field_type: FieldType = if (field.nullable) .f32_optional else .f32;
    self.addFieldInternal(field, field_type, .none, null);
}

pub fn numeric(self: *TableSchema, field: FieldInput) void {
    const field_type: FieldType = if (field.nullable) .f64_optional else .f64;
    self.addFieldInternal(field, field_type, .none, null);
}

// MARK: - JSON Types

pub fn json(self: *TableSchema, field: FieldInput) void {
    const field_type: FieldType = if (field.nullable) .json_optional else .json;
    self.addFieldInternal(field, field_type, .none, null);
}

pub fn jsonb(self: *TableSchema, field: FieldInput) void {
    const field_type: FieldType = if (field.nullable) .jsonb_optional else .jsonb;
    self.addFieldInternal(field, field_type, .none, null);
}

// MARK: - Relationships

pub fn foreign(self: *TableSchema, rel: Relationship) void {
    if (self.err != null) return;
    self.relationships.append(self.allocator, rel) catch |err| {
        self.err = err;
    };
}

pub fn foreigns(self: *TableSchema, rels: []const Relationship) void {
    if (self.err != null) return;
    self.relationships.appendSlice(self.allocator, rels) catch |err| {
        self.err = err;
    };
}

/// Define a belongs-to relationship (many-to-one).
/// This table has a foreign key column that references another table.
/// Example: Post belongs to User (posts.user_id -> users.id)
///
/// ```zig
/// t.belongsTo(.{
///     .name = "post_author",
///     .column = "user_id",
///     .references_table = "users",
///     .references_column = "id",
///     .on_delete = .cascade,
/// });
/// ```
pub fn belongsTo(self: *TableSchema, options: struct {
    name: []const u8,
    column: []const u8,
    references_table: []const u8,
    references_column: []const u8 = "id",
    on_delete: OnDeleteAction = .no_action,
    on_update: OnUpdateAction = .no_action,
}) void {
    self.foreign(.{
        .name = options.name,
        .column = options.column,
        .references_table = options.references_table,
        .references_column = options.references_column,
        .relationship_type = .many_to_one,
        .on_delete = options.on_delete,
        .on_update = options.on_update,
    });
}

/// Define a has-one relationship (one-to-one).
/// This table has a unique foreign key column that references another table.
/// Example: User has one Profile (users.profile_id -> profiles.id)
///
/// ```zig
/// t.hasOne(.{
///     .name = "user_profile",
///     .column = "profile_id",
///     .references_table = "profiles",
///     .references_column = "id",
///     .on_delete = .set_null,
/// });
/// ```
pub fn hasOne(self: *TableSchema, options: struct {
    name: []const u8,
    column: []const u8,
    references_table: []const u8,
    references_column: []const u8 = "id",
    on_delete: OnDeleteAction = .no_action,
    on_update: OnUpdateAction = .no_action,
}) void {
    self.foreign(.{
        .name = options.name,
        .column = options.column,
        .references_table = options.references_table,
        .references_column = options.references_column,
        .relationship_type = .one_to_one,
        .on_delete = options.on_delete,
        .on_update = options.on_update,
    });
}

/// Define a many-to-many relationship through a junction table.
/// This creates metadata for the relationship - the junction table must be defined separately.
/// Example: Users <-> Roles through user_roles junction table
///
/// ```zig
/// t.manyToMany(.{
///     .name = "user_roles",
///     .column = "user_id",           // FK column in junction table pointing to this table
///     .references_table = "user_roles", // The junction table
///     .references_column = "user_id",   // Column in junction that references this table
/// });
/// ```
pub fn manyToMany(self: *TableSchema, options: struct {
    name: []const u8,
    column: []const u8,
    references_table: []const u8,
    references_column: []const u8,
    on_delete: OnDeleteAction = .cascade,
    on_update: OnUpdateAction = .no_action,
}) void {
    self.foreign(.{
        .name = options.name,
        .column = options.column,
        .references_table = options.references_table,
        .references_column = options.references_column,
        .relationship_type = .many_to_many,
        .on_delete = options.on_delete,
        .on_update = options.on_update,
    });
}

/// Define a one-to-many relationship from this table (parent) to another table (child).
/// This is metadata only - no FK constraint is generated here (the FK lives in the child table).
/// This generates helper methods like `fetchUserPosts()` on this model.
///
/// Example in users.zig:
/// ```zig
/// t.hasMany(.{
///     .name = "user_posts",
///     .foreign_table = "posts",
///     .foreign_column = "user_id",
/// });
/// ```
pub fn hasMany(self: *TableSchema, rel: HasManyRelationship) void {
    if (self.err != null) return;
    self.has_many_relationships.append(self.allocator, rel) catch |err| {
        self.err = err;
    };
}

/// Define multiple one-to-many relationships at once.
pub fn hasManyList(self: *TableSchema, rels: []const HasManyRelationship) void {
    if (self.err != null) return;
    self.has_many_relationships.appendSlice(self.allocator, rels) catch |err| {
        self.err = err;
    };
}

// MARK: - Alter Operations

pub fn alterField(self: *TableSchema, field: Alter) void {
    if (self.err != null) return;
    if (self.fields.items.len == 0) {
        self.err = error.NoFields;
        return;
    }

    // check if field exists
    const exist = self.getFieldByName(field.name) catch |err| {
        self.err = err;
        return;
    };

    self.alters.append(self.allocator, .{
        .name = field.name,
        .type = if (field.type) |t| t else exist.type,
        .primary_key = if (field.primary_key) |pk| pk else exist.primary_key,
        .unique = if (field.unique) |u| u else exist.unique,
        .not_null = if (field.not_null) |nn| nn else exist.not_null,
        .create_input = if (field.create_input) |ci| ci else exist.create_input,
        .update_input = if (field.update_input) |ui| ui else exist.update_input,
        .redacted = if (field.redacted) |r| r else exist.redacted,
        .default_value = if (field.default_value) |dv| dv else exist.default_value,
        .auto_generated = if (field.auto_generated) |ag| ag else exist.auto_generated,
        .auto_generate_type = if (field.auto_generate_type) |agt| agt else exist.auto_generate_type,
    }) catch |err| {
        self.err = err;
    };
}

pub fn alterFields(self: *TableSchema, fields: []const Alter) void {
    if (self.err != null) return;
    if (self.fields.items.len == 0) {
        self.err = error.NoFields;
        return;
    }

    for (fields) |field| {
        self.alterField(field);
    }
}

// MARK: - Index Operations

pub fn addIndexes(self: *TableSchema, list: []const Index) void {
    if (self.err != null) return;
    self.indexes.appendSlice(self.allocator, list) catch |err| {
        self.err = err;
    };
}

pub fn dropIndex(self: *TableSchema, index_name: []const u8) void {
    if (self.err != null) return;
    self.drop_indexes.append(self.allocator, index_name) catch |err| {
        self.err = err;
        return;
    };
}

// MARK: - Tests

test "check" {
    const allocator = std.testing.allocator;

    var table = try TableSchema.create(
        "test",
        allocator,
        struct {
            fn build(t: *TableSchema) void {
                t.bigIncrements(.{ .name = "id" });
                t.string(.{ .name = "name" });
            }
        }.build,
    );
    defer table.deinit();
}

test "deferred error check" {
    const allocator = std.testing.allocator;

    const result = TableSchema.create(
        "test_error",
        allocator,
        struct {
            fn build(t: *TableSchema) void {
                // Create an error by trying to alter a field that doesn't exist
                t.alterField(.{ .name = "nonexistent" });
            }
        }.build,
    );

    try std.testing.expectError(error.FieldNotFound, result);
}
