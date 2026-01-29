// Schema Converter
// Converts introspected database schema to ORM TableSchema definitions

const std = @import("std");

const types = @import("types.zig");
const schema = @import("../schema.zig");
const TableSchema = @import("../table.zig");

/// Options for schema conversion
pub const ConversionOptions = struct {
    /// Generate timestamps fields (created_at, updated_at) with auto-generation hints
    detect_timestamps: bool = true,
    /// Infer input modes based on column properties
    infer_input_modes: bool = true,
    /// Mark password/secret fields as redacted
    detect_redacted_fields: bool = true,
    /// Field names that should be marked as redacted
    redacted_patterns: []const []const u8 = &.{
        "password",
        "password_hash",
        "secret",
        "token",
        "api_key",
        "private_key",
    },
};

/// Convert an introspected database to TableSchema definitions
pub fn convertDatabase(
    allocator: std.mem.Allocator,
    db: *const types.IntrospectedDatabase,
    options: ConversionOptions,
) ![]TableSchema {
    var schemas = std.ArrayList(TableSchema){};
    errdefer {
        for (schemas.items) |*s| {
            s.deinit();
        }
        schemas.deinit(allocator);
    }

    for (db.tables.items) |*table| {
        const table_schema = try convertTable(allocator, table, db, options);
        try schemas.append(allocator, table_schema);
    }

    return schemas.toOwnedSlice(allocator);
}

/// Convert a single introspected table to TableSchema
pub fn convertTable(
    allocator: std.mem.Allocator,
    table: *const types.IntrospectedTable,
    db: *const types.IntrospectedDatabase,
    options: ConversionOptions,
) !TableSchema {
    var table_schema = try TableSchema.createEmpty(table.table_name, allocator);
    errdefer table_schema.deinit();

    // Convert columns to fields
    for (table.columns.items) |col| {
        const field = try convertColumn(allocator, &col, table, options);
        try table_schema.fields.append(allocator, field);
    }

    // Convert indexes (excluding primary key indexes)
    for (table.indexes.items) |idx| {
        if (idx.is_primary) continue; // Skip primary key indexes

        // Allocate columns slice
        var columns = try allocator.alloc([]const u8, idx.columns.items.len);
        for (idx.columns.items, 0..) |col, i| {
            columns[i] = col;
        }

        try table_schema.indexes.append(allocator, .{
            .name = idx.index_name,
            .columns = columns,
            .unique = idx.is_unique,
        });
    }

    // Convert foreign keys to relationships
    for (table.foreign_keys.items) |fk| {
        const rel = schema.Relationship{
            .name = fk.constraint_name,
            .column = fk.column_name,
            .references_table = fk.foreign_table_name,
            .references_column = fk.foreign_column_name,
            .relationship_type = .many_to_one,
            .on_delete = fk.toOnDeleteAction(),
            .on_update = fk.toOnUpdateAction(),
        };
        try table_schema.relationships.append(allocator, rel);
    }

    // Infer has_many relationships from other tables' foreign keys
    for (db.tables.items) |*other_table| {
        if (std.mem.eql(u8, other_table.table_name, table.table_name)) continue;

        for (other_table.foreign_keys.items) |fk| {
            if (std.mem.eql(u8, fk.foreign_table_name, table.table_name)) {
                // This table is referenced by another table
                const rel_name = try std.fmt.allocPrint(allocator, "{s}_{s}", .{
                    table.table_name,
                    other_table.table_name,
                });

                try table_schema.has_many_relationships.append(allocator, .{
                    .name = rel_name,
                    .foreign_table = other_table.table_name,
                    .foreign_column = fk.column_name,
                    .local_column = fk.foreign_column_name,
                });
            }
        }
    }

    return table_schema;
}

