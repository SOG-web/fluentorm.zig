const std = @import("std");

const pg = @import("pg");

const err = @import("error.zig");
const OrmError = err.OrmError;
const Executor = @import("executor.zig").Executor;
const TableFieldsUnion = @import("registry.zig").TableFieldsUnion;
const Tables = @import("registry.zig").Tables;

pub const JoinClause = struct {
    base_field: TableFieldsUnion,
    join_field: TableFieldsUnion,
    join_operator: Operator,
    join_type: JoinType = .left,
    join_table: Tables,
    predicates: []PredicateClause = &.{},
    select: []const []const u8 = &.{"*"},
    is_many: bool = false,
};

pub const PredicateClause = struct {
    where_type: WhereClauseType,
    sql: []const u8,
};

const jc_exp = JoinClause{
    .base_field = .{ .users = .id },
    .join_type = .inner,
    .join_table = .posts,
    .join_field = .{ .posts = .user_id },
    .join_operator = .eq,
    .predicates = &.{
        .{
            .where_type = .@"and",
            .sql = "posts.is_approved = true",
        },
        .{
            .where_type = .@"or",
            .sql = "posts.title LIKE '%zig%'",
        },
    },
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

pub fn select(self: anytype, fields: anytype) void {
    for (fields) |field| {
        const _field = std.fmt.allocPrint(
            self.arena.allocator(),
            "{s}.{s}",
            .{ self.tablename(), @tagName(field) },
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
    agg: AggregateType,
    field: anytype,
    alias: []const u8,
) void {
    const _field = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s}({s}.{s}) AS {s}",
        .{ agg.toSql(), self.tablename(), @tagName(field), alias },
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

pub fn where(self: anytype, clause: anytype) void {
    const sql = buildWhereClauseSql(self, clause, clause.value) catch return;
    self.where_clauses.append(self.arena.allocator(), .{
        .sql = sql,
        .clause_type = .@"and",
    }) catch return;
}

pub fn orWhere(self: anytype, clause: anytype) void {
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
            "{s}.{s} {s}",
            .{ self.tablename(), @tagName(clause.field), op_str },
        );
    }

    // Handle standard operators
    if (value) |val| {
        const str = switch (val) {
            .boolean => |b| try std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}.{s} {s} {}",
                .{ self.tablename(), @tagName(clause.field), op_str, b },
            ),
            .integer => |i| try std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}.{s} {s} {d}",
                .{ self.tablename(), @tagName(clause.field), op_str, i },
            ),
            .string => |s| try std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}.{s} {s} '{s}'",
                .{ self.tablename(), @tagName(clause.field), op_str, s },
            ),
        };

        return str;
    }

    return "";
}

pub fn whereBetween(
    self: anytype,
    field: anytype,
    low: WhereValue,
    high: WhereValue,
    valueType: InType,
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
        "{s}.{s} BETWEEN {s}",
        .{ self.tablename(), @tagName(field), str },
    ) catch return;
    self.where_clauses.append(self.arena.allocator(), .{
        .sql = sql,
        .clause_type = .@"and",
    }) catch return;
}

pub fn whereNotBetween(
    self: anytype,
    field: anytype,
    low: WhereValue,
    high: WhereValue,
    valueType: InType,
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
        "{s}.{s} NOT BETWEEN {s}",
        .{ self.tablename(), @tagName(field), str },
    ) catch return;
    self.where_clauses.append(self.arena.allocator(), .{
        .sql = sql,
        .clause_type = .@"and",
    }) catch return;
}

pub fn whereIn(self: anytype, field: anytype, values: []const []const u8) void {
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
        "{s}.{s} IN {s}",
        .{ self.tablename(), @tagName(field), values_str.items },
    ) catch return;
    self.where_clauses.append(self.arena.allocator(), .{
        .sql = sql,
        .clause_type = .@"and",
    }) catch return;
}

