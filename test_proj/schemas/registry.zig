// Auto-generated file - do not edit manually
// Run 'zig build generate' to regenerate

const std = @import("std");
const TableSchema = @import("fluentorm").TableSchema;
const SchemaBuilder = @import("fluentorm").SchemaBuilder;

const @"01_users_schema" = @import("01_users.zig");
const @"02_posts_schema" = @import("02_posts.zig");
const @"03_profiles_schema" = @import("03_profiles.zig");
const @"04_categories_schema" = @import("04_categories.zig");
const @"05_post_categories_schema" = @import("05_post_categories.zig");
const @"06_comments_schema" = @import("06_comments.zig");
const @"07_users_extra_schema" = @import("07_users_extra.zig");

/// Information about a table and its schema files
pub const TableInfo = struct {
    name: []const u8,
    builders: []const SchemaBuilder,
};

/// Tables grouped by table_name with their schema builders
pub const tables = [_]TableInfo{
    .{ .name = "users", .builders = &[_]SchemaBuilder{
        .{ .name = "users", .builder_fn = @"01_users_schema".build },
        .{ .name = "users", .builder_fn = @"07_users_extra_schema".build },
    }},
    .{ .name = "posts", .builders = &[_]SchemaBuilder{
        .{ .name = "posts", .builder_fn = @"02_posts_schema".build },
    }},
    .{ .name = "profiles", .builders = &[_]SchemaBuilder{
        .{ .name = "profiles", .builder_fn = @"03_profiles_schema".build },
    }},
    .{ .name = "categories", .builders = &[_]SchemaBuilder{
        .{ .name = "categories", .builder_fn = @"04_categories_schema".build },
    }},
    .{ .name = "post_categories", .builders = &[_]SchemaBuilder{
        .{ .name = "post_categories", .builder_fn = @"05_post_categories_schema".build },
    }},
    .{ .name = "comments", .builders = &[_]SchemaBuilder{
        .{ .name = "comments", .builder_fn = @"06_comments_schema".build },
    }},
};

/// Legacy: flat list of all schema builders (for backward compatibility)
pub const schemas = [_]SchemaBuilder{
    .{ .name = "users", .builder_fn = @"01_users_schema".build },
    .{ .name = "posts", .builder_fn = @"02_posts_schema".build },
    .{ .name = "profiles", .builder_fn = @"03_profiles_schema".build },
    .{ .name = "categories", .builder_fn = @"04_categories_schema".build },
    .{ .name = "post_categories", .builder_fn = @"05_post_categories_schema".build },
    .{ .name = "comments", .builder_fn = @"06_comments_schema".build },
    .{ .name = "users", .builder_fn = @"07_users_extra_schema".build },
};

/// File prefixes for SQL migration ordering (e.g., "01", "02")
pub const file_prefixes = [_][]const u8{
    "01",
    "02",
    "03",
    "04",
    "05",
    "06",
    "07",
};

/// Get file prefixes for SQL migration ordering
pub fn getFilePrefixes() []const []const u8 {
    return &file_prefixes;
}

/// Get all schemas, merging multiple files that share the same table_name
pub fn getAllSchemasMerged(allocator: std.mem.Allocator) ![]TableSchema {
    var result = std.ArrayList(TableSchema){};
    errdefer {
        for (result.items) |*schema| {
            schema.deinit();
        }
        result.deinit(allocator);
    }

    for (tables) |table_info| {
        // Create ONE TableSchema per unique table_name
        var table = try TableSchema.createEmpty(table_info.name, allocator);
        errdefer table.deinit();

        // Call all builder functions for this table
        for (table_info.builders) |builder| {
            builder.builder_fn(&table);
        }

        try result.append(allocator, table);
    }

    return result.toOwnedSlice(allocator);
}

/// Legacy: Get all schemas without merging (for backward compatibility)
pub fn getAllSchemas(allocator: std.mem.Allocator) ![]TableSchema {
    var result = std.ArrayList(TableSchema){};
    errdefer {
        for (result.items) |*schema| {
            schema.deinit();
        }
        result.deinit(allocator);
    }

    for (schemas) |schema_builder| {
        const table = try TableSchema.create(
            schema_builder.name,
            allocator,
            schema_builder.builder_fn,
        );
        try result.append(allocator, table);
    }

    return result.toOwnedSlice(allocator);
}