/// Convert a single column to Field
fn convertColumn(
    allocator: std.mem.Allocator,
    col: *const types.IntrospectedColumn,
    table: *const types.IntrospectedTable,
    options: ConversionOptions,
) !schema.Field {
    _ = allocator;

    const is_pk = table.isPrimaryKeyColumn(col.name);
    const is_unique = table.isUniqueColumn(col.name);
    const auto_gen_type = col.getAutoGenerateType();
    const is_auto_generated = auto_gen_type != .none;

    // Determine input mode
    var create_input: schema.InputMode = .required;
    if (options.infer_input_modes) {
        if (is_auto_generated or is_pk) {
            create_input = .excluded;
        } else if (col.is_nullable or col.column_default != null) {
            create_input = .optional;
        }
    }

    // Determine if field is updatable
    const update_input = !is_pk and !is_auto_generated;

    // Check if field should be redacted
    var redacted = false;
    if (options.detect_redacted_fields) {
        for (options.redacted_patterns) |pattern| {
            if (std.mem.indexOf(u8, col.name, pattern) != null) {
                redacted = true;
                break;
            }
        }
    }

    return schema.Field{
        .name = col.name,
        .type = col.toFieldType(),
        .primary_key = is_pk,
        .unique = is_unique,
        .not_null = !col.is_nullable,
        .create_input = create_input,
        .update_input = update_input,
        .redacted = redacted,
        .default_value = col.column_default,
        .auto_generated = is_auto_generated,
        .auto_generate_type = auto_gen_type,
    };
}

