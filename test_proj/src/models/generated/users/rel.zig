// AUTO-GENERATED CODE - DO NOT EDIT
// Explicit relation types for full ZLS IntelliSense support

const std = @import("std");
const Row = @import("pg").Row;
const Model = @import("model.zig");
const Posts = @import("../posts/model.zig");
const Comments = @import("../comments/model.zig");

/// Users with posts relation loaded
pub const UsersWithPosts = struct {
    id: []const u8,
    email: []const u8,
    name: []const u8,
    bid: ?[]const u8,
    password_hash: []const u8,
    is_active: bool,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    phone: ?[]const u8,
    bio: ?[]const u8,
    posts: ?[]Posts = null,

    /// Create from a base Users model with relation set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .email = model.email,
            .name = model.name,
            .bid = model.bid,
            .password_hash = model.password_hash,
            .is_active = model.is_active,
            .created_at = model.created_at,
            .updated_at = model.updated_at,
            .deleted_at = model.deleted_at,
            .phone = model.phone,
            .bio = model.bio,
            .posts = null,
        };
    }

    /// Extract the base Users model (without relation)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .email = self.email,
            .name = self.name,
            .bid = self.bid,
            .password_hash = self.password_hash,
            .is_active = self.is_active,
            .created_at = self.created_at,
            .updated_at = self.updated_at,
            .deleted_at = self.deleted_at,
            .phone = self.phone,
            .bio = self.bio,
        };
    }

    /// Create from a database row, parsing JSONB relation columns.
    /// Use this with query results that include relations via LEFT JOIN.
    pub fn fromRow(row: Row, allocator: std.mem.Allocator) !@This() {
        var result: @This() = undefined;

        // Map base fields
        result.id = row.get([]const u8, "id");
        result.email = row.get([]const u8, "email");
        result.name = row.get([]const u8, "name");
        result.bid = row.get(?[]const u8, "bid");
        result.password_hash = row.get([]const u8, "password_hash");
        result.is_active = row.get(bool, "is_active");
        result.created_at = row.get(i64, "created_at");
        result.updated_at = row.get(i64, "updated_at");
        result.deleted_at = row.get(?i64, "deleted_at");
        result.phone = row.get(?[]const u8, "phone");
        result.bio = row.get(?[]const u8, "bio");

        // Parse JSONB relation: posts
        const posts_json = row.get(?[]const u8, "posts");
        if (posts_json) |json_str| {
            result.posts = std.json.parseFromSlice([]Posts, allocator, json_str, .{}) catch null;
        } else {
            result.posts = null;
        }

        return result;
    }
};

/// Users with comments relation loaded
pub const UsersWithComments = struct {
    id: []const u8,
    email: []const u8,
    name: []const u8,
    bid: ?[]const u8,
    password_hash: []const u8,
    is_active: bool,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    phone: ?[]const u8,
    bio: ?[]const u8,
    comments: ?[]Comments = null,

    /// Create from a base Users model with relation set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .email = model.email,
            .name = model.name,
            .bid = model.bid,
            .password_hash = model.password_hash,
            .is_active = model.is_active,
            .created_at = model.created_at,
            .updated_at = model.updated_at,
            .deleted_at = model.deleted_at,
            .phone = model.phone,
            .bio = model.bio,
            .comments = null,
        };
    }

    /// Extract the base Users model (without relation)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .email = self.email,
            .name = self.name,
            .bid = self.bid,
            .password_hash = self.password_hash,
            .is_active = self.is_active,
            .created_at = self.created_at,
            .updated_at = self.updated_at,
            .deleted_at = self.deleted_at,
            .phone = self.phone,
            .bio = self.bio,
        };
    }

    /// Create from a database row, parsing JSONB relation columns.
    /// Use this with query results that include relations via LEFT JOIN.
    pub fn fromRow(row: Row, allocator: std.mem.Allocator) !@This() {
        var result: @This() = undefined;

        // Map base fields
        result.id = row.get([]const u8, "id");
        result.email = row.get([]const u8, "email");
        result.name = row.get([]const u8, "name");
        result.bid = row.get(?[]const u8, "bid");
        result.password_hash = row.get([]const u8, "password_hash");
        result.is_active = row.get(bool, "is_active");
        result.created_at = row.get(i64, "created_at");
        result.updated_at = row.get(i64, "updated_at");
        result.deleted_at = row.get(?i64, "deleted_at");
        result.phone = row.get(?[]const u8, "phone");
        result.bio = row.get(?[]const u8, "bio");

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

/// Users with all relations loaded
pub const UsersWithAllRelations = struct {
    id: []const u8,
    email: []const u8,
    name: []const u8,
    bid: ?[]const u8,
    password_hash: []const u8,
    is_active: bool,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    phone: ?[]const u8,
    bio: ?[]const u8,
    posts: ?[]Posts = null,
    comments: ?[]Comments = null,

    /// Create from a base Users model with all relations set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .email = model.email,
            .name = model.name,
            .bid = model.bid,
            .password_hash = model.password_hash,
            .is_active = model.is_active,
            .created_at = model.created_at,
            .updated_at = model.updated_at,
            .deleted_at = model.deleted_at,
            .phone = model.phone,
            .bio = model.bio,
            .posts = null,
            .comments = null,
        };
    }

    /// Extract the base Users model (without relations)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .email = self.email,
            .name = self.name,
            .bid = self.bid,
            .password_hash = self.password_hash,
            .is_active = self.is_active,
            .created_at = self.created_at,
            .updated_at = self.updated_at,
            .deleted_at = self.deleted_at,
            .phone = self.phone,
            .bio = self.bio,
        };
    }

    /// Create from a database row, parsing all JSONB relation columns.
    /// Use this with query results that include relations via LEFT JOIN.
    pub fn fromRow(row: Row, allocator: std.mem.Allocator) !@This() {
        var result: @This() = undefined;

        // Map base fields
        result.id = row.get([]const u8, "id");
        result.email = row.get([]const u8, "email");
        result.name = row.get([]const u8, "name");
        result.bid = row.get(?[]const u8, "bid");
        result.password_hash = row.get([]const u8, "password_hash");
        result.is_active = row.get(bool, "is_active");
        result.created_at = row.get(i64, "created_at");
        result.updated_at = row.get(i64, "updated_at");
        result.deleted_at = row.get(?i64, "deleted_at");
        result.phone = row.get(?[]const u8, "phone");
        result.bio = row.get(?[]const u8, "bio");

        // Parse JSONB relations
        const posts_json = row.get(?[]const u8, "posts");
        if (posts_json) |json_str| {
            result.posts = std.json.parseFromSlice([]Posts, allocator, json_str, .{}) catch null;
        } else {
            result.posts = null;
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
