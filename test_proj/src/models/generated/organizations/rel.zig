// AUTO-GENERATED CODE - DO NOT EDIT
// Explicit relation types for full ZLS IntelliSense support

const std = @import("std");
const Row = @import("pg").Row;
const Model = @import("model.zig");
const OrganizationUsers = @import("../organization_users/model.zig");

/// Organizations with users relation loaded
pub const OrganizationsWithOrganizationUsers = struct {
    id: []const u8,
    name: []const u8,
    email: []const u8,
    phone: []const u8,
    address: []const u8,
    website: []const u8,
    industry: []const u8,
    business_registration_number: ?[]const u8,
    tax_id: ?[]const u8,
    verification_status: ?[]const u8,
    verification_documents: ?[]const u8,
    required_documents: ?[]const u8,
    uploaded_documents: ?[]const u8,
    onboarding_status: ?[]const u8,
    subscription_plan: []const u8,
    billing_email: ?[]const u8,
    status: []const u8,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    users: ?[]OrganizationUsers = null,

    /// Create from a base Organizations model with relation set to null
    pub fn fromBase(model: Model) @This() {
        return .{
            .id = model.id,
            .name = model.name,
            .email = model.email,
            .phone = model.phone,
            .address = model.address,
            .website = model.website,
            .industry = model.industry,
            .business_registration_number = model.business_registration_number,
            .tax_id = model.tax_id,
            .verification_status = model.verification_status,
            .verification_documents = model.verification_documents,
            .required_documents = model.required_documents,
            .uploaded_documents = model.uploaded_documents,
            .onboarding_status = model.onboarding_status,
            .subscription_plan = model.subscription_plan,
            .billing_email = model.billing_email,
            .status = model.status,
            .created_at = model.created_at,
            .updated_at = model.updated_at,
            .deleted_at = model.deleted_at,
            .users = null,
        };
    }

    /// Extract the base Organizations model (without relation)
    pub fn toBase(self: @This()) Model {
        return .{
            .id = self.id,
            .name = self.name,
            .email = self.email,
            .phone = self.phone,
            .address = self.address,
            .website = self.website,
            .industry = self.industry,
            .business_registration_number = self.business_registration_number,
            .tax_id = self.tax_id,
            .verification_status = self.verification_status,
            .verification_documents = self.verification_documents,
            .required_documents = self.required_documents,
            .uploaded_documents = self.uploaded_documents,
            .onboarding_status = self.onboarding_status,
            .subscription_plan = self.subscription_plan,
            .billing_email = self.billing_email,
            .status = self.status,
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
        result.name = row.getCol([]const u8, "name");
        result.email = row.getCol([]const u8, "email");
        result.phone = row.getCol([]const u8, "phone");
        result.address = row.getCol([]const u8, "address");
        result.website = row.getCol([]const u8, "website");
        result.industry = row.getCol([]const u8, "industry");
        result.business_registration_number = row.getCol(?[]const u8, "business_registration_number");
        result.tax_id = row.getCol(?[]const u8, "tax_id");
        result.verification_status = row.getCol(?[]const u8, "verification_status");
        result.verification_documents = row.getCol(?[]const u8, "verification_documents");
        result.required_documents = row.getCol(?[]const u8, "required_documents");
        result.uploaded_documents = row.getCol(?[]const u8, "uploaded_documents");
        result.onboarding_status = row.getCol(?[]const u8, "onboarding_status");
        result.subscription_plan = row.getCol([]const u8, "subscription_plan");
        result.billing_email = row.getCol(?[]const u8, "billing_email");
        result.status = row.getCol([]const u8, "status");
        result.created_at = row.getCol(i64, "created_at");
        result.updated_at = row.getCol(i64, "updated_at");
        result.deleted_at = row.getCol(?i64, "deleted_at");

        // Parse JSONB relation: users
        const users_json = row.getCol(?[]const u8, "users");
        if (users_json) |json_str| {
            if (std.json.parseFromSlice([]OrganizationUsers, allocator, json_str, .{})) |parsed| {
                result.users = parsed.value;
            } else |_| {
                result.users = null;
            }
        } else {
            result.users = null;
        }

        return result;
    }
};

