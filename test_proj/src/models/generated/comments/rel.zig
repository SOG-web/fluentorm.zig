// AUTO-GENERATED CODE - DO NOT EDIT
// Explicit relation types for full ZLS IntelliSense support

const std = @import("std");
const Row = @import("pg").Row;
const Model = @import("model.zig");
const Posts = @import("../posts/model.zig");
const Uwsers = @import("../uwsers/model.zig");

/// Comments with post relation loaded
pub const CommentsWithPosts = struct {
    id: []const u8,
    post_id: []const u8,
    user_id: []const u8,
    parent_id: ?[]const u8,
    content: []const u8,
    is_approved: bool,
    like_count: i32,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    post: ?Posts = null,

    /// Create from a base Comments model with relation set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .post_id = model.post_id,
            .user_id = model.user_id,
            .parent_id = model.parent_id,
            .content = model.content,
            .is_approved = model.is_approved,
            .like_count = model.like_count,
            .created_at = model.created_at,
            .updated_at = model.updated_at,
            .deleted_at = model.deleted_at,
            .post = null,
        };
    }

    /// Extract the base Comments model (without relation)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .post_id = self.post_id,
            .user_id = self.user_id,
            .parent_id = self.parent_id,
            .content = self.content,
            .is_approved = self.is_approved,
            .like_count = self.like_count,
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
        result.id = row.getCol([]const u8, "id");
        result.post_id = row.getCol([]const u8, "post_id");
        result.user_id = row.getCol([]const u8, "user_id");
        result.parent_id = row.getCol(?[]const u8, "parent_id");
        result.content = row.getCol([]const u8, "content");
        result.is_approved = row.getCol(bool, "is_approved");
        result.like_count = row.getCol(i32, "like_count");
        result.created_at = row.getCol(i64, "created_at");
        result.updated_at = row.getCol(i64, "updated_at");
        result.deleted_at = row.getCol(?i64, "deleted_at");

        // Parse JSONB relation: post
        const post_json = row.getCol(?[]const u8, "post");
        if (post_json) |json_str| {
            if (std.json.parseFromSlice(Posts, allocator, json_str, .{})) |parsed| {
                result.post = parsed.value;
            } else |_| {
                result.post = null;
            }
        } else {
            result.post = null;
        }

        return result;
    }
};

/// Comments with user relation loaded
pub const CommentsWithUwsers = struct {
    id: []const u8,
    post_id: []const u8,
    user_id: []const u8,
    parent_id: ?[]const u8,
    content: []const u8,
    is_approved: bool,
    like_count: i32,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    user: ?Uwsers = null,

    /// Create from a base Comments model with relation set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .post_id = model.post_id,
            .user_id = model.user_id,
            .parent_id = model.parent_id,
            .content = model.content,
            .is_approved = model.is_approved,
            .like_count = model.like_count,
            .created_at = model.created_at,
            .updated_at = model.updated_at,
            .deleted_at = model.deleted_at,
            .user = null,
        };
    }

    /// Extract the base Comments model (without relation)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .post_id = self.post_id,
            .user_id = self.user_id,
            .parent_id = self.parent_id,
            .content = self.content,
            .is_approved = self.is_approved,
            .like_count = self.like_count,
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
        result.id = row.getCol([]const u8, "id");
        result.post_id = row.getCol([]const u8, "post_id");
        result.user_id = row.getCol([]const u8, "user_id");
        result.parent_id = row.getCol(?[]const u8, "parent_id");
        result.content = row.getCol([]const u8, "content");
        result.is_approved = row.getCol(bool, "is_approved");
        result.like_count = row.getCol(i32, "like_count");
        result.created_at = row.getCol(i64, "created_at");
        result.updated_at = row.getCol(i64, "updated_at");
        result.deleted_at = row.getCol(?i64, "deleted_at");

        // Parse JSONB relation: user
        const user_json = row.getCol(?[]const u8, "user");
        if (user_json) |json_str| {
            if (std.json.parseFromSlice(Uwsers, allocator, json_str, .{})) |parsed| {
                result.user = parsed.value;
            } else |_| {
                result.user = null;
            }
        } else {
            result.user = null;
        }

        return result;
    }
};

/// Comments with all relations loaded
pub const CommentsWithAllRelations = struct {
    id: []const u8,
    post_id: []const u8,
    user_id: []const u8,
    parent_id: ?[]const u8,
    content: []const u8,
    is_approved: bool,
    like_count: i32,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    post: ?Posts = null,
    user: ?Uwsers = null,

    /// Create from a base Comments model with all relations set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .post_id = model.post_id,
            .user_id = model.user_id,
            .parent_id = model.parent_id,
            .content = model.content,
            .is_approved = model.is_approved,
            .like_count = model.like_count,
            .created_at = model.created_at,
            .updated_at = model.updated_at,
            .deleted_at = model.deleted_at,
            .post = null,
            .user = null,
        };
    }

    /// Extract the base Comments model (without relations)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .post_id = self.post_id,
            .user_id = self.user_id,
            .parent_id = self.parent_id,
            .content = self.content,
            .is_approved = self.is_approved,
            .like_count = self.like_count,
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
        result.id = row.getCol([]const u8, "id");
        result.post_id = row.getCol([]const u8, "post_id");
        result.user_id = row.getCol([]const u8, "user_id");
        result.parent_id = row.getCol(?[]const u8, "parent_id");
        result.content = row.getCol([]const u8, "content");
        result.is_approved = row.getCol(bool, "is_approved");
        result.like_count = row.getCol(i32, "like_count");
        result.created_at = row.getCol(i64, "created_at");
        result.updated_at = row.getCol(i64, "updated_at");
        result.deleted_at = row.getCol(?i64, "deleted_at");

        // Parse JSONB relations
        const post_json = row.getCol(?[]const u8, "post");
        if (post_json) |json_str| {
            if (std.json.parseFromSlice(Posts, allocator, json_str, .{})) |parsed| {
                result.post = parsed.value;
            } else |_| {
                result.post = null;
            }
        } else {
            result.post = null;
        }
        const user_json = row.getCol(?[]const u8, "user");
        if (user_json) |json_str| {
            if (std.json.parseFromSlice(Uwsers, allocator, json_str, .{})) |parsed| {
                result.user = parsed.value;
            } else |_| {
                result.user = null;
            }
        } else {
            result.user = null;
        }

        return result;
    }
};
