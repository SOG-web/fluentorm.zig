const std = @import("std");

const pg = @import("pg");

const Executor = @import("executor.zig").Executor;

const Tables = @import("registry.zig").Tables;
const TableFieldsUnion = @import("registry.zig").TableFieldsUnion;

pub const JoinClause = struct {
    base_field: TableFieldsUnion,
    join_field: TableFieldsUnion,
    join_operator: Operator,
    join_type: JoinType = .left,
    join_table: Tables,
};

const jc_exp = JoinClause{
    .base_field = .{ .users = .id },
    .join_type = .inner,
    .join_table = .posts,
    .join_field = .{ .posts = .user_id },
    .join_operator = .eq,
};

pub const Operator = enum {
    eq,
    neq,
    gt,
    gte,
    lt,
    lte,
    like,
    ilike,
    in,
    not_in,
    is_null,
    is_not_null,
    between,
    not_between,

    pub fn toSql(self: Operator) []const u8 {
        return switch (self) {
            .eq => "=",
            .neq => "!=",
            .gt => ">",
            .gte => ">=",
            .lt => "<",
            .lte => "<=",
            .like => "LIKE",
            .ilike => "ILIKE",
            .in => "IN",
            .not_in => "NOT IN",
            .is_null => "IS NULL",
            .is_not_null => "IS NOT NULL",
            .between => "BETWEEN",
            .not_between => "NOT BETWEEN",
        };
    }
};

pub const WhereValue = union(enum) {
    string: []const u8,
    integer: i64,
    boolean: bool,
};

pub const WhereClauseType = enum {
    @"and",
    @"or",

    pub fn toSql(self: WhereClauseType) []const u8 {
        return switch (self) {
            .@"and" => "AND",
            .@"or" => "OR",
        };
    }
};

/// Internal representation of where clauses
pub const WhereClauseInternal = struct {
    sql: []const u8,
    clause_type: WhereClauseType,
};

pub const InType = enum {
    /// Text type for IN clauses
    /// All values will be quoted as strings
    string,
    integer,
    boolean,
};

pub const JoinType = enum {
    inner,
    left,
    right,
    full,

    pub fn toSql(self: JoinType) []const u8 {
        return switch (self) {
            .inner => "INNER JOIN",
            .left => "LEFT JOIN",
            .right => "RIGHT JOIN",
            .full => "FULL OUTER JOIN",
        };
    }
};

pub const AggregateType = enum {
    count,
    sum,
    avg,
    min,
    max,

    pub fn toSql(self: AggregateType) []const u8 {
        return switch (self) {
            .count => "COUNT",
            .sum => "SUM",
            .avg => "AVG",
            .min => "MIN",
            .max => "MAX",
        };
    }
};

pub fn deinit(self: anytype) void {
    self.where_clauses.deinit(self.arena.allocator());
    self.select_clauses.deinit(self.arena.allocator());
    self.order_clauses.deinit(self.arena.allocator());
    self.group_clauses.deinit(self.arena.allocator());
    self.having_clauses.deinit(self.arena.allocator());
    self.join_clauses.deinit(self.arena.allocator());
    self.includes_clauses.deinit(self.arena.allocator());
    self.arena.deinit();
}

pub fn reset(self: anytype) void {
    self.select_clauses.clearAndFree(self.arena.allocator());
    self.where_clauses.clearAndFree(self.arena.allocator());
    self.order_clauses.clearAndFree(self.arena.allocator());
    self.group_clauses.clearAndFree(self.arena.allocator());
    self.having_clauses.clearAndFree(self.arena.allocator());
    self.join_clauses.clearAndFree(self.arena.allocator());
    self.includes_clauses.clearAndFree(self.arena.allocator());
    self.limit_val = null;
    self.offset_val = null;
    self.include_deleted = false;
    self.distinct_enabled = false;
}

pub fn select(self: anytype, comptime fields: anytype) void {
    for (fields) |field| {
        const _field = std.fmt.allocPrint(
            self.arena.allocator(),
            "{s}.{s}",
            .{ self.tablename, @tagName(field.field) },
        ) catch return;
        self.select_clauses.append(self.arena.allocator(), _field) catch return;
    }
}

pub fn distinct(self: anytype) void {
    self.distinct_enabled = true;
}

