// AUTO-GENERATED CODE - DO NOT EDIT
// Explicit relation types for full ZLS IntelliSense support

const std = @import("std");
const Row = @import("pg").Row;
const Model = @import("model.zig");
const Posts = @import("../posts/model.zig");
const Categories = @import("../categories/model.zig");

/// PostCategories with post relation loaded
pub const PostCategoriesWithPosts = struct {
    id: []const u8,
    post_id: []const u8,
    category_id: []const u8,
    created_at: i64,
    post: ?Posts = null,

    /// Create from a base PostCategories model with relation set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .post_id = model.post_id,
            .category_id = model.category_id,
            .created_at = model.created_at,
            .post = null,
        };
    }

    /// Extract the base PostCategories model (without relation)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .post_id = self.post_id,
            .category_id = self.category_id,
            .created_at = self.created_at,
        };
    }

    /// Create from a database row, parsing JSONB relation columns.
    /// Use this with query results that include relations via LEFT JOIN.
    pub fn fromRow(row: Row, allocator: std.mem.Allocator) !@This() {
        var result: @This() = undefined;

        // Map base fields
        result.id = row.get([]const u8, "id");
        result.post_id = row.get([]const u8, "post_id");
        result.category_id = row.get([]const u8, "category_id");
        result.created_at = row.get(i64, "created_at");

        // Parse JSONB relation: post
        const post_json = row.get(?[]const u8, "post");
        if (post_json) |json_str| {
            result.post = std.json.parseFromSlice(Posts, allocator, json_str, .{}) catch null;
        } else {
            result.post = null;
        }

        return result;
    }
};

/// PostCategories with category relation loaded
pub const PostCategoriesWithCategories = struct {
    id: []const u8,
    post_id: []const u8,
    category_id: []const u8,
    created_at: i64,
    category: ?Categories = null,

    /// Create from a base PostCategories model with relation set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .post_id = model.post_id,
            .category_id = model.category_id,
            .created_at = model.created_at,
            .category = null,
        };
    }

    /// Extract the base PostCategories model (without relation)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .post_id = self.post_id,
            .category_id = self.category_id,
            .created_at = self.created_at,
        };
    }

    /// Create from a database row, parsing JSONB relation columns.
    /// Use this with query results that include relations via LEFT JOIN.
    pub fn fromRow(row: Row, allocator: std.mem.Allocator) !@This() {
        var result: @This() = undefined;

        // Map base fields
        result.id = row.get([]const u8, "id");
        result.post_id = row.get([]const u8, "post_id");
        result.category_id = row.get([]const u8, "category_id");
        result.created_at = row.get(i64, "created_at");

        // Parse JSONB relation: category
        const category_json = row.get(?[]const u8, "category");
        if (category_json) |json_str| {
            result.category = std.json.parseFromSlice(Categories, allocator, json_str, .{}) catch null;
        } else {
            result.category = null;
        }

        return result;
    }
};

/// PostCategories with all relations loaded
pub const PostCategoriesWithAllRelations = struct {
    id: []const u8,
    post_id: []const u8,
    category_id: []const u8,
    created_at: i64,
    post: ?Posts = null,
    category: ?Categories = null,

    /// Create from a base PostCategories model with all relations set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .post_id = model.post_id,
            .category_id = model.category_id,
            .created_at = model.created_at,
            .post = null,
            .category = null,
        };
    }

    /// Extract the base PostCategories model (without relations)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .post_id = self.post_id,
            .category_id = self.category_id,
            .created_at = self.created_at,
        };
    }

    /// Create from a database row, parsing all JSONB relation columns.
    /// Use this with query results that include relations via LEFT JOIN.
    pub fn fromRow(row: Row, allocator: std.mem.Allocator) !@This() {
        var result: @This() = undefined;

        // Map base fields
        result.id = row.get([]const u8, "id");
        result.post_id = row.get([]const u8, "post_id");
        result.category_id = row.get([]const u8, "category_id");
        result.created_at = row.get(i64, "created_at");

        // Parse JSONB relations
        const post_json = row.get(?[]const u8, "post");
        if (post_json) |json_str| {
            result.post = std.json.parseFromSlice(Posts, allocator, json_str, .{}) catch null;
        } else {
            result.post = null;
        }
        const category_json = row.get(?[]const u8, "category");
        if (category_json) |json_str| {
            result.category = std.json.parseFromSlice(Categories, allocator, json_str, .{}) catch null;
        } else {
            result.category = null;
        }

        return result;
    }
};
