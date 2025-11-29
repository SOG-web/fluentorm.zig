// JSON Schema Parser for Database Models
const std = @import("std");

const schema_mod = @import("schema");
const Schema = schema_mod.Schema;
const Field = schema_mod.Field;
const FieldType = schema_mod.FieldType;
const InputMode = schema_mod.InputMode;
const Index = schema_mod.Index;
const Relationship = schema_mod.Relationship;
const RelationshipType = schema_mod.RelationshipType;
const OnDeleteAction = schema_mod.OnDeleteAction;
const OnUpdateAction = schema_mod.OnUpdateAction;

pub const ParseError = error{
    InvalidJson,
    InvalidFieldType,
    InvalidInputMode,
    MissingRequiredField,
    InvalidStructure,
    InvalidBoolean,
} || std.mem.Allocator.Error || std.json.ParseError(std.json.Scanner);

/// Map JSON type string to FieldType enum, considering nullability
fn parseFieldType(type_str: []const u8, nullable: bool, field_name: []const u8) ParseError!FieldType {
    // Map base type + nullable to correct FieldType variant
    if (std.mem.eql(u8, type_str, "uuid")) {
        return FieldType.uuid;
    } else if (std.mem.eql(u8, type_str, "text")) {
        return if (nullable) FieldType.text_optional else FieldType.text;
    } else if (std.mem.eql(u8, type_str, "boolean")) {
        return FieldType.bool;
    } else if (std.mem.eql(u8, type_str, "i16")) {
        return FieldType.i16;
    } else if (std.mem.eql(u8, type_str, "i32")) {
        return FieldType.i32;
    } else if (std.mem.eql(u8, type_str, "i64")) {
        return if (nullable) FieldType.i64_optional else FieldType.i64;
    } else if (std.mem.eql(u8, type_str, "timestamp")) {
        return if (nullable) FieldType.timestamp_optional else FieldType.timestamp;
    } else if (std.mem.eql(u8, type_str, "json")) {
        return if (nullable) FieldType.json_optional else FieldType.json;
    }

    // Type not found - print helpful error
    std.debug.print("❌ Error in field '{s}': Invalid type '{s}'\n", .{ field_name, type_str });
    std.debug.print("   Valid types: uuid, text, boolean, i16, i32, i64, timestamp, json\n", .{});
    return ParseError.InvalidFieldType;
}

/// Map JSON input_mode string to InputMode enum
fn parseInputMode(mode_str: []const u8, field_name: []const u8) ParseError!InputMode {
    if (std.mem.eql(u8, mode_str, "required")) {
        return InputMode.required;
    } else if (std.mem.eql(u8, mode_str, "optional")) {
        return InputMode.optional;
    } else if (std.mem.eql(u8, mode_str, "auto_generated")) {
        return InputMode.excluded; // Auto-generated fields are excluded from input
    }

    std.debug.print("❌ Error in field '{s}': Invalid input_mode '{s}'\n", .{ field_name, mode_str });
    std.debug.print("   Valid modes: required, optional, auto_generated\n", .{});
    return ParseError.InvalidInputMode;
}

/// Parse relationship type from string
fn parseRelationshipType(type_str: []const u8) ParseError!RelationshipType {
    if (std.mem.eql(u8, type_str, "many_to_one")) {
        return RelationshipType.many_to_one;
    } else if (std.mem.eql(u8, type_str, "one_to_many")) {
        return RelationshipType.one_to_many;
    } else if (std.mem.eql(u8, type_str, "one_to_one")) {
        return RelationshipType.one_to_one;
    } else if (std.mem.eql(u8, type_str, "many_to_many")) {
        return RelationshipType.many_to_many;
    }
    return RelationshipType.many_to_one; // default
}