pub fn whereNotIn(self: anytype, field: anytype, values: []const []const u8) void {
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
        "{s}.{s} NOT IN {s}",
        .{ self.tablename(), @tagName(field), values_str.items },
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

pub fn whereNull(self: anytype, field: anytype) void {
    _ = self.where(.{
        .field = field,
        .operator = .is_null,
    });
}

pub fn whereNotNull(self: anytype, field: anytype) void {
    _ = self.where(.{
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
    field: anytype,
    operator: Operator,
    subquery: []const u8,
) void {
    const sql = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s}.{s} {s} ({s})",
        .{ self.tablename(), @tagName(field), operator.toSql(), subquery },
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

pub fn join(self: anytype, join_clause: JoinClause) void {
    {
        if (@tagName(join_clause.base_field) != self.tablename()) {
            @compileError("Invalid join: base field does not belong to base table");
        }
    }
    self.join_clauses.append(self.arena.allocator(), join_clause) catch return;
}

// SELECT
//   users.*,
//   jsonb_strip_nulls(to_jsonb(wallets)) AS wallet
// FROM users
// LEFT JOIN wallets
//   ON users.id = wallets.user_id
//  AND wallets.is_active = true;
pub fn include(self: anytype, rel: anytype) void {
    self.includes_clauses.append(self.arena.allocator(), rel) catch return;
    // build include sql using inner join
    const include_sql = self.buildIncludeSql(rel) catch return;
    self.join_clauses.append(self.arena.allocator(), include_sql) catch return;
}

pub fn buildIncludeWhere(self: anytype, clause: anytype, table: []const u8, value: ?WhereValue) ![]const u8 {
    const op_str = clause.operator.toSql();

    // Handle IS NULL / IS NOT NULL which don't have a value
    if (clause.operator == .is_null or clause.operator == .is_not_null) {
        return try std.fmt.allocPrint(
            self.arena.allocator(),
            "{s}.{s} {s}",
            .{ table, @tagName(clause.field), op_str },
        );
    }

    // Handle standard operators
    if (value) |val| {
        const str = switch (val) {
            .boolean,
            => |b| try std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}.{s} {s} {}",
                .{ table, @tagName(clause.field), op_str, b },
            ),
            .integer => |i| try std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}.{s} {s} {d}",
                .{ table, @tagName(clause.field), op_str, i },
            ),
            .string => |s| try std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}.{s} {s} '{s}'",
                .{ table, @tagName(clause.field), op_str, s },
            ),
        };

        return str;
    }

    return "";
}

pub fn groupBy(self: anytype, fields: anytype) void {
    for (fields) |field| {
        const _field = std.fmt.allocPrint(
            self.arena.allocator(),
            "{s}.{s}",
            .{ self.tablename(), @tagName(field) },
        ) catch return;
        self.group_clauses.append(self.arena.allocator(), _field) catch return;
    }
}

pub fn groupByRaw(self: anytype, raw_sql: []const u8) !void {
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
    agg: AggregateType,
    field: anytype,
    operator: Operator,
    value: []const u8,
) void {
    const _cond = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s}({s}.{s}) {s} {s}",
        .{ agg.toSql(), self.tablename(), @tagName(field), operator.toSql(), value },
    ) catch return;
    self.having_clauses.append(self.arena.allocator(), _cond) catch return;
}