// TODO: Add support for aliases in return struct
pub fn selectAggregate(
    self: anytype,
    comptime agg: AggregateType,
    comptime field: anytype,
    alias: []const u8,
) void {
    const _field = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s}({s}.{s}) AS {s}",
        .{ agg.toSql(), self.tablename, @tagName(field), alias },
    ) catch return;
    self.select_clauses.append(self.arena.allocator(), _field) catch return;
}

pub fn selectRaw(self: anytype, raw_sql: []const u8) void {
    const _raw = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s}",
        .{raw_sql},
    ) catch return;
    self.select_clauses.append(self.arena.allocator(), _raw) catch return;
}

pub fn where(self: anytype, comptime clause: anytype) void {
    const sql = buildWhereClauseSql(self, clause, clause.value) catch return;
    self.where_clauses.append(self.arena.allocator(), .{
        .sql = sql,
        .clause_type = .@"and",
    }) catch return;
}

pub fn orWhere(self: anytype, comptime clause: anytype) void {
    const sql = buildWhereClauseSql(self, clause, clause.value) catch return;
    self.where_clauses.append(self.arena.allocator(), .{
        .sql = sql,
        .clause_type = .@"or",
    }) catch return;
}

pub fn buildWhereClauseSql(self: anytype, clause: anytype, value: ?WhereValue) ![]const u8 {
    const op_str = clause.operator.toSql();

    // Handle IS NULL / IS NOT NULL which don't have a value
    if (clause.operator == .is_null or clause.operator == .is_not_null) {
        return try std.fmt.allocPrint(
            self.arena.allocator(),
            "{s} {s}",
            .{ @tagName(clause.field), op_str },
        );
    }

    // Handle standard operators
    if (value) |val| {
        const str = switch (val) {
            .boolean, .integer => |b| try std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} {s} {s}",
                .{ @tagName(clause.field), op_str, b },
            ),
            .string => |s| try std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} {s} '{s}'",
                .{ @tagName(clause.field), op_str, s },
            ),
        };

        return str;
    }

    return "";
}

pub fn whereBetween(
    self: anytype,
    comptime field: anytype,
    low: WhereValue,
    high: WhereValue,
    comptime valueType: InType,
) void {
    const str = switch (valueType) {
        .string => std.fmt.allocPrint(
            self.arena.allocator(),
            "'{s}' AND '{s}'",
            .{ low.string, high.string },
        ) catch return,
        .integer => std.fmt.allocPrint(
            self.arena.allocator(),
            "{s} AND {s}",
            .{ low.integer, high.integer },
        ) catch return,
        .boolean => std.fmt.allocPrint(
            self.arena.allocator(),
            "{s} AND {s}",
            .{ low.boolean, high.boolean },
        ) catch return,
    };

    const sql = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s} BETWEEN {s}",
        .{ @tagName(field), str },
    ) catch return;
    self.where_clauses.append(self.arena.allocator(), .{
        .sql = sql,
        .clause_type = .@"and",
    }) catch return;
}

pub fn whereNotBetween(
    self: anytype,
    comptime field: anytype,
    low: WhereValue,
    high: WhereValue,
    comptime valueType: InType,
) void {
    const str = switch (valueType) {
        .string => std.fmt.allocPrint(
            self.arena.allocator(),
            "'{s}' AND '{s}'",
            .{ low.string, high.string },
        ) catch return,
        .integer => std.fmt.allocPrint(
            self.arena.allocator(),
            "{s} AND {s}",
            .{ low.integer, high.integer },
        ) catch return,
        .boolean => std.fmt.allocPrint(
            self.arena.allocator(),
            "{s} AND {s}",
            .{ low.boolean, high.boolean },
        ) catch return,
    };
    const sql = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s} NOT BETWEEN {s}",
        .{ @tagName(field), str },
    ) catch return;
    self.where_clauses.append(self.arena.allocator(), .{
        .sql = sql,
        .clause_type = .@"and",
    }) catch return;
}

pub fn whereIn(self: anytype, comptime field: anytype, values: []const []const u8) void {
    var values_str = std.ArrayList(u8){};
    values_str.appendSlice(self.arena.allocator(), "(") catch return;
    for (values, 0..) |val, i| {
        values_str.append(self.arena.allocator(), '\'') catch return;

        values_str.appendSlice(self.arena.allocator(), val) catch return;

        values_str.append(self.arena.allocator(), '\'') catch return;

        if (i < values.len - 1) {
            values_str.appendSlice(self.arena.allocator(), ", ") catch return;
        }
    }
    values_str.appendSlice(self.arena.allocator(), ")") catch return;

    const sql = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s} IN {s}",
        .{ @tagName(field), values_str.items },
    ) catch return;
    self.where_clauses.append(self.arena.allocator(), .{
        .sql = sql,
        .clause_type = .@"and",
    }) catch return;
}

