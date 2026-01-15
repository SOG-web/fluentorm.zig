// AUTO-GENERATED CODE - DO NOT EDIT
// Explicit relation types for full ZLS IntelliSense support

const std = @import("std");
const Row = @import("pg").Row;
const Model = @import("model.zig");
const Users = @import("../users/model.zig");
const Comments = @import("../comments/model.zig");

/// Posts with user relation loaded
pub const PostsWithUsers = struct {
    id: []const u8,
    title: []const u8,
    content: []const u8,
    user_id: []const u8,
    is_published: bool,
    view_count: i32,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    user: ?Users = null,

    /// Create from a base Posts model with relation set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .title = model.title,
            .content = model.content,
            .user_id = model.user_id,
            .is_published = model.is_published,
            .view_count = model.view_count,
            .created_at = model.created_at,
            .updated_at = model.updated_at,
            .deleted_at = model.deleted_at,
            .user = null,
        };
    }

    /// Extract the base Posts model (without relation)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .title = self.title,
            .content = self.content,
            .user_id = self.user_id,
            .is_published = self.is_published,
            .view_count = self.view_count,
            .created_at = self.created_at,
            .updated_at = self.updated_at,
            .deleted_at = self.deleted_at,
        };
    }

    /// Create from a database row, parsing JSONB relation columns.
    /// Use this with query results that include relations via LEFT JOIN.
    pub fn fromRow(row: Row, allocator: std.mem.Allocator) !@This() {
        var result: @This() = undefined;

        // Map base fields
        result.id = row.get([]const u8, "id");
        result.title = row.get([]const u8, "title");
        result.content = row.get([]const u8, "content");
        result.user_id = row.get([]const u8, "user_id");
        result.is_published = row.get(bool, "is_published");
        result.view_count = row.get(i32, "view_count");
        result.created_at = row.get(i64, "created_at");
        result.updated_at = row.get(i64, "updated_at");
        result.deleted_at = row.get(?i64, "deleted_at");

        // Parse JSONB relation: user
        const user_json = row.get(?[]const u8, "user");
        if (user_json) |json_str| {
            result.user = std.json.parseFromSlice(Users, allocator, json_str, .{}) catch null;
        } else {
            result.user = null;
        }

        return result;
    }
};

/// Posts with comments relation loaded
pub const PostsWithComments = struct {
    id: []const u8,
    title: []const u8,
    content: []const u8,
    user_id: []const u8,
    is_published: bool,
    view_count: i32,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    comments: ?[]Comments = null,

    /// Create from a base Posts model with relation set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .title = model.title,
            .content = model.content,
            .user_id = model.user_id,
            .is_published = model.is_published,
            .view_count = model.view_count,
            .created_at = model.created_at,
            .updated_at = model.updated_at,
            .deleted_at = model.deleted_at,
            .comments = null,
        };
    }

    /// Extract the base Posts model (without relation)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .title = self.title,
            .content = self.content,
            .user_id = self.user_id,
            .is_published = self.is_published,
            .view_count = self.view_count,
            .created_at = self.created_at,
            .updated_at = self.updated_at,
            .deleted_at = self.deleted_at,
        };
    }

    /// Create from a database row, parsing JSONB relation columns.
    /// Use this with query results that include relations via LEFT JOIN.
    pub fn fromRow(row: Row, allocator: std.mem.Allocator) !@This() {
        var result: @This() = undefined;

        // Map base fields
        result.id = row.get([]const u8, "id");
        result.title = row.get([]const u8, "title");
        result.content = row.get([]const u8, "content");
        result.user_id = row.get([]const u8, "user_id");
        result.is_published = row.get(bool, "is_published");
        result.view_count = row.get(i32, "view_count");
        result.created_at = row.get(i64, "created_at");
        result.updated_at = row.get(i64, "updated_at");
        result.deleted_at = row.get(?i64, "deleted_at");

        // Parse JSONB relation: comments
        const comments_json = row.get(?[]const u8, "comments");
        if (comments_json) |json_str| {
            result.comments = std.json.parseFromSlice([]Comments, allocator, json_str, .{}) catch null;
        } else {
            result.comments = null;
        }

        return result;
    }
};

/// Posts with all relations loaded
pub const PostsWithAllRelations = struct {
    id: []const u8,
    title: []const u8,
    content: []const u8,
    user_id: []const u8,
    is_published: bool,
    view_count: i32,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    user: ?Users = null,
    comments: ?[]Comments = null,

    /// Create from a base Posts model with all relations set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .title = model.title,
            .content = model.content,
            .user_id = model.user_id,
            .is_published = model.is_published,
            .view_count = model.view_count,
            .created_at = model.created_at,
            .updated_at = model.updated_at,
            .deleted_at = model.deleted_at,
            .user = null,
            .comments = null,
        };
    }

    /// Extract the base Posts model (without relations)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .title = self.title,
            .content = self.content,
            .user_id = self.user_id,
            .is_published = self.is_published,
            .view_count = self.view_count,
            .created_at = self.created_at,
            .updated_at = self.updated_at,
            .deleted_at = self.deleted_at,
        };
    }

    /// Create from a database row, parsing all JSONB relation columns.
    /// Use this with query results that include relations via LEFT JOIN.
    pub fn fromRow(row: Row, allocator: std.mem.Allocator) !@This() {
        var result: @This() = undefined;

        // Map base fields
        result.id = row.get([]const u8, "id");
        result.title = row.get([]const u8, "title");
        result.content = row.get([]const u8, "content");
        result.user_id = row.get([]const u8, "user_id");
        result.is_published = row.get(bool, "is_published");
        result.view_count = row.get(i32, "view_count");
        result.created_at = row.get(i64, "created_at");
        result.updated_at = row.get(i64, "updated_at");
        result.deleted_at = row.get(?i64, "deleted_at");

        // Parse JSONB relations
        const user_json = row.get(?[]const u8, "user");
        if (user_json) |json_str| {
            result.user = std.json.parseFromSlice(Users, allocator, json_str, .{}) catch null;
        } else {
            result.user = null;
        }
        const comments_json = row.get(?[]const u8, "comments");
        if (comments_json) |json_str| {
            result.comments = std.json.parseFromSlice([]Comments, allocator, json_str, .{}) catch null;
        } else {
            result.comments = null;
        }

        return result;
    }
};
