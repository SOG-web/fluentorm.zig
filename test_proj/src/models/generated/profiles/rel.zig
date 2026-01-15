// AUTO-GENERATED CODE - DO NOT EDIT
// Explicit relation types for full ZLS IntelliSense support

const std = @import("std");
const Row = @import("pg").Row;
const Model = @import("model.zig");
const Users = @import("../users/model.zig");

/// Profiles with user relation loaded
pub const ProfilesWithUsers = struct {
    id: []const u8,
    user_id: []const u8,
    bio: ?[]const u8,
    avatar_url: ?[]const u8,
    website: ?[]const u8,
    location: ?[]const u8,
    date_of_birth: ?i64,
    created_at: i64,
    updated_at: i64,
    user: ?Users = null,

    /// Create from a base Profiles model with relation set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .user_id = model.user_id,
            .bio = model.bio,
            .avatar_url = model.avatar_url,
            .website = model.website,
            .location = model.location,
            .date_of_birth = model.date_of_birth,
            .created_at = model.created_at,
            .updated_at = model.updated_at,
            .user = null,
        };
    }

    /// Extract the base Profiles model (without relation)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .user_id = self.user_id,
            .bio = self.bio,
            .avatar_url = self.avatar_url,
            .website = self.website,
            .location = self.location,
            .date_of_birth = self.date_of_birth,
            .created_at = self.created_at,
            .updated_at = self.updated_at,
        };
    }

    /// Create from a database row, parsing JSONB relation columns.
    /// Use this with query results that include relations via LEFT JOIN.
    pub fn fromRow(row: Row, allocator: std.mem.Allocator) !@This() {
        var result: @This() = undefined;

        // Map base fields
        result.id = row.get([]const u8, "id");
        result.user_id = row.get([]const u8, "user_id");
        result.bio = row.get(?[]const u8, "bio");
        result.avatar_url = row.get(?[]const u8, "avatar_url");
        result.website = row.get(?[]const u8, "website");
        result.location = row.get(?[]const u8, "location");
        result.date_of_birth = row.get(?i64, "date_of_birth");
        result.created_at = row.get(i64, "created_at");
        result.updated_at = row.get(i64, "updated_at");

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