pub fn orderBy(self: anytype, clause: anytype) void {
    const direction_str = clause.toSql();
    const _clause = std.fmt.allocPrint(
        self.arena.allocator(),
        "{s}.{s} {s}",
        .{ self.tablename(), @tagName(clause.field), direction_str },
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
        "{s}.deleted_at IS NOT NULL",
        .{self.tablename()},
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

pub fn fetchAs(self: anytype, R: type, db: Executor, allocator: std.mem.Allocator, args: anytype) err.Result([]R) {
    const temp_allocator = self.arena.allocator();
    const sql = self.buildSql(temp_allocator) catch |e| {
        return .{ .err = OrmError.fromError(e) };
    };

    const query_result = db.queryOptsWithErr(sql, args, .{
        .column_names = true,
    });
    switch (query_result) {
        .err => |e| return .{ .err = e },
        .ok => |result| {
            defer result.deinit();
            defer result.drain() catch {};

            var items = std.ArrayList(R){};

            var mapper = result.mapper(R, .{ .allocator = allocator });
            while (true) {
                const item = mapper.next() catch |e| {
                    items.deinit(allocator);
                    return .{ .err = OrmError.fromError(e) };
                };
                if (item) |i| {
                    items.append(allocator, i) catch |e| {
                        items.deinit(allocator);
                        return .{ .err = OrmError.fromError(e) };
                    };
                } else break;
            }

            return .{ .ok = items.toOwnedSlice(allocator) catch |e| {
                items.deinit(allocator);
                return .{ .err = OrmError.fromError(e) };
            } };
        },
    }
}

pub fn fetchWithRel(self: anytype, R: type, db: Executor, allocator: std.mem.Allocator, args: anytype) err.Result([]R) {
    const temp_allocator = self.arena.allocator();
    const sql = self.buildSql(temp_allocator) catch |e| {
        return .{ .err = OrmError.fromError(e) };
    };

    const query_result = db.queryOptsWithErr(sql, args, .{
        .column_names = true,
    });
    switch (query_result) {
        .err => |e| return .{ .err = e },
        .ok => |result| {
            defer result.deinit();
            defer result.drain() catch {};

            var items = std.ArrayList(R){};

            while (true) {
                const row = result.next() catch |e| {
                    items.deinit(allocator);
                    return .{ .err = OrmError.fromError(e) };
                };
                if (row) |r| {
                    const item = R.fromRow(r, allocator) catch |e| {
                        items.deinit(allocator);
                        return .{ .err = OrmError.fromError(e) };
                    };
                    items.append(allocator, item) catch |e| {
                        items.deinit(allocator);
                        return .{ .err = OrmError.fromError(e) };
                    };
                } else break;
            }

            return .{ .ok = items.toOwnedSlice(allocator) catch |e| {
                items.deinit(allocator);
                return .{ .err = OrmError.fromError(e) };
            } };
        },
    }
}

pub fn fetchRaw(self: anytype, db: Executor, args: anytype) !pg.Result {
    const temp_allocator = self.arena.allocator();
    const sql = try self.buildSql(temp_allocator);

    return try db.queryOpts(sql, args, .{
        .column_names = true,
    });
}

pub fn firstAs(self: anytype, R: type, db: Executor, allocator: std.mem.Allocator, args: anytype) err.Result(?R) {
    self.limit_val = 1;
    const temp_allocator = self.arena.allocator();
    const sql = self.buildSql(temp_allocator) catch |e| {
        return .{ .err = OrmError.fromError(e) };
    };

    const query_result = db.queryOptsWithErr(sql, args, .{
        .column_names = true,
    });
    switch (query_result) {
        .err => |e| return .{ .err = e },
        .ok => |result| {
            defer result.deinit();
            defer result.drain() catch {};

            var mapper = result.mapper(R, .{ .allocator = allocator });
            const item = mapper.next() catch |e| {
                return .{ .err = OrmError.fromError(e) };
            };
            return .{ .ok = item };
        },
    }
}

pub fn firstWithRel(self: anytype, R: type, db: Executor, allocator: std.mem.Allocator, args: anytype) err.Result(?R) {
    self.limit_val = 1;
    const temp_allocator = self.arena.allocator();
    const sql = self.buildSql(temp_allocator) catch |e| {
        return .{ .err = OrmError.fromError(e) };
    };

    const query_result = db.queryOptsWithErr(sql, args, .{
        .column_names = true,
    });
    switch (query_result) {
        .err => |e| return .{ .err = e },
        .ok => |result| {
            defer result.deinit();
            defer result.drain() catch {};

            const row = result.next() catch |e| {
                return .{ .err = OrmError.fromError(e) };
            };
            if (row) |r| {
                const item = R.fromRow(r, allocator) catch |e| {
                    return .{ .err = OrmError.fromError(e) };
                };
                return .{ .ok = item };
            }
            return .{ .ok = null };
        },
    }
}

pub fn firstRaw(self: anytype, db: Executor, args: anytype) !*pg.Result {
    self.limit_val = 1;
    const temp_allocator = self.arena.allocator();
    const sql = try self.buildSql(temp_allocator);

    // In pool mode, we need to ensure the result releases the connection
    const opts = pg.Conn.QueryOpts{
        .column_names = true,
        .release_conn = db == .pool,
    };

    return try db.queryOpts(sql, args, opts);
}

pub fn delete(self: anytype, db: Executor, args: anytype, Model: type) err.Result(void) {
    const temp_allocator = self.arena.allocator();
    var comp_sql = std.ArrayList(u8){};
    defer comp_sql.deinit(temp_allocator);

    const table_name = Model.tableName();
    comp_sql.writer(temp_allocator).print("DELETE FROM {s}", .{table_name}) catch |e| {
        return .{ .err = OrmError.fromError(e) };
    };

    var first_where = true;
    const has_deleted_at = @hasField(Model, "deleted_at");
    if (has_deleted_at and !self.include_deleted) {
        comp_sql.appendSlice(temp_allocator, " WHERE deleted_at IS NULL") catch |e| {
            return .{ .err = OrmError.fromError(e) };
        };
        first_where = false;
    }

    for (self.where_clauses.items) |clause| {
        if (first_where) {
            comp_sql.appendSlice(temp_allocator, " WHERE ") catch |e| {
                return .{ .err = OrmError.fromError(e) };
            };
            first_where = false;
        } else {
            comp_sql.writer(temp_allocator).print(" {s} ", .{clause.clause_type.toSql()}) catch |e| {
                return .{ .err = OrmError.fromError(e) };
            };
        }
        comp_sql.appendSlice(temp_allocator, clause.sql) catch |e| {
            return .{ .err = OrmError.fromError(e) };
        };
    }

    const result = db.execWithErr(comp_sql.items, args);
    return switch (result) {
        .ok => .{ .ok = {} },
        .err => |e| .{ .err = e },
    };
}

pub fn count(self: anytype, db: Executor, args: anytype, Model: type) err.Result(i64) {
    const temp_allocator = self.arena.allocator();

    var sql = std.ArrayList(u8){};
    defer sql.deinit(temp_allocator);

    const table_name = Model.tableName();
    sql.appendSlice(temp_allocator, "SELECT COUNT(*) FROM ") catch |e| {
        return .{ .err = OrmError.fromError(e) };
    };
    sql.appendSlice(temp_allocator, table_name) catch |e| {
        return .{ .err = OrmError.fromError(e) };
    };

    var first_where = true;
    const has_deleted_at = @hasField(Model, "deleted_at");
    if (has_deleted_at and !self.include_deleted) {
        sql.appendSlice(temp_allocator, " WHERE deleted_at IS NULL") catch |e| {
            return .{ .err = OrmError.fromError(e) };
        };
        first_where = false;
    }

    for (self.where_clauses.items) |clause| {
        if (first_where) {
            sql.appendSlice(temp_allocator, " WHERE ") catch |e| {
                return .{ .err = OrmError.fromError(e) };
            };
            first_where = false;
        } else {
            sql.writer(temp_allocator).print(" {s} ", .{clause.clause_type.toSql()}) catch |e| {
                return .{ .err = OrmError.fromError(e) };
            };
        }
        sql.appendSlice(temp_allocator, clause.sql) catch |e| {
            return .{ .err = OrmError.fromError(e) };
        };
    }

    const row_result = db.rowWithErr(sql.items, args);
    switch (row_result) {
        .err => |e| return .{ .err = e },
        .ok => |maybe_row| {
            var row = maybe_row orelse return .{ .ok = 0 };
            defer row.deinit() catch {};
            return .{ .ok = row.get(i64, 0) };
        },
    }
}

pub fn exists(self: anytype, db: Executor, args: anytype, Model: type) err.Result(bool) {
    _ = Model;
    const count_result = self.count(db, args);
    switch (count_result) {
        .err => |e| return .{ .err = e },
        .ok => |c| return .{ .ok = c > 0 },
    }
}

pub fn pluck(self: anytype, db: Executor, allocator: std.mem.Allocator, field: anytype, args: anytype, Model: type) err.Result([][]const u8) {
    const temp_allocator = self.arena.allocator();

    var sql = std.ArrayList(u8){};
    defer sql.deinit(temp_allocator);

    const table_name = Model.tableName();
    sql.writer(temp_allocator).print("SELECT {s} FROM {s}", .{ @tagName(field), table_name }) catch |e| {
        return .{ .err = OrmError.fromError(e) };
    };

    var first_where = true;
    const has_deleted_at = @hasField(Model, "deleted_at");
    if (has_deleted_at and !self.include_deleted) {
        sql.appendSlice(temp_allocator, " WHERE deleted_at IS NULL") catch |e| {
            return .{ .err = OrmError.fromError(e) };
        };
        first_where = false;
    }

    for (self.where_clauses.items) |clause| {
        if (first_where) {
            sql.appendSlice(temp_allocator, " WHERE ") catch |e| {
                return .{ .err = OrmError.fromError(e) };
            };
            first_where = false;
        } else {
            sql.writer(temp_allocator).print(" {s} ", .{clause.clause_type.toSql()}) catch |e| {
                return .{ .err = OrmError.fromError(e) };
            };
        }
        sql.appendSlice(temp_allocator, clause.sql) catch |e| {
            return .{ .err = OrmError.fromError(e) };
        };
    }

    if (self.limit_val) |l| {
        var buf: [32]u8 = undefined;
        const _limit = std.fmt.bufPrint(&buf, " LIMIT {d}", .{l}) catch |e| {
            return .{ .err = OrmError.fromError(e) };
        };
        sql.appendSlice(temp_allocator, _limit) catch |e| {
            return .{ .err = OrmError.fromError(e) };
        };
    }

    if (self.offset_val) |o| {
        var buf: [32]u8 = undefined;
        const _offset = std.fmt.bufPrint(&buf, " OFFSET {d}", .{o}) catch |e| {
            return .{ .err = OrmError.fromError(e) };
        };
        sql.appendSlice(temp_allocator, _offset) catch |e| {
            return .{ .err = OrmError.fromError(e) };
        };
    }

    const query_result = db.queryOptsWithErr(sql.items, args, .{
        .column_names = true,
    });
    switch (query_result) {
        .err => |e| return .{ .err = e },
        .ok => |result| {
            defer result.deinit();
            defer result.drain() catch {};

            var items = std.ArrayList([]const u8){};

            while (true) {
                const row = result.next() catch |e| {
                    items.deinit(allocator);
                    return .{ .err = OrmError.fromError(e) };
                };
                if (row) |r| {
                    const val = r.get([]const u8, 0);
                    const dupe = allocator.dupe(u8, val) catch |e| {
                        items.deinit(allocator);
                        return .{ .err = OrmError.fromError(e) };
                    };
                    items.append(allocator, dupe) catch |e| {
                        items.deinit(allocator);
                        return .{ .err = OrmError.fromError(e) };
                    };
                } else break;
            }

            return .{ .ok = items.toOwnedSlice(allocator) catch |e| {
                items.deinit(allocator);
                return .{ .err = OrmError.fromError(e) };
            } };
        },
    }
}

pub fn aggregate(self: anytype, db: Executor, agg: AggregateType, field: anytype, args: anytype, Model: type) err.Result(f64) {
    const temp_allocator = self.arena.allocator();

    var sql = std.ArrayList(u8){};
    defer sql.deinit(temp_allocator);

    const table_name = Model.tableName();
    sql.writer(temp_allocator).print("SELECT {s}({s}) FROM {s}", .{
        agg.toSql(),
        @tagName(field),
        table_name,
    }) catch |e| {
        return .{ .err = OrmError.fromError(e) };
    };

    var first_where = true;
    const has_deleted_at = @hasField(Model, "deleted_at");
    if (has_deleted_at and !self.include_deleted) {
        sql.appendSlice(temp_allocator, " WHERE deleted_at IS NULL") catch |e| {
            return .{ .err = OrmError.fromError(e) };
        };
        first_where = false;
    }

    for (self.where_clauses.items) |clause| {
        if (first_where) {
            sql.appendSlice(temp_allocator, " WHERE ") catch |e| {
                return .{ .err = OrmError.fromError(e) };
            };
            first_where = false;
        } else {
            sql.writer(temp_allocator).print(" {s} ", .{clause.clause_type.toSql()}) catch |e| {
                return .{ .err = OrmError.fromError(e) };
            };
        }
        sql.appendSlice(temp_allocator, clause.sql) catch |e| {
            return .{ .err = OrmError.fromError(e) };
        };
    }

    const row_result = db.rowWithErr(sql.items, args);
    switch (row_result) {
        .err => |e| return .{ .err = e },
        .ok => |maybe_row| {
            var row = maybe_row orelse return .{ .ok = 0.0 };
            defer row.deinit() catch {};
            return .{ .ok = row.get(?f64, 0) orelse 0.0 };
        },
    }
}