pub fn whereNotIn(self: anytype, comptime field: anytype, values: []const []const u8) void {
    var values_str = std.ArrayList(u8){};
    values_str.appendSlice(self.arena.allocator(), "(") catch return;
    for (values, 0..) |val, i| {
        values_str.append(self.arena.allocator(), '\'') catch return;
        values_str.appendSlice(self.arena.allocator(), val) catch return;
        values_str.append(self.arena.allocator(), '\'') catch return;

        if (i < values.len - 1) {
            values_str.appendSlice(self.arena.allocator(), ", ") catch return;
        }
    }
    values_str.appendSlice(self.arena.allocator(), ")") catch return;

    const sql = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s} NOT IN {s}",
        .{ @tagName(field), values_str.items },
    ) catch return;
    self.where_clauses.append(self.arena.allocator(), .{
        .sql = sql,
        .clause_type = .@"and",
    }) catch return;
}

pub fn whereRaw(self: anytype, raw_sql: []const u8) void {
    const sql = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s}",
        .{raw_sql},
    ) catch return;
    self.where_clauses.append(self.arena.allocator(), .{
        .sql = sql,
        .clause_type = .@"and",
    }) catch return;
}

pub fn orWhereRaw(self: anytype, raw_sql: []const u8) void {
    const sql = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s}",
        .{raw_sql},
    ) catch return;
    self.where_clauses.append(self.arena.allocator(), .{
        .sql = sql,
        .clause_type = .@"or",
    }) catch return;
}

pub fn whereNull(self: anytype, comptime field: anytype) void {
    self.where(.{
        .field = field,
        .operator = .is_null,
    });
}

pub fn whereNotNull(self: anytype, comptime field: anytype) void {
    self.where(.{
        .field = field,
        .operator = .is_not_null,
    });
}

pub fn whereExists(self: anytype, subquery: []const u8) void {
    const sql = std.fmt.allocPrint(
        self.arena.allocator(),
        "EXISTS ({s})",
        .{subquery},
    ) catch return;
    self.where_clauses.append(self.arena.allocator(), .{
        .sql = sql,
        .clause_type = .@"and",
    }) catch return;
}

pub fn whereNotExists(self: anytype, subquery: []const u8) void {
    const sql = std.fmt.allocPrint(
        self.arena.allocator(),
        "NOT EXISTS ({s})",
        .{subquery},
    ) catch return;
    self.where_clauses.append(self.arena.allocator(), .{
        .sql = sql,
        .clause_type = .@"and",
    }) catch return;
}

pub fn whereSubquery(
    self: anytype,
    comptime field: anytype,
    comptime operator: Operator,
    subquery: []const u8,
) void {
    const sql = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s} {s} ({s})",
        .{ @tagName(field), operator.toSql(), subquery },
    ) catch return;
    self.where_clauses.append(self.arena.allocator(), .{
        .sql = sql,
        .clause_type = .@"and",
    }) catch return;
}

// SELECT
//   users.*,
//   wallets.id AS wallet_id,
//   wallets.cash_balance AS wallet_cash_balance
// FROM users
// LEFT JOIN wallets ON users.id = wallets.user_id;

pub fn join(self: anytype, comptime join_clause: JoinClause) void {
    comptime {
        if (@tagName(join_clause.base_field) != self.tableName) {
            @compileError("Invalid join: base field does not belong to base table");
        }
    }

    // const sql = std.fmt.allocPrint(
    //     self.arena.allocator(),
    //     "{s} {s} ON {s}.{s} {s} {s}.{s}",
    //     .{
    //         join_clause.join_type.toSql(),
    //         @tagName(join_clause.join_table),
    //         @tagName(join_clause.join_field),
    //         join_clause.join_field.toString(),
    //         join_clause.join_operator.toSql(),
    //         @tagName(join_clause.base_field),
    //         join_clause.base_field.toString(),
    //     },
    // ) catch return;
    self.join_clauses.append(self.arena.allocator(), join_clause) catch return;
}

pub fn include(self: anytype, rel: anytype) void {
    self.includes_clauses.append(self.arena.allocator(), rel);
    // build include sql using inner join
    const include_sql = try self.buildIncludeSql(rel);
    self.join_clauses.append(self.arena.allocator(), include_sql);
}

