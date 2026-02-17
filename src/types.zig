// Centralized type definitions and mappings for FluentORM
// Consolidates type conversion logic from schema.zig, sql_generator.zig, and introspection/types.zig

const std = @import("std");

/// PostgreSQL to Zig type mapping information
pub const TypeInfo = struct {
    zig_type: []const u8,
    pg_type: []const u8,
    is_optional: bool,
    field_method: []const u8, // Method name for schema builder
};

/// All field types supported by the ORM
pub const FieldType = enum {
    uuid,
    uuid_optional,
    text,
    text_optional,
    bool,
    bool_optional,
    i16,
    i16_optional,
    i32,
    i32_optional,
    i64,
    i64_optional,
    f32,
    f32_optional,
    f64,
    f64_optional,
    timestamp,
    timestamp_optional,
    json,
    json_optional,
    jsonb,
    jsonb_optional,
    binary,
    binary_optional,

    /// Get the Zig type string for this field type
    pub fn toZigType(self: FieldType) []const u8 {
        return type_info_table[@intFromEnum(self)].zig_type;
    }

    /// Get the PostgreSQL type string for this field type
    pub fn toPgType(self: FieldType) []const u8 {
        return type_info_table[@intFromEnum(self)].pg_type;
    }

    /// Check if this field type is optional
    pub fn isOptional(self: FieldType) bool {
        return type_info_table[@intFromEnum(self)].is_optional;
    }

    /// Get the schema builder method name for this field type
    pub fn toFieldMethod(self: FieldType) []const u8 {
        return type_info_table[@intFromEnum(self)].field_method;
    }

    /// Convert to the optional version of this type
    pub fn toOptional(self: FieldType) FieldType {
        return switch (self) {
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
            else => self, // Already optional
        };
    }

    /// Convert from optional to non-optional version
    pub fn toNonOptional(self: FieldType) FieldType {
        return switch (self) {
            .uuid_optional => .uuid,
            .text_optional => .text,
            .bool_optional => .bool,
            .i16_optional => .i16,
            .i32_optional => .i32,
            .i64_optional => .i64,
            .f32_optional => .f32,
            .f64_optional => .f64,
            .timestamp_optional => .timestamp,
            .json_optional => .json,
            .jsonb_optional => .jsonb,
            .binary_optional => .binary,
            else => self, // Already non-optional
        };
    }

    /// Check if this is a numeric type
    pub fn isNumeric(self: FieldType) bool {
        return switch (self) {
            .i16, .i16_optional, .i32, .i32_optional, .i64, .i64_optional, .f32, .f32_optional, .f64, .f64_optional => true,
            else => false,
        };
    }

    /// Check if this is a text-based type
    pub fn isText(self: FieldType) bool {
        return switch (self) {
            .text, .text_optional, .json, .json_optional, .jsonb, .jsonb_optional, .uuid, .uuid_optional, .binary, .binary_optional => true,
            else => false,
        };
    }

    /// Check if this type should quote default values
    pub fn shouldQuoteDefault(self: FieldType, default_value: []const u8) bool {
        if (self.isNumeric()) return false;
        if (std.mem.eql(u8, default_value, "true") or std.mem.eql(u8, default_value, "false")) return false;
        if (std.mem.eql(u8, default_value, "CURRENT_TIMESTAMP") or
            std.mem.eql(u8, default_value, "now()") or
            std.mem.indexOf(u8, default_value, "uuid") != null) return false;
        return true;
    }
};