/// Generate Zig schema definition code from introspected table
pub fn generateSchemaCode(
    allocator: std.mem.Allocator,
    table: *const types.IntrospectedTable,
    db: *const types.IntrospectedDatabase,
    options: ConversionOptions,
) ![]const u8 {
    var output = std.ArrayList(u8){};
    errdefer output.deinit(allocator);
    const writer = output.writer(allocator);

    // Header
    try writer.print(
        \\// Schema definition for table: {s}
        \\// Generated by db pull introspection
        \\
        \\const fluentzig = @import("fluentorm");
        \\const TableSchema = fluentzig.TableSchema;
        \\
        \\pub fn define(self: *TableSchema) void {{
        \\
    , .{table.table_name});

    // Generate field definitions
    for (table.columns.items) |col| {
        try generateFieldCode(writer, &col, table, options);
    }

    // Generate index definitions (non-primary)
    var has_indexes = false;
    for (table.indexes.items) |idx| {
        if (!idx.is_primary and !idx.is_unique) {
            has_indexes = true;
            break;
        }
    }

    if (has_indexes) {
        try writer.writeAll("\n    // Indexes\n");
        try writer.writeAll("    self.addIndexes(&.{\n");
        for (table.indexes.items) |idx| {
            if (idx.is_primary) continue;

            // Build columns array literal
            try writer.print("        .{{ .name = \"{s}\", .columns = &.{{", .{idx.index_name});
            for (idx.columns.items, 0..) |col_name, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("\"{s}\"", .{col_name});
            }
            try writer.print("}}, .unique = {s} }},\n", .{if (idx.is_unique) "true" else "false"});
        }
        try writer.writeAll("    });\n");
    }

    // Generate relationship definitions
    if (table.foreign_keys.items.len > 0) {
        try writer.writeAll("\n    // Foreign Key Relationships\n");
        for (table.foreign_keys.items) |fk| {
            try writer.print(
                \\    self.belongsTo(.{{
                \\        .name = "{s}",
                \\        .column = "{s}",
                \\        .references_table = "{s}",
                \\        .references_column = "{s}",
                \\        .on_delete = .{s},
                \\        .on_update = .{s},
                \\    }});
                \\
            , .{
                fk.constraint_name,
                fk.column_name,
                fk.foreign_table_name,
                fk.foreign_column_name,
                @tagName(fk.toOnDeleteAction()),
                @tagName(fk.toOnUpdateAction()),
            });
        }
    }

    // Generate has_many relationships (inferred)
    var has_many_count: usize = 0;
    for (db.tables.items) |*other_table| {
        if (std.mem.eql(u8, other_table.table_name, table.table_name)) continue;
        for (other_table.foreign_keys.items) |fk| {
            if (std.mem.eql(u8, fk.foreign_table_name, table.table_name)) {
                has_many_count += 1;
            }
        }
    }

    if (has_many_count > 0) {
        try writer.writeAll("\n    // Has Many Relationships (inferred from foreign keys)\n");
        for (db.tables.items) |*other_table| {
            if (std.mem.eql(u8, other_table.table_name, table.table_name)) continue;
            for (other_table.foreign_keys.items) |fk| {
                if (std.mem.eql(u8, fk.foreign_table_name, table.table_name)) {
                    try writer.print(
                        \\    self.hasMany(.{{
                        \\        .name = "{s}_{s}",
                        \\        .foreign_table = "{s}",
                        \\        .foreign_column = "{s}",
                        \\        .local_column = "{s}",
                        \\    }});
                        \\
                    , .{
                        table.table_name,
                        other_table.table_name,
                        other_table.table_name,
                        fk.column_name,
                        fk.foreign_column_name,
                    });
                }
            }
        }
    }

    try writer.writeAll("}\n");

    return output.toOwnedSlice(allocator);
}

fn generateFieldCode(
    writer: anytype,
    col: *const types.IntrospectedColumn,
    table: *const types.IntrospectedTable,
    options: ConversionOptions,
) !void {
    const is_pk = table.isPrimaryKeyColumn(col.name);
    const is_unique = table.isUniqueColumn(col.name);
    const auto_gen_type = col.getAutoGenerateType();

    // Determine field method based on type and auto-generation
    const method_name = getFieldMethodName(col, auto_gen_type);

    try writer.print("    self.{s}(.{{\n", .{method_name});
    try writer.print("        .name = \"{s}\",\n", .{col.name});

    // Add constraints
    if (is_pk) {
        try writer.writeAll("        .primary_key = true,\n");
    }
    if (is_unique and !is_pk) {
        try writer.writeAll("        .unique = true,\n");
    }
    if (col.is_nullable) {
        try writer.writeAll("        .nullable = true,\n");
    }

    // Add default value if present and not auto-generated
    if (col.column_default != null and auto_gen_type == .none) {
        try writer.print("        .default_value = \"{s}\",\n", .{col.column_default.?});
    }

    // Check for redacted fields
    if (options.detect_redacted_fields) {
        for (options.redacted_patterns) |pattern| {
            if (std.mem.indexOf(u8, col.name, pattern) != null) {
                try writer.writeAll("        .redacted = true,\n");
                break;
            }
        }
    }

    try writer.writeAll("    });\n");
}

fn getFieldMethodName(col: *const types.IntrospectedColumn, auto_gen_type: schema.AutoGenerateType) []const u8 {
    // Handle auto-generated types
    if (auto_gen_type == .uuid) {
        return "uuidPrimaryKey";
    }
    if (auto_gen_type == .increments) {
        if (std.mem.eql(u8, col.udt_name, "int8") or std.mem.eql(u8, col.udt_name, "bigint")) {
            return "bigIncrements";
        }
        return "increments";
    }
    if (auto_gen_type == .timestamp) {
        return "timestamp";
    }

    // Map by PostgreSQL type
    if (std.mem.eql(u8, col.udt_name, "uuid")) return "uuid";
    if (std.mem.eql(u8, col.udt_name, "text")) return "string";
    if (std.mem.eql(u8, col.udt_name, "varchar")) return "string";
    if (std.mem.eql(u8, col.udt_name, "bool") or std.mem.eql(u8, col.udt_name, "boolean")) return "boolean";
    if (std.mem.eql(u8, col.udt_name, "int2") or std.mem.eql(u8, col.udt_name, "smallint")) return "smallInt";
    if (std.mem.eql(u8, col.udt_name, "int4") or std.mem.eql(u8, col.udt_name, "integer")) return "integer";
    if (std.mem.eql(u8, col.udt_name, "int8") or std.mem.eql(u8, col.udt_name, "bigint")) return "bigInt";
    if (std.mem.eql(u8, col.udt_name, "float4") or std.mem.eql(u8, col.udt_name, "real")) return "float";
    if (std.mem.eql(u8, col.udt_name, "float8") or std.mem.eql(u8, col.udt_name, "numeric")) return "decimal";
    if (std.mem.eql(u8, col.udt_name, "timestamp") or std.mem.eql(u8, col.udt_name, "timestamptz")) return "timestamp";
    if (std.mem.eql(u8, col.udt_name, "json")) return "json";
    if (std.mem.eql(u8, col.udt_name, "jsonb")) return "jsonb";
    if (std.mem.eql(u8, col.udt_name, "bytea")) return "binary";

    // Default to string for unknown types
    return "string";
}