// fn buildIncludeSql(_: *Self, rel: IncludeClauseInput) !JoinClause {
//     const rel_tag = std.meta.activeTag(rel);
//     const relation = Model.getRelation(rel_tag);

//     // Default select: if user didn't specify any base select, keep base columns.
//     // if (self.select_clauses.items.len == 0) {
//     //     const base_star = try std.fmt.allocPrint(allocator, "jsonb_strip_nulls(to_jsonb({s})) AS {s}", .{
//     //         @tagName(relation.foreign_table),
//     //         @tagName(relation.foreign_table),
//     //     });
//     //     self.select_clauses.append(allocator, base_star) catch {};
//     // }

//     // Use LEFT JOIN to ensure we don't filter out comments that have no related record
//     // (e.g. optional relations or soft-deleted parents)
//     return JoinClause{
//         .join_type = JoinType.left,
//         .join_table = relation.foreign_table,
//         .join_field = relation.foreign_key,
//         .join_operator = .eq,
//         .base_field = relation.local_key,
//     };
// }

pub fn buildIncludeWhere(
    allocator: std.mem.Allocator,
    table: []const u8,
    clause: anytype,
    value: ?WhereValue,
) ![]const u8 {
    const op_str = clause.operator.toSql();

    if (clause.operator == .is_null or clause.operator == .is_not_null) {
        return try std.fmt.allocPrint(allocator, "{s}.{s} {s}", .{ table, @tagName(clause.field), op_str });
    }

    if (value) |val| {
        const str = switch (val) {
            .boolean, .integer => |b| try std.fmt.allocPrint(
                allocator,
                "{s}.{s} {s} {s}",
                .{
                    table,
                    @tagName(clause.field),
                    op_str,
                    b,
                },
            ),
            .string => |s| try std.fmt.allocPrint(
                allocator,
                "{s}.{s} {s} '{s}'",
                .{
                    table,
                    @tagName(clause.field),
                    op_str,
                    s,
                },
            ),
        };

        return str;
    }

    return "";
}

pub fn groupBy(self: anytype, comptime fields: anytype) void {
    for (fields) |field| {
        const _field = std.fmt.allocPrint(
            self.arena.allocator(),
            "{s}",
            .{@tagName(field)},
        ) catch return;
        self.group_clauses.append(self.arena.allocator(), _field) catch return;
    }
}

pub fn groupByRaw(self: anytype, raw_sql: []const u8) void {
    const _raw = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s}",
        .{raw_sql},
    ) catch return;
    self.group_clauses.append(self.arena.allocator(), _raw) catch return;
}

pub fn having(self: anytype, condition: []const u8) void {
    const _cond = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s}",
        .{condition},
    ) catch return;
    self.having_clauses.append(self.arena.allocator(), _cond) catch return;
}

pub fn havingAggregate(
    self: anytype,
    comptime agg: AggregateType,
    comptime field: anytype,
    comptime operator: Operator,
    value: []const u8,
) void {
    const _cond = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s}({s}) {s} {s}",
        .{ agg.toSql(), @tagName(field), operator.toSql(), value },
    ) catch return;
    self.having_clauses.append(self.arena.allocator(), _cond) catch return;
}

pub fn orderBy(self: anytype, comptime clause: anytype) void {
    const direction_str = clause.toSql();
    const _clause = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s} {s}",
        .{ @tagName(clause.field), direction_str },
    ) catch return;
    self.order_clauses.append(self.arena.allocator(), _clause) catch return;
}

pub fn orderByRaw(self: anytype, raw_sql: []const u8) void {
    const _raw = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s}",
        .{raw_sql},
    ) catch return;
    self.order_clauses.append(self.arena.allocator(), _raw) catch return;
}

pub fn limit(self: anytype, n: u64) void {
    self.limit_val = n;
}

pub fn offset(self: anytype, n: u64) void {
    self.offset_val = n;
}

pub fn paginate(self: anytype, page: u64, per_page: u64) void {
    const actual_page = if (page == 0) 1 else page;
    self.limit_val = per_page;
    self.offset_val = (actual_page - 1) * per_page;
}

pub fn withDeleted(self: anytype) void {
    self.include_deleted = true;
}

pub fn onlyDeleted(self: anytype) void {
    self.include_deleted = true;
    const sql = std.fmt.allocPrint(
        self.arena.allocator(),
        "deleted_at IS NOT NULL",
        .{},
    ) catch return;
    self.where_clauses.append(self.arena.allocator(), .{
        .sql = sql,
        .clause_type = .@"and",
    }) catch return;
}