/// Comptime lookup table for all field type mappings
pub const type_info_table: [@typeInfo(FieldType).Enum.fields.len]TypeInfo = blk: {
    var table: [@typeInfo(FieldType).Enum.fields.len]TypeInfo = undefined;

    // UUID types
    table[@intFromEnum(FieldType.uuid)] = .{ .zig_type = "[]const u8", .pg_type = "UUID", .is_optional = false, .field_method = "uuid" };
    table[@intFromEnum(FieldType.uuid_optional)] = .{ .zig_type = "?[]const u8", .pg_type = "UUID", .is_optional = true, .field_method = "uuid.optional()" };

    // Text types
    table[@intFromEnum(FieldType.text)] = .{ .zig_type = "[]const u8", .pg_type = "TEXT", .is_optional = false, .field_method = "string" };
    table[@intFromEnum(FieldType.text_optional)] = .{ .zig_type = "?[]const u8", .pg_type = "TEXT", .is_optional = true, .field_method = "string.optional()" };

    // Boolean types
    table[@intFromEnum(FieldType.bool)] = .{ .zig_type = "bool", .pg_type = "BOOLEAN", .is_optional = false, .field_method = "boolean" };
    table[@intFromEnum(FieldType.bool_optional)] = .{ .zig_type = "?bool", .pg_type = "BOOLEAN", .is_optional = true, .field_method = "boolean.optional()" };

    // Integer types
    table[@intFromEnum(FieldType.i16)] = .{ .zig_type = "i16", .pg_type = "SMALLINT", .is_optional = false, .field_method = "smallInt" };
    table[@intFromEnum(FieldType.i16_optional)] = .{ .zig_type = "?i16", .pg_type = "SMALLINT", .is_optional = true, .field_method = "smallInt.optional()" };
    table[@intFromEnum(FieldType.i32)] = .{ .zig_type = "i32", .pg_type = "INT", .is_optional = false, .field_method = "integer" };
    table[@intFromEnum(FieldType.i32_optional)] = .{ .zig_type = "?i32", .pg_type = "INT", .is_optional = true, .field_method = "integer.optional()" };
    table[@intFromEnum(FieldType.i64)] = .{ .zig_type = "i64", .pg_type = "BIGINT", .is_optional = false, .field_method = "bigInt" };
    table[@intFromEnum(FieldType.i64_optional)] = .{ .zig_type = "?i64", .pg_type = "BIGINT", .is_optional = true, .field_method = "bigInt.optional()" };

    // Float types
    table[@intFromEnum(FieldType.f32)] = .{ .zig_type = "f32", .pg_type = "float4", .is_optional = false, .field_method = "float" };
    table[@intFromEnum(FieldType.f32_optional)] = .{ .zig_type = "?f32", .pg_type = "float4", .is_optional = true, .field_method = "float.optional()" };
    table[@intFromEnum(FieldType.f64)] = .{ .zig_type = "f64", .pg_type = "numeric", .is_optional = false, .field_method = "decimal" };
    table[@intFromEnum(FieldType.f64_optional)] = .{ .zig_type = "?f64", .pg_type = "numeric", .is_optional = true, .field_method = "decimal.optional()" };

    // Timestamp types
    table[@intFromEnum(FieldType.timestamp)] = .{ .zig_type = "i64", .pg_type = "TIMESTAMP", .is_optional = false, .field_method = "timestamp" };
    table[@intFromEnum(FieldType.timestamp_optional)] = .{ .zig_type = "?i64", .pg_type = "TIMESTAMP", .is_optional = true, .field_method = "timestamp.optional()" };

    // JSON types
    table[@intFromEnum(FieldType.json)] = .{ .zig_type = "[]const u8", .pg_type = "JSON", .is_optional = false, .field_method = "json" };
    table[@intFromEnum(FieldType.json_optional)] = .{ .zig_type = "?[]const u8", .pg_type = "JSON", .is_optional = true, .field_method = "json.optional()" };
    table[@intFromEnum(FieldType.jsonb)] = .{ .zig_type = "[]const u8", .pg_type = "JSONB", .is_optional = false, .field_method = "jsonb" };
    table[@intFromEnum(FieldType.jsonb_optional)] = .{ .zig_type = "?[]const u8", .pg_type = "JSONB", .is_optional = true, .field_method = "jsonb.optional()" };

    // Binary types
    table[@intFromEnum(FieldType.binary)] = .{ .zig_type = "[]const u8", .pg_type = "bytea", .is_optional = false, .field_method = "binary" };
    table[@intFromEnum(FieldType.binary_optional)] = .{ .zig_type = "?[]const u8", .pg_type = "bytea", .is_optional = true, .field_method = "binary.optional()" };

    break :blk table;
};

/// Auto-generation types for fields
pub const AutoGenerateType = enum {
    none,
    uuid,
    timestamp,
    increments,

    /// Convert to SQL generation string
    pub fn toSql(self: AutoGenerateType) []const u8 {
        return switch (self) {
            .none => "",
            .uuid => "DEFAULT gen_random_uuid()",
            .timestamp => "DEFAULT CURRENT_TIMESTAMP",
            .increments => "GENERATED ALWAYS AS IDENTITY",
        };
    }
};

