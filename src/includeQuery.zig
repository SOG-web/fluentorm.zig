const std = @import("std");

const pg = @import("pg");

const Executor = @import("executor.zig").Executor;

/// RelationMeta describes a relationship for include queries
pub const RelationMeta = struct {
    /// Name of the relation field (e.g., "posts")
    name: []const u8,
    /// The related table name (e.g., "posts")
    table: []const u8,
    /// The foreign key column in the related table (e.g., "user_id")
    foreign_key: []const u8,
    /// The local key (usually "id")
    local_key: []const u8,
    /// Type of relationship
    relation_type: RelationType,

    pub const RelationType = enum {
        has_many, // One user has many posts
        has_one, // One user has one profile
        belongs_to, // One post belongs to one user
    };
};

/// IncludeOptions for customizing relation loading
pub fn IncludeOptions(comptime RelatedFieldEnum: type) type {
    return struct {
        /// Select specific fields from the relation
        select: ?[]const RelatedFieldEnum = null,
        /// Limit number of related records
        limit: ?u32 = null,
        /// Order by clause for relation
        order_by: ?[]const u8 = null,
        /// Where clause for relation (raw SQL)
        where: ?[]const u8 = null,
    };
}

/// Result of a query with includes - parent record with loaded relations
pub fn WithRelation(comptime Parent: type, comptime Relation: type, comptime field_name: []const u8) type {
    _ = field_name; // Used for naming in the struct
    return struct {
        parent: Parent,
        relations: []Relation,

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            for (self.relations) |*r| {
                if (@hasDecl(Relation, "deinit")) {
                    r.deinit(allocator);
                }
            }
            allocator.free(self.relations);
            if (@hasDecl(Parent, "deinit")) {
                var p = self.parent;
                p.deinit(allocator);
            }
        }
    };
}

/// Execute an include query - loads parent and related records using LEFT JOIN
/// Returns array of parents, each with their related records
pub fn executeIncludeQuery(
    comptime Parent: type,
    comptime Relation: type,
    comptime relation_meta: RelationMeta,
    db: Executor,
    allocator: std.mem.Allocator,
    parent_where: ?[]const u8,
    args: anytype,
) ![]WithRelation(Parent, Relation, relation_meta.name) {
    const Result = WithRelation(Parent, Relation, relation_meta.name);

    // Build the JOIN query
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp_alloc = arena.allocator();

    const parent_table = Parent.tableName();

    // Build SQL with LEFT JOIN
    var sql = std.ArrayList(u8){};
    defer sql.deinit(temp_alloc);

    // Select parent fields with table prefix
    try sql.appendSlice(temp_alloc, "SELECT ");

    // Get parent field names from the type info
    const parent_fields = @typeInfo(Parent).@"struct".fields;
    inline for (parent_fields, 0..) |field, i| {
        if (i > 0) try sql.appendSlice(temp_alloc, ", ");
        try sql.writer(temp_alloc).print("{s}.{s}", .{ parent_table, field.name });
    }

    // Select relation fields with aliases
    const relation_fields = @typeInfo(Relation).@"struct".fields;
    inline for (relation_fields) |field| {
        try sql.appendSlice(temp_alloc, ", ");
        try sql.writer(temp_alloc).print("{s}.{s} AS {s}__{s}", .{
            relation_meta.table,
            field.name,
            relation_meta.name,
            field.name,
        });
    }

    try sql.appendSlice(temp_alloc, " FROM ");
    try sql.appendSlice(temp_alloc, parent_table);

    // LEFT JOIN for relations
    try sql.writer(temp_alloc).print(" LEFT JOIN {s} ON {s}.{s} = {s}.{s}", .{
        relation_meta.table,
        relation_meta.table,
        relation_meta.foreign_key,
        parent_table,
        relation_meta.local_key,
    });

    // Add where clause if provided
    if (parent_where) |w| {
        try sql.appendSlice(temp_alloc, " WHERE ");
        try sql.appendSlice(temp_alloc, w);
    }

    // Order by parent ID to group relations together
    try sql.writer(temp_alloc).print(" ORDER BY {s}.{s}", .{ parent_table, relation_meta.local_key });

    // Execute query
    var result = try db.queryOpts(sql.items, args, .{ .column_names = true });
    defer result.deinit();

    // Parse results - group by parent ID
    var results = std.ArrayList(Result){};
    errdefer {
        for (results.items) |*r| r.deinit(allocator);
        results.deinit(allocator);
    }

    var current_parent_id: ?[]const u8 = null;
    var current_relations = std.ArrayList(Relation){};
    defer current_relations.deinit(allocator);

    var current_parent: ?Parent = null;

    while (try result.next()) |row| {
        // Get parent ID from first column (assumed to be 'id')
        const parent_id = row.get([]const u8, 0);

        // Check if this is a new parent
        const is_new_parent = if (current_parent_id) |cid|
            !std.mem.eql(u8, cid, parent_id)
        else
            true;

        if (is_new_parent) {
            // Save previous parent if exists
            if (current_parent) |p| {
                const owned_id = try allocator.dupe(u8, current_parent_id.?);
                _ = owned_id;
                try results.append(allocator, Result{
                    .parent = p,
                    .relations = try current_relations.toOwnedSlice(allocator),
                });
                current_relations = std.ArrayList(Relation){};
            }

            // Parse new parent from row
            current_parent = try row.to(Parent, .{ .allocator = allocator, .map = .name });
            current_parent_id = try allocator.dupe(u8, parent_id);
        }

        // Parse relation from aliased columns (if not null)
        // Check if relation exists by checking first relation column
        const relation_first_col_idx = parent_fields.len;
        const first_relation_val = row.get(?[]const u8, relation_first_col_idx);

        if (first_relation_val != null) {
            // Parse relation - needs custom parsing for aliased columns
            // For now, we'll use a simpler approach with ordinal after the parent fields
            var rel: Relation = undefined;
            inline for (relation_fields, 0..) |field, i| {
                const col_idx = parent_fields.len + i;
                @field(rel, field.name) = row.get(field.type, col_idx);
            }
            try current_relations.append(allocator, rel);
        }
    }

    // Don't forget the last parent
    if (current_parent) |p| {
        try results.append(allocator, Result{
            .parent = p,
            .relations = try current_relations.toOwnedSlice(allocator),
        });
    }

    return try results.toOwnedSlice(allocator);
}

/// Convenience function to execute include with first result only
pub fn executeIncludeQueryFirst(
    comptime Parent: type,
    comptime Relation: type,
    comptime relation_meta: RelationMeta,
    db: Executor,
    allocator: std.mem.Allocator,
    parent_where: ?[]const u8,
    args: anytype,
) !?WithRelation(Parent, Relation, relation_meta.name) {
    const results = try executeIncludeQuery(
        Parent,
        Relation,
        relation_meta,
        db,
        allocator,
        parent_where,
        args,
    );

    if (results.len == 0) {
        allocator.free(results);
        return null;
    }

    // Free extra results if any
    for (results[1..]) |*r| {
        r.deinit(allocator);
    }

    const first = results[0];
    allocator.free(results);
    return first;
}
