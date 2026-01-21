// AUTO-GENERATED CODE - DO NOT EDIT
// Explicit relation types for full ZLS IntelliSense support

const std = @import("std");
const Row = @import("pg").Row;
const Model = @import("model.zig");
const Organizations = @import("../organizations/model.zig");
const Uwsers = @import("../uwsers/model.zig");

/// OrganizationUsers with organization relation loaded
pub const OrganizationUsersWithOrganizations = struct {
    id: []const u8,
    organization_id: []const u8,
    user_id: []const u8,
    status: []const u8,
    role: []const u8,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    organization: ?Organizations = null,

    /// Create from a base OrganizationUsers model with relation set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .organization_id = model.organization_id,
            .user_id = model.user_id,
            .status = model.status,
            .role = model.role,
            .created_at = model.created_at,
            .updated_at = model.updated_at,
            .deleted_at = model.deleted_at,
            .organization = null,
        };
    }

    /// Extract the base OrganizationUsers model (without relation)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .organization_id = self.organization_id,
            .user_id = self.user_id,
            .status = self.status,
            .role = self.role,
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
        result.organization_id = row.getCol([]const u8, "organization_id");
        result.user_id = row.getCol([]const u8, "user_id");
        result.status = row.getCol([]const u8, "status");
        result.role = row.getCol([]const u8, "role");
        result.created_at = row.getCol(i64, "created_at");
        result.updated_at = row.getCol(i64, "updated_at");
        result.deleted_at = row.getCol(?i64, "deleted_at");

        // Parse JSONB relation: organization
        const organization_json = row.getCol(?[]const u8, "organization");
        if (organization_json) |json_str| {
            if (std.json.parseFromSlice(Organizations, allocator, json_str, .{})) |parsed| {
                result.organization = parsed.value;
            } else |_| {
                result.organization = null;
            }
        } else {
            result.organization = null;
        }

        return result;
    }
};

/// OrganizationUsers with user relation loaded
pub const OrganizationUsersWithUwsers = struct {
    id: []const u8,
    organization_id: []const u8,
    user_id: []const u8,
    status: []const u8,
    role: []const u8,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    user: ?Uwsers = null,

    /// Create from a base OrganizationUsers model with relation set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .organization_id = model.organization_id,
            .user_id = model.user_id,
            .status = model.status,
            .role = model.role,
            .created_at = model.created_at,
            .updated_at = model.updated_at,
            .deleted_at = model.deleted_at,
            .user = null,
        };
    }

    /// Extract the base OrganizationUsers model (without relation)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .organization_id = self.organization_id,
            .user_id = self.user_id,
            .status = self.status,
            .role = self.role,
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
        result.organization_id = row.getCol([]const u8, "organization_id");
        result.user_id = row.getCol([]const u8, "user_id");
        result.status = row.getCol([]const u8, "status");
        result.role = row.getCol([]const u8, "role");
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

/// OrganizationUsers with all relations loaded
pub const OrganizationUsersWithAllRelations = struct {
    id: []const u8,
    organization_id: []const u8,
    user_id: []const u8,
    status: []const u8,
    role: []const u8,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    organization: ?Organizations = null,
    user: ?Uwsers = null,

    /// Create from a base OrganizationUsers model with all relations set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .organization_id = model.organization_id,
            .user_id = model.user_id,
            .status = model.status,
            .role = model.role,
            .created_at = model.created_at,
            .updated_at = model.updated_at,
            .deleted_at = model.deleted_at,
            .organization = null,
            .user = null,
        };
    }

    /// Extract the base OrganizationUsers model (without relations)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .organization_id = self.organization_id,
            .user_id = self.user_id,
            .status = self.status,
            .role = self.role,
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
        result.organization_id = row.getCol([]const u8, "organization_id");
        result.user_id = row.getCol([]const u8, "user_id");
        result.status = row.getCol([]const u8, "status");
        result.role = row.getCol([]const u8, "role");
        result.created_at = row.getCol(i64, "created_at");
        result.updated_at = row.getCol(i64, "updated_at");
        result.deleted_at = row.getCol(?i64, "deleted_at");

        // Parse JSONB relations
        const organization_json = row.getCol(?[]const u8, "organization");
        if (organization_json) |json_str| {
            if (std.json.parseFromSlice(Organizations, allocator, json_str, .{})) |parsed| {
                result.organization = parsed.value;
            } else |_| {
                result.organization = null;
            }
        } else {
            result.organization = null;
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
