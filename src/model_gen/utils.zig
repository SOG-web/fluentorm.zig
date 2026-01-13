const std = @import("std");

const Relationship = @import("../schema.zig").Relationship;
const FieldType = @import("../schema.zig").FieldType;
const Field = @import("../schema.zig").Field;
const TableSchema = @import("../table.zig").TableSchema;

pub fn singularize(table_name: []const u8) []const u8 {
    // Simple singularization: remove trailing 's' if present
    // This handles: posts -> post, comments -> comment, profiles -> profile
    // Note: doesn't handle complex cases like "categories" -> "category"
    if (table_name.len > 1 and table_name[table_name.len - 1] == 's') {
        return table_name[0 .. table_name.len - 1];
    }
    return table_name;
}

pub fn tableToPascalCase(allocator: std.mem.Allocator, table_name: []const u8) ![]const u8 {
    //  Singularize first (posts -> post, comments -> comment)
    const singular = singularize(table_name);

    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    var capitalize_next = true;
    for (singular) |c| {
        if (c == '_') {
            capitalize_next = true;
        } else if (capitalize_next) {
            try result.append(allocator, std.ascii.toUpper(c));
            capitalize_next = false;
        } else {
            try result.append(allocator, c);
        }
    }

    return result.toOwnedSlice(allocator);
}

pub fn toLowerSnakeCase(allocator: std.mem.Allocator, camel: []const u8) ![]const u8 {
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    for (camel, 0..) |c, i| {
        if (std.ascii.isUpper(c)) {
            if (i > 0) {
                try result.append(allocator, '_');
            }
            try result.append(allocator, std.ascii.toLower(c));
        } else {
            try result.append(allocator, c);
        }
    }

    return result.toOwnedSlice(allocator);
}

pub fn toPascalCaseNonSingular(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    // Convert to PascalCase WITHOUT singularizing
    // e.g., "comments" -> "Comments" (not "Comment")
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    var capitalize_next = true;
    for (name) |c| {
        if (c == '_') {
            capitalize_next = true;
        } else if (capitalize_next) {
            try result.append(allocator, std.ascii.toUpper(c));
            capitalize_next = false;
        } else {
            try result.append(allocator, c);
        }
    }

    return result.toOwnedSlice(allocator);
}

pub fn columnToMethodName(allocator: std.mem.Allocator, column_name: []const u8, table_name: []const u8, is_plural: bool) ![]const u8 {
    // Convert organization_id -> Organization
    // Convert user_id -> User
    // For one-to-many: use table name directly keeping plurality (e.g., "comments" -> "Comments")
    // Strip _id suffix and convert to PascalCase

    // If column is just "id", use the table name (don't singularize for one-to-many)
    if (std.mem.eql(u8, column_name, "id")) {
        if (is_plural) {
            // Keep plural for one-to-many: "comments" -> "Comments"
            return toPascalCaseNonSingular(allocator, table_name);
        } else {
            // Singularize for one-to-one reverse: "profiles" -> "Profile"
            return tableToPascalCase(allocator, table_name);
        }
    }

    var name_without_id = column_name;
    if (std.mem.endsWith(u8, column_name, "_id")) {
        name_without_id = column_name[0 .. column_name.len - 3];
    }

    return tableToPascalCase(allocator, name_without_id);
}

pub fn relationshipToFieldName(allocator: std.mem.Allocator, rel: Relationship) ![]const u8 {
    // Convert organization_id -> organization (snake_case, strip _id)
    // Convert user_id -> user
    // For one_to_many: use references_table directly (e.g., "comments")
    // For reverse relationships (column="id"): use references_table

    switch (rel.relationship_type) {
        .one_to_many, .many_to_many => {
            // For one_to_many, use the referenced table name as-is (already plural)
            // e.g., references "comments" table -> field "comments"
            return allocator.dupe(u8, rel.references_table);
        },
        .one_to_one => {
            // If column is "id", this is a reverse relationship - use table name
            if (std.mem.eql(u8, rel.column, "id")) {
                // Remove plural 's' for one-to-one if present
                if (std.mem.endsWith(u8, rel.references_table, "s")) {
                    return allocator.dupe(u8, rel.references_table[0 .. rel.references_table.len - 1]);
                }
                return allocator.dupe(u8, rel.references_table);
            }
            // Forward relationship - use column name without _id
            var name_without_id = rel.column;
            if (std.mem.endsWith(u8, rel.column, "_id")) {
                name_without_id = rel.column[0 .. rel.column.len - 3];
            }
            return allocator.dupe(u8, name_without_id);
        },
        .many_to_one => {
            // For many_to_one, use column name without _id suffix
            var name_without_id = rel.column;
            if (std.mem.endsWith(u8, rel.column, "_id")) {
                name_without_id = rel.column[0 .. rel.column.len - 3];
            }
            return allocator.dupe(u8, name_without_id);
        },
    }
}

pub fn typeIsnumeric(field_type: FieldType) bool {
    return switch (field_type) {
        .i16, .i16_optional, .i32, .i32_optional, .i64, .i64_optional, .f32, .f32_optional, .f64, .f64_optional => true,
        else => false,
    };
}

pub fn getFinalFields(allocator: std.mem.Allocator, schema: TableSchema) ![]Field {
    var fields = std.ArrayList(Field){};
    defer fields.deinit(allocator);
    try fields.appendSlice(allocator, schema.fields.items);

    for (schema.alters.items) |alter| {
        for (fields.items) |*f| {
            if (std.mem.eql(u8, f.name, alter.name)) {
                f.* = alter;
                break;
            }
        }
    }

    return fields.toOwnedSlice(allocator);
}

pub fn hasManyMethodName(allocator: std.mem.Allocator, rel_name: []const u8) ![]const u8 {
    // Convert "user_posts" -> "Posts", "user_comments" -> "Comments"
    // Takes the last part after underscore and converts to PascalCase
    // If no underscore, just capitalize first letter

    // Find the last underscore
    var last_underscore: ?usize = null;
    for (rel_name, 0..) |c, i| {
        if (c == '_') {
            last_underscore = i;
        }
    }

    const name_part = if (last_underscore) |idx|
        rel_name[idx + 1 ..]
    else
        rel_name;

    // Convert to PascalCase (capitalize first letter, keep the rest including plural 's')
    return toPascalCaseNonSingular(allocator, name_part);
}