/// Parse ON DELETE action from string
fn parseOnDeleteAction(action_str: []const u8) ParseError!OnDeleteAction {
    if (std.mem.eql(u8, action_str, "CASCADE")) {
        return OnDeleteAction.cascade;
    } else if (std.mem.eql(u8, action_str, "SET NULL")) {
        return OnDeleteAction.set_null;
    } else if (std.mem.eql(u8, action_str, "SET DEFAULT")) {
        return OnDeleteAction.set_default;
    } else if (std.mem.eql(u8, action_str, "RESTRICT")) {
        return OnDeleteAction.restrict;
    } else if (std.mem.eql(u8, action_str, "NO ACTION")) {
        return OnDeleteAction.no_action;
    }
    return OnDeleteAction.no_action;
}

/// Parse ON UPDATE action from string
fn parseOnUpdateAction(action_str: []const u8) ParseError!OnUpdateAction {
    if (std.mem.eql(u8, action_str, "CASCADE")) {
        return OnUpdateAction.cascade;
    } else if (std.mem.eql(u8, action_str, "SET NULL")) {
        return OnUpdateAction.set_null;
    } else if (std.mem.eql(u8, action_str, "SET DEFAULT")) {
        return OnUpdateAction.set_default;
    } else if (std.mem.eql(u8, action_str, "RESTRICT")) {
        return OnUpdateAction.restrict;
    } else if (std.mem.eql(u8, action_str, "NO ACTION")) {
        return OnUpdateAction.no_action;
    }
    return OnUpdateAction.no_action;
}