pub fn hasCustomProjection(self: anytype) bool {
    // JOINs produce columns from multiple tables - can't map to single model
    if (self.join_clauses.items.len > 0) {
        return true;
    }

    // GROUP BY typically means aggregation - result shape difFieldEnumrs from model
    if (self.group_clauses.items.len > 0) {
        return true;
    }

    // HAVING requires GROUP BY and aggregates
    if (self.having_clauses.items.len > 0) {
        return true;
    }

    // Check select clauses for aggregates, aliases, or raw SQL patterns
    if (self.select_clauses.items.len > 0) {
        return true;
    }

    return false;
}

pub fn fetchAs(self: anytype, comptime R: type, db: Executor, allocator: std.mem.Allocator, args: anytype) ![]R {
    const temp_allocator = self.arena.allocator();
    const sql = try self.buildSql(temp_allocator);

    var result = try db.queryOpts(sql, args, .{
        .column_names = true,
    });
    defer result.deinit();

    var items = std.ArrayList(R){};
    defer items.deinit(allocator);

    var mapper = result.mapper(R, .{ .allocator = allocator });
    while (try mapper.next()) |item| {
        try items.append(allocator, item);
    }
    return items.toOwnedSlice(allocator);
}

pub fn fetchRaw(self: anytype, db: Executor, args: anytype) !pg.Result {
    const temp_allocator = self.arena.allocator();
    const sql = try self.buildSql(temp_allocator);

    return try db.queryOpts(sql, args, .{
        .column_names = true,
    });
}

pub fn firstAs(self: anytype, comptime R: type, db: Executor, allocator: std.mem.Allocator, args: anytype) !?R {
    self.limit_val = 1;
    const temp_allocator = self.arena.allocator();
    const sql = try self.buildSql(temp_allocator);

    var result = try db.queryOpts(sql, args, .{
        .column_names = true,
    });
    defer result.deinit();

    var mapper = result.mapper(R, .{ .allocator = allocator });
    if (try mapper.next()) |item| {
        return item;
    }
    return null;
}

pub fn firstRaw(self: anytype, db: Executor, args: anytype) !?pg.Result {
    self.limit_val = 1;
    const temp_allocator = self.arena.allocator();
    const sql = try self.buildSql(temp_allocator);

    var result = try db.queryOpts(sql, args, .{
        .column_names = true,
    });
    defer result.deinit();
    // Check if there's at least one row
    if (try result.next()) |_| {
        return try db.queryOpts(sql, args, .{
            .column_names = true,
        });
    }

    return null;
}

pub fn delete(self: anytype, db: Executor, args: anytype, comptime Model: type) !void {
    const temp_allocator = self.arena.allocator();
    var comp_sql = std.ArrayList(u8){};
    defer comp_sql.deinit(temp_allocator);

    const table_name = Model.tableName();
    try comp_sql.writer(temp_allocator).print("DELETE FROM {s}", .{table_name});

    var first_where = true;
    // Handle soft deletes
    const has_deleted_at = @hasField(Model, "deleted_at");
    if (has_deleted_at and !self.include_deleted) {
        try comp_sql.appendSlice(temp_allocator, " WHERE deleted_at IS NULL");
        first_where = false;
    }

    for (self.where_clauses.items) |clause| {
        if (first_where) {
            try comp_sql.appendSlice(temp_allocator, " WHERE ");
            first_where = false;
        } else {
            try comp_sql.writer(temp_allocator).print(" {s} ", .{clause.clause_type.toSql()});
        }
        try comp_sql.appendSlice(temp_allocator, clause.sql);
    }

    var result = try db.query(comp_sql.items, args);
    defer result.deinit();
}

