// Schema definition types for the model generator
// Re-exports centralized types and provides schema-specific extensions

const std = @import("std");
const types = @import("types.zig");

// Re-export all centralized types for backward compatibility
pub const FieldType = types.FieldType;
pub const AutoGenerateType = types.AutoGenerateType;
pub const ReferentialAction = types.ReferentialAction;
pub const OnDeleteAction = types.OnDeleteAction;
pub const OnUpdateAction = types.OnUpdateAction;
pub const RelationshipType = types.RelationshipType;
pub const Relationship = types.Relationship;
pub const Field = types.Field;
pub const Index = types.Index;

// Legacy type aliases for full backward compatibility
pub const type_info_table = types.type_info_table;

/// Input mode for field creation
pub const InputMode = enum {
    required, // Must be in CreateInput
    optional, // Optional in CreateInput
    excluded, // Not in CreateInput (auto-generated)
};

/// Schema field with input mode extensions
pub const SchemaField = struct {
    name: []const u8,
    type: FieldType,

    // Constraints
    primary_key: bool = false,
    unique: bool = false,
    not_null: bool = true,

    // Generation hints
    create_input: InputMode = .required,
    /// If true, included in UpdateInput; if false, excluded.
    update_input: bool = true,

    // JSON response hints
    redacted: bool = false, // If true, field is excluded from toJsonResponseSafe()

    // SQL defaults
    default_value: ?[]const u8 = null,
    auto_generated: bool = false,
    auto_generate_type: AutoGenerateType = .none,

    /// Convert to base Field type
    pub fn toField(self: SchemaField) Field {
        return .{
            .name = self.name,
            .field_type = self.type,
            .primary_key = self.primary_key,
            .nullable = !self.not_null,
            .unique = self.unique,
            .default_value = self.default_value,
            .references_table = null,
            .references_column = null,
            .auto_generated = self.auto_generated,
            .auto_generate_type = self.auto_generate_type,
            .redacted = self.redacted,
            .index = false,
        };
    }
};

/// Schema alteration definition
pub const Alter = struct {
    name: []const u8,
    type: ?FieldType = null,

    // Constraints
    primary_key: ?bool = null,
    unique: ?bool = null,
    not_null: ?bool = null,

    // Generation hints
    create_input: ?InputMode = null,
    update_input: ?bool = null,

    // JSON response hints
    redacted: ?bool = null, // If true, field is excluded from toJsonResponseSafe()

    // SQL defaults
    default_value: ?[]const u8 = null,
    auto_generated: ?bool = null,
    auto_generate_type: ?AutoGenerateType = null,
};

/// Legacy Index definition for schema (kept for backward compatibility)
pub const SchemaIndex = struct {
    name: []const u8,
    columns: []const []const u8,
    unique: bool = false,
};

/// HasMany relationship definition for one-to-many relationships defined in the parent table.
/// This is metadata only - no SQL constraint is generated (the FK is in the child table).
/// Used to generate helper methods like `fetchUserPosts()` on the parent model.
pub const HasManyRelationship = struct {
    name: []const u8, // e.g., "user_posts"
    foreign_table: []const u8, // e.g., "posts"
    foreign_column: []const u8, // e.g., "user_id" (the FK column in foreign table)
    local_column: []const u8 = "id", // e.g., "id" (usually the PK of this table)
};

/// Complete schema definition for a table
pub const Schema = struct {
    table_name: []const u8,
    struct_name: []const u8,
    fields: []const SchemaField,
    indexes: []const SchemaIndex,
    relationships: []const Relationship,

    pub fn getCreateInputFields(self: Schema) []const SchemaField {
        var count: usize = 0;
        for (self.fields) |field| {
            if (field.create_input != .excluded) {
                count += 1;
            }
        }

        var result = std.heap.page_allocator.alloc(SchemaField, count) catch unreachable;
        var i: usize = 0;
        for (self.fields) |field| {
            if (field.create_input != .excluded) {
                result[i] = field;
                i += 1;
            }
        }
        return result;
    }

    pub fn getUpdateInputFields(self: Schema) []const SchemaField {
        var count: usize = 0;
        for (self.fields) |field| {
            if (field.update_input) {
                count += 1;
            }
        }

        var result = std.heap.page_allocator.alloc(SchemaField, count) catch unreachable;
        var i: usize = 0;
        for (self.fields) |field| {
            if (field.update_input) {
                result[i] = field;
                i += 1;
            }
        }
        return result;
    }
};