/// Parse a JSON schema file into a Schema struct
pub fn parseJsonSchema(allocator: std.mem.Allocator, json_content: []const u8) ParseError!Schema {
    // Parse JSON
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_content,
        .{},
    ) catch |err| {
        std.debug.print("❌ Failed to parse JSON: {}\n", .{err});
        return ParseError.InvalidJson;
    };
    defer parsed.deinit();

    const root = parsed.value;
    const obj = switch (root) {
        .object => |o| o,
        else => {
            std.debug.print("❌ Schema must be a JSON object\n", .{});
            return ParseError.InvalidStructure;
        },
    };

    // Extract table_name
    const table_name = blk: {
        const value = obj.get("table_name") orelse {
            std.debug.print("❌ Missing required field: table_name\n", .{});
            return ParseError.MissingRequiredField;
        };
        break :blk switch (value) {
            .string => |s| try allocator.dupe(u8, s),
            else => {
                std.debug.print("❌ table_name must be a string\n", .{});
                return ParseError.InvalidStructure;
            },
        };
    };
    errdefer allocator.free(table_name);

    // Extract struct_name
    const struct_name = blk: {
        const value = obj.get("struct_name") orelse {
            std.debug.print("❌ Missing required field: struct_name\n", .{});
            return ParseError.MissingRequiredField;
        };
        break :blk switch (value) {
            .string => |s| try allocator.dupe(u8, s),
            else => {
                std.debug.print("❌ struct_name must be a string\n", .{});
                return ParseError.InvalidStructure;
            },
        };
    };
    errdefer allocator.free(struct_name);

    // Parse fields
    const fields_json = obj.get("fields") orelse {
        std.debug.print("❌ Missing required field: fields\n", .{});
        return ParseError.MissingRequiredField;
    };

    const fields_array = switch (fields_json) {
        .array => |arr| arr,
        else => {
            std.debug.print("❌ 'fields' must be an array\n", .{});
            return ParseError.InvalidStructure;
        },
    };

    var fields = std.ArrayList(Field){};
    errdefer {
        // Clean up all allocated field data
        for (fields.items) |field| {
            allocator.free(field.name);
            if (field.default_value) |default| {
                allocator.free(default);
            }
        }
        fields.deinit(allocator);
    }

    for (fields_array.items) |field_value| {
        const field_obj = switch (field_value) {
            .object => |o| o,
            else => {
                std.debug.print("❌ Each field must be an object\n", .{});
                return ParseError.InvalidStructure;
            },
        };

        // Parse field name
        const name = blk: {
            const value = field_obj.get("name") orelse {
                std.debug.print("❌ Field missing 'name' property\n", .{});
                return ParseError.MissingRequiredField;
            };
            break :blk switch (value) {
                .string => |s| try allocator.dupe(u8, s),
                else => {
                    std.debug.print("❌ Field 'name' must be a string\n", .{});
                    return ParseError.InvalidStructure;
                },
            };
        };
        errdefer allocator.free(name);

        // Parse nullable (default: false)
        const nullable = if (field_obj.get("nullable")) |value|
            switch (value) {
                .bool => |b| b,
                else => {
                    std.debug.print("❌ Field '{s}' nullable must be boolean\n", .{name});
                    return ParseError.InvalidBoolean;
                },
            }
        else
            false;

        // Parse field type (considering nullability)
        const type_str = blk: {
            const value = field_obj.get("type") orelse {
                std.debug.print("❌ Field '{s}' missing 'type' property\n", .{name});
                return ParseError.MissingRequiredField;
            };
            break :blk switch (value) {
                .string => |s| s,
                else => {
                    std.debug.print("❌ Field '{s}' type must be a string\n", .{name});
                    return ParseError.InvalidStructure;
                },
            };
        };
        const field_type = try parseFieldType(type_str, nullable, name);

        // Parse primary_key (default: false)
        const primary_key = if (field_obj.get("primary_key")) |value|
            switch (value) {
                .bool => |b| b,
                else => {
                    std.debug.print("❌ Field '{s}' primary_key must be boolean\n", .{name});
                    return ParseError.InvalidBoolean;
                },
            }
        else
            false;

        // Parse unique (default: false)
        const unique = if (field_obj.get("unique")) |value|
            switch (value) {
                .bool => |b| b,
                else => {
                    std.debug.print("❌ Field '{s}' unique must be boolean\n", .{name});
                    return ParseError.InvalidBoolean;
                },
            }
        else
            false;

        // Parse default value
        const default_value = if (field_obj.get("default")) |value|
            switch (value) {
                .string => |s| try allocator.dupe(u8, s),
                .null => null,
                else => null,
            }
        else
            null;
        errdefer if (default_value) |dv| allocator.free(dv);

        // Parse input_mode (default: excluded)
        const create_input = if (field_obj.get("input_mode")) |value| blk: {
            const mode_str = switch (value) {
                .string => |s| s,
                else => {
                    std.debug.print("❌ Field '{s}' input_mode must be a string\n", .{name});
                    return ParseError.InvalidStructure;
                },
            };
            break :blk try parseInputMode(mode_str, name);
        } else InputMode.excluded;

        // For now, map update_input based on input_mode
        // Required and optional fields can be updated
        const update_input = create_input != InputMode.excluded;

        // Parse redacted flag (default: false)
        const redacted = if (field_obj.get("redacted")) |value| blk: {
            break :blk switch (value) {
                .bool => |b| b,
                else => {
                    std.debug.print("❌ Field '{s}' redacted must be a boolean\n", .{name});
                    return ParseError.InvalidStructure;
                },
            };
        } else false;

        try fields.append(allocator, Field{
            .name = name,
            .type = field_type,
            .primary_key = primary_key,
            .unique = unique,
            .not_null = !nullable,
            .default_value = default_value,
            .create_input = create_input,
            .update_input = update_input,
            .redacted = redacted,
        });
    }

    // Parse relationships (optional)
    var relationships = std.ArrayList(Relationship){};
    errdefer {
        // Clean up all allocated relationship data
        for (relationships.items) |rel| {
            allocator.free(rel.name);
            allocator.free(rel.column);
            allocator.free(rel.references_table);
            allocator.free(rel.references_column);
        }
        relationships.deinit(allocator);
    }

    if (obj.get("relationships")) |relationships_json| {
        const relationships_array = switch (relationships_json) {
            .array => |arr| arr,
            else => {
                std.debug.print("❌ 'relationships' must be an array\n", .{});
                return ParseError.InvalidStructure;
            },
        };

        for (relationships_array.items) |rel_value| {
            const rel_obj = switch (rel_value) {
                .object => |o| o,
                else => {
                    std.debug.print("❌ Each relationship must be an object\n", .{});
                    return ParseError.InvalidStructure;
                },
            };

            // Parse relationship name
            const name = blk: {
                const value = rel_obj.get("name") orelse {
                    std.debug.print("❌ Relationship missing 'name' property\n", .{});
                    return ParseError.MissingRequiredField;
                };
                break :blk switch (value) {
                    .string => |s| try allocator.dupe(u8, s),
                    else => {
                        std.debug.print("❌ Relationship 'name' must be a string\n", .{});
                        return ParseError.InvalidStructure;
                    },
                };
            };
            errdefer allocator.free(name);

            // Parse column
            const column = blk: {
                const value = rel_obj.get("column") orelse {
                    std.debug.print("❌ Relationship '{s}' missing 'column' property\n", .{name});
                    return ParseError.MissingRequiredField;
                };
                break :blk switch (value) {
                    .string => |s| try allocator.dupe(u8, s),
                    else => {
                        std.debug.print("❌ Relationship '{s}' column must be a string\n", .{name});
                        return ParseError.InvalidStructure;
                    },
                };
            };
            errdefer allocator.free(column);

            // Parse references object
            const references = rel_obj.get("references") orelse {
                std.debug.print("❌ Relationship '{s}' missing 'references' property\n", .{name});
                return ParseError.MissingRequiredField;
            };

            const references_obj = switch (references) {
                .object => |o| o,
                else => {
                    std.debug.print("❌ Relationship '{s}' references must be an object\n", .{name});
                    return ParseError.InvalidStructure;
                },
            };

            // Parse references.table
            const references_table = blk: {
                const value = references_obj.get("table") orelse {
                    std.debug.print("❌ Relationship '{s}' references missing 'table' property\n", .{name});
                    return ParseError.MissingRequiredField;
                };
                break :blk switch (value) {
                    .string => |s| try allocator.dupe(u8, s),
                    else => {
                        std.debug.print("❌ Relationship '{s}' references.table must be a string\n", .{name});
                        return ParseError.InvalidStructure;
                    },
                };
            };
            errdefer allocator.free(references_table);

            // Parse references.column
            const references_column = blk: {
                const value = references_obj.get("column") orelse {
                    std.debug.print("❌ Relationship '{s}' references missing 'column' property\n", .{name});
                    return ParseError.MissingRequiredField;
                };
                break :blk switch (value) {
                    .string => |s| try allocator.dupe(u8, s),
                    else => {
                        std.debug.print("❌ Relationship '{s}' references.column must be a string\n", .{name});
                        return ParseError.InvalidStructure;
                    },
                };
            };
            errdefer allocator.free(references_column);

            // Parse relationship_type (optional, default: many_to_one)
            const relationship_type = if (rel_obj.get("type")) |value| blk: {
                const type_str = switch (value) {
                    .string => |s| s,
                    else => {
                        std.debug.print("❌ Relationship '{s}' type must be a string\n", .{name});
                        return ParseError.InvalidStructure;
                    },
                };
                break :blk try parseRelationshipType(type_str);
            } else RelationshipType.many_to_one;

            // Parse on_delete (optional, default: NO ACTION)
            const on_delete = if (rel_obj.get("on_delete")) |value| blk: {
                const action_str = switch (value) {
                    .string => |s| s,
                    else => {
                        std.debug.print("❌ Relationship '{s}' on_delete must be a string\n", .{name});
                        return ParseError.InvalidStructure;
                    },
                };
                break :blk try parseOnDeleteAction(action_str);
            } else OnDeleteAction.no_action;

            // Parse on_update (optional, default: NO ACTION)
            const on_update = if (rel_obj.get("on_update")) |value| blk: {
                const action_str = switch (value) {
                    .string => |s| s,
                    else => {
                        std.debug.print("❌ Relationship '{s}' on_update must be a string\n", .{name});
                        return ParseError.InvalidStructure;
                    },
                };
                break :blk try parseOnUpdateAction(action_str);
            } else OnUpdateAction.no_action;

            try relationships.append(allocator, Relationship{
                .name = name,
                .column = column,
                .references_table = references_table,
                .references_column = references_column,
                .relationship_type = relationship_type,
                .on_delete = on_delete,
                .on_update = on_update,
            });
        }
    }

    // Parse indexes (optional)
    var indexes = std.ArrayList(Index){};
    errdefer {
        // Clean up all allocated index data
        for (indexes.items) |index| {
            allocator.free(index.name);
            for (index.columns) |col| {
                allocator.free(col);
            }
            allocator.free(index.columns);
        }
        indexes.deinit(allocator);
    }

    if (obj.get("indexes")) |indexes_json| {
        const indexes_array = switch (indexes_json) {
            .array => |arr| arr,
            else => {
                std.debug.print("❌ 'indexes' must be an array\n", .{});
                return ParseError.InvalidStructure;
            },
        };

        for (indexes_array.items) |index_value| {
            const index_obj = switch (index_value) {
                .object => |o| o,
                else => {
                    std.debug.print("❌ Each index must be an object\n", .{});
                    return ParseError.InvalidStructure;
                },
            };

            // Parse index name
            const name = blk: {
                const value = index_obj.get("name") orelse {
                    std.debug.print("❌ Index missing 'name' property\n", .{});
                    return ParseError.MissingRequiredField;
                };
                break :blk switch (value) {
                    .string => |s| try allocator.dupe(u8, s),
                    else => {
                        std.debug.print("❌ Index 'name' must be a string\n", .{});
                        return ParseError.InvalidStructure;
                    },
                };
            };
            errdefer allocator.free(name);

            // Parse columns
            const columns_json = index_obj.get("columns") orelse {
                std.debug.print("❌ Index '{s}' missing 'columns' property\n", .{name});
                return ParseError.MissingRequiredField;
            };

            const columns_array = switch (columns_json) {
                .array => |arr| arr,
                else => {
                    std.debug.print("❌ Index '{s}' columns must be an array\n", .{name});
                    return ParseError.InvalidStructure;
                },
            };

            var columns = std.ArrayList([]const u8){};
            errdefer {
                for (columns.items) |col| {
                    allocator.free(col);
                }
                columns.deinit(allocator);
            }

            for (columns_array.items) |col_value| {
                const col_str = switch (col_value) {
                    .string => |s| try allocator.dupe(u8, s),
                    else => {
                        std.debug.print("❌ Index '{s}' column names must be strings\n", .{name});
                        return ParseError.InvalidStructure;
                    },
                };
                try columns.append(allocator, col_str);
            }

            // Parse unique (default: false)
            const unique = if (index_obj.get("unique")) |value|
                switch (value) {
                    .bool => |b| b,
                    else => {
                        std.debug.print("❌ Index '{s}' unique must be boolean\n", .{name});
                        return ParseError.InvalidBoolean;
                    },
                }
            else
                false;

            try indexes.append(allocator, Index{
                .name = name,
                .columns = try columns.toOwnedSlice(allocator),
                .unique = unique,
            });
        }
    }

    std.debug.print("✅ Schema validation passed: {s} ({d} fields, {d} indexes, {d} relationships)\n", .{ struct_name, fields.items.len, indexes.items.len, relationships.items.len });

    return Schema{
        .table_name = table_name,
        .struct_name = struct_name,
        .fields = try fields.toOwnedSlice(allocator),
        .indexes = try indexes.toOwnedSlice(allocator),
        .relationships = try relationships.toOwnedSlice(allocator),
    };
}
