// AUTO-GENERATED CODE - DO NOT EDIT
// Explicit relation types for full ZLS IntelliSense support

const std = @import("std");
const Row = @import("pg").Row;
const Model = @import("model.zig");
const PostCategories = @import("../post_categories/model.zig");

/// Categories with posts relation loaded
pub const CategoriesWithPostCategories = struct {
    id: []const u8,
    name: []const u8,
    slug: []const u8,
    description: ?[]const u8,
    color: ?[]const u8,
    sort_order: i32,
    is_active: bool,
    created_at: i64,
    updated_at: i64,
    posts: ?[]PostCategories = null,

    /// Create from a base Categories model with relation set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .name = model.name,
            .slug = model.slug,
            .description = model.description,
            .color = model.color,
            .sort_order = model.sort_order,
            .is_active = model.is_active,
            .created_at = model.created_at,
            .updated_at = model.updated_at,
            .posts = null,
        };
    }

    /// Extract the base Categories model (without relation)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .name = self.name,
            .slug = self.slug,
            .description = self.description,
            .color = self.color,
            .sort_order = self.sort_order,
            .is_active = self.is_active,
            .created_at = self.created_at,
            .updated_at = self.updated_at,
        };
    }

    /// Create from a database row, parsing JSONB relation columns.
    /// Use this with query results that include relations via LEFT JOIN.
    pub fn fromRow(row: Row, allocator: std.mem.Allocator) !@This() {
        var result: @This() = undefined;

        // Map base fields
        result.id = row.getCol([]const u8, "id");
        result.name = row.getCol([]const u8, "name");
        result.slug = row.getCol([]const u8, "slug");
        result.description = row.getCol(?[]const u8, "description");
        result.color = row.getCol(?[]const u8, "color");
        result.sort_order = row.getCol(i32, "sort_order");
        result.is_active = row.getCol(bool, "is_active");
        result.created_at = row.getCol(i64, "created_at");
        result.updated_at = row.getCol(i64, "updated_at");

        // Parse JSONB relation: posts
        const posts_json = row.getCol(?[]const u8, "posts");
        if (posts_json) |json_str| {
            if (std.json.parseFromSlice([]PostCategories, allocator, json_str, .{})) |parsed| {
                result.posts = parsed.value;
            } else |_| {
                result.posts = null;
            }
        } else {
            result.posts = null;
        }

        return result;
    }
};