pub fn count(self: anytype, db: Executor, args: anytype, comptime Model: type) !i64 {
    const temp_allocator = self.arena.allocator();

    var sql = std.ArrayList(u8){};
    defer sql.deinit(temp_allocator);

    const table_name = Model.tableName();
    try sql.appendSlice(temp_allocator, "SELECT COUNT(*) FROM ");
    try sql.appendSlice(temp_allocator, table_name);

    // JOIN clauses
    for (self.join_clauses.items) |join_sql| {
        try sql.appendSlice(temp_allocator, " ");
        try sql.appendSlice(temp_allocator, join_sql);
    }

    var first_where = true;
    const has_deleted_at = @hasField(Model, "deleted_at");
    if (has_deleted_at and !self.include_deleted) {
        try sql.appendSlice(temp_allocator, " WHERE deleted_at IS NULL");
        first_where = false;
    }

    for (self.where_clauses.items) |clause| {
        if (first_where) {
            try sql.appendSlice(temp_allocator, " WHERE ");
            first_where = false;
        } else {
            try sql.writer(temp_allocator).print(" {s} ", .{clause.clause_type.toSql()});
        }
        try sql.appendSlice(temp_allocator, clause.sql);
    }

    var result = try db.queryOpts(sql.items, args, .{
        .column_names = true,
    });
    defer result.deinit();

    if (try result.next()) |row| {
        return row.get(i64, 0);
    }
    return 0;
}

pub fn exists(self: anytype, db: Executor, args: anytype, comptime Model: type) !bool {
    const c = try self.count(db, args, Model);
    return c > 0;
}

pub fn pluck(self: anytype, db: Executor, allocator: std.mem.Allocator, comptime field: anytype, args: anytype, comptime Model: type) ![][]const u8 {
    const temp_allocator = self.arena.allocator();

    var sql = std.ArrayList(u8){};
    defer sql.deinit(temp_allocator);

    const table_name = Model.tableName();
    try sql.writer(temp_allocator).print("SELECT {s} FROM {s}", .{ @tagName(field), table_name });

    var first_where = true;
    const has_deleted_at = @hasField(Model, "deleted_at");
    if (has_deleted_at and !self.include_deleted) {
        try sql.appendSlice(temp_allocator, " WHERE deleted_at IS NULL");
        first_where = false;
    }

    for (self.where_clauses.items) |clause| {
        if (first_where) {
            try sql.appendSlice(temp_allocator, " WHERE ");
            first_where = false;
        } else {
            try sql.writer(temp_allocator).print(" {s} ", .{clause.clause_type.toSql()});
        }
        try sql.appendSlice(temp_allocator, clause.sql);
    }

    if (self.limit_val) |l| {
        var buf: [32]u8 = undefined;
        const _limit = try std.fmt.bufPrint(&buf, " LIMIT {d}", .{l});
        try sql.appendSlice(temp_allocator, _limit);
    }

    if (self.offset_val) |o| {
        var buf: [32]u8 = undefined;
        const _offset = try std.fmt.bufPrint(&buf, " OFFSET {d}", .{o});
        try sql.appendSlice(temp_allocator, _offset);
    }

    var result = try db.queryOpts(sql.items, args, .{
        .column_names = true,
    });
    defer result.deinit();

    var items = std.ArrayList([]const u8){};
    errdefer items.deinit(allocator);

    while (try result.next()) |row| {
        const val = row.get([]const u8, 0);
        const dupe = try allocator.dupe(u8, val);
        try items.append(allocator, dupe);
    }

    return items.toOwnedSlice(allocator);
}

pub fn aggregate(self: anytype, db: Executor, comptime agg: AggregateType, comptime field: anytype, args: anytype, comptime Model: type) !f64 {
    // comptime {
    //     if (agg != .count and !isNumericField(Model, field)) {
    //         @compileError("Aggregate requires numeric field");
    //     }
    // }

    const temp_allocator = self.arena.allocator();

    var sql = std.ArrayList(u8){};
    defer sql.deinit(temp_allocator);

    const table_name = Model.tableName();
    try sql.writer(temp_allocator).print("SELECT {s}({s}) FROM {s}", .{
        agg.toSql(),
        @tagName(field),
        table_name,
    });

    var first_where = true;
    const has_deleted_at = @hasField(Model, "deleted_at");
    if (has_deleted_at and !self.include_deleted) {
        try sql.appendSlice(temp_allocator, " WHERE deleted_at IS NULL");
        first_where = false;
    }

    for (self.where_clauses.items) |clause| {
        if (first_where) {
            try sql.appendSlice(temp_allocator, " WHERE ");
            first_where = false;
        } else {
            try sql.writer(temp_allocator).print(" {s} ", .{clause.clause_type.toSql()});
        }
        try sql.appendSlice(temp_allocator, clause.sql);
    }

    var result = try db.queryOpts(sql.items, args, .{
        .column_names = true,
    });
    defer result.deinit();

    if (try result.next()) |row| {
        return row.get(?f64, 0) orelse 0.0;
    }
    return 0.0;
}