/// Referential actions for foreign keys (unified OnDeleteAction and OnUpdateAction)
pub const ReferentialAction = enum {
    cascade,
    set_null,
    set_default,
    restrict,
    no_action,

    /// Convert to SQL string
    pub fn toSql(self: ReferentialAction) []const u8 {
        return switch (self) {
            .cascade => "CASCADE",
            .set_null => "SET NULL",
            .set_default => "SET DEFAULT",
            .restrict => "RESTRICT",
            .no_action => "NO ACTION",
        };
    }

    /// Parse from SQL string
    pub fn fromSql(action: []const u8) ReferentialAction {
        if (std.mem.eql(u8, action, "CASCADE") or std.mem.eql(u8, action, "c")) return .cascade;
        if (std.mem.eql(u8, action, "SET NULL") or std.mem.eql(u8, action, "n")) return .set_null;
        if (std.mem.eql(u8, action, "SET DEFAULT") or std.mem.eql(u8, action, "d")) return .set_default;
        if (std.mem.eql(u8, action, "RESTRICT") or std.mem.eql(u8, action, "r")) return .restrict;
        return .no_action;
    }
};

// Legacy aliases for backward compatibility
pub const OnDeleteAction = ReferentialAction;
pub const OnUpdateAction = ReferentialAction;

/// Map PostgreSQL type name to FieldType (for introspection)
pub fn mapPgTypeToFieldType(udt_name: []const u8, data_type: []const u8) FieldType {
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

/// Map FieldType enum tag name string to FieldType
pub fn fieldTypeFromString(type_str: []const u8) FieldType {
    if (std.mem.eql(u8, type_str, "uuid")) return .uuid;
    if (std.mem.eql(u8, type_str, "uuid_optional")) return .uuid_optional;
    if (std.mem.eql(u8, type_str, "text")) return .text;
    if (std.mem.eql(u8, type_str, "text_optional")) return .text_optional;
    if (std.mem.eql(u8, type_str, "bool")) return .bool;
    if (std.mem.eql(u8, type_str, "bool_optional")) return .bool_optional;
    if (std.mem.eql(u8, type_str, "i16")) return .i16;
    if (std.mem.eql(u8, type_str, "i16_optional")) return .i16_optional;
    if (std.mem.eql(u8, type_str, "i32")) return .i32;
    if (std.mem.eql(u8, type_str, "i32_optional")) return .i32_optional;
    if (std.mem.eql(u8, type_str, "i64")) return .i64;
    if (std.mem.eql(u8, type_str, "i64_optional")) return .i64_optional;
    if (std.mem.eql(u8, type_str, "f32")) return .f32;
    if (std.mem.eql(u8, type_str, "f32_optional")) return .f32_optional;
    if (std.mem.eql(u8, type_str, "f64")) return .f64;
    if (std.mem.eql(u8, type_str, "f64_optional")) return .f64_optional;
    if (std.mem.eql(u8, type_str, "timestamp")) return .timestamp;
    if (std.mem.eql(u8, type_str, "timestamp_optional")) return .timestamp_optional;
    if (std.mem.eql(u8, type_str, "json")) return .json;
    if (std.mem.eql(u8, type_str, "json_optional")) return .json_optional;
    if (std.mem.eql(u8, type_str, "jsonb")) return .jsonb;
    if (std.mem.eql(u8, type_str, "jsonb_optional")) return .jsonb_optional;
    if (std.mem.eql(u8, type_str, "binary")) return .binary;
    if (std.mem.eql(u8, type_str, "binary_optional")) return .binary_optional;
    return .text; // fallback
}

/// Determine auto-generation type from column default patterns
pub fn determineAutoGenerateType(column_default: ?[]const u8, is_identity: bool, _identity_generation: ?[]const u8) AutoGenerateType {
    _ = _identity_generation; // autofix
    if (is_identity) {
        return .increments;
    }

    if (column_default) |default| {
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

/// Type for schema field definition
pub const Field = struct {
    name: []const u8,
    field_type: FieldType,
    primary_key: bool,
    nullable: bool,
    unique: bool,
    default_value: ?[]const u8,
    references_table: ?[]const u8,
    references_column: ?[]const u8,
    auto_generated: bool,
    auto_generate_type: AutoGenerateType,
    redacted: bool,
    index: bool,
};

/// Relationship types for model associations
pub const RelationshipType = enum {
    one_to_one,
    one_to_many,
    many_to_one,
    many_to_many,
};

/// Relationship definition for schema
pub const Relationship = struct {
    name: []const u8,
    column: []const u8,
    references_table: []const u8,
    references_column: []const u8,
    relationship_type: RelationshipType = .many_to_one,
    on_delete: ReferentialAction = .no_action,
    on_update: ReferentialAction = .no_action,
    through_table: ?[]const u8 = null, // For many-to-many
    through_column: ?[]const u8 = null,
    through_references_column: ?[]const u8 = null,
};

/// Index definition for schema
pub const Index = struct {
    name: []const u8,
    columns: [][]const u8,
    unique: bool,
    method: []const u8,
};
