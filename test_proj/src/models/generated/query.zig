const std = @import("std");

const pg = @import("pg");

const Executor = @import("executor.zig").Executor;

/// Query builder for BaseModel operations
pub fn QueryBuilder(comptime T: type, comptime K: type, comptime FE: type) type {
    _ = K;
    if (!@hasDecl(T, "tableName")) {
        @compileError("Struct must have a tableName field");
    }
    return struct {
        arena: std.heap.ArenaAllocator,
        select_clauses: std.ArrayList([]const u8),
        where_clauses: std.ArrayList(WhereClauseInternal),
        order_clauses: std.ArrayList([]const u8),
        group_clauses: std.ArrayList([]const u8),
        having_clauses: std.ArrayList([]const u8),
        join_clauses: std.ArrayList([]const u8),
        limit_val: ?u64 = null,
        offset_val: ?u64 = null,
        include_deleted: bool = false,
        distinct_enabled: bool = false,

        const Self = @This();

        /// Internal representation of where clauses
        const WhereClauseInternal = struct {
            sql: []const u8,
            clause_type: WhereClauseType,
        };

        /// Enum of field names for the model.
        pub const Field = FE;

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

        pub const WhereClause = struct {
            field: Field,
            operator: Operator,
            value: ?[]const u8 = null,
        };

        pub const InType = enum {
            /// Text type for IN clauses
            /// All values will be quoted as strings
            string,
            integer,
            boolean,
        };

        pub const OrderByClause = struct {
            field: Field,
            direction: enum {
                asc,
                desc,
            },

            pub fn toSql(self: OrderByClause) []const u8 {
                return switch (self.direction) {
                    .asc => "ASC",
                    .desc => "DESC",
                };
            }
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

        pub const SelectField = []const Field;

        pub fn init() Self {
            return Self{
                .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
                .where_clauses = std.ArrayList(WhereClauseInternal){},
                .select_clauses = std.ArrayList([]const u8){},
                .order_clauses = std.ArrayList([]const u8){},
                .group_clauses = std.ArrayList([]const u8){},
                .having_clauses = std.ArrayList([]const u8){},
                .join_clauses = std.ArrayList([]const u8){},
            };
        }

        pub fn deinit(self: *Self) void {
            self.where_clauses.deinit(self.arena.allocator());
            self.select_clauses.deinit(self.arena.allocator());
            self.order_clauses.deinit(self.arena.allocator());
            self.group_clauses.deinit(self.arena.allocator());
            self.having_clauses.deinit(self.arena.allocator());
            self.join_clauses.deinit(self.arena.allocator());
            self.arena.deinit();
        }

        /// Reset the query - clear all clauses, this makes the query builder reusable
        ///
        /// Example:
        /// ```zig
        /// .reset()
        /// ```
        pub fn reset(self: *Self) void {
            self.where_clauses.clearAndFree(self.arena.allocator());
            self.select_clauses.clearAndFree(self.arena.allocator());
            self.order_clauses.clearAndFree(self.arena.allocator());
            self.group_clauses.clearAndFree(self.arena.allocator());
            self.having_clauses.clearAndFree(self.arena.allocator());
            self.join_clauses.clearAndFree(self.arena.allocator());
            self.limit_val = null;
            self.offset_val = null;
            self.include_deleted = false;
            self.distinct_enabled = false;
        }

        /// Add a SELECT clause
        ///
        /// Example:
        /// ```zig
        /// .select(&.{ .id, .name })
        /// ```
        pub fn select(self: *Self, fields: []const FE) *Self {
            for (fields) |field| {
                const _field = std.fmt.allocPrint(
                    self.arena.allocator(),
                    "{s}",
                    .{@tagName(field)},
                ) catch return self;
                self.select_clauses.append(self.arena.allocator(), _field) catch return self;
            }
            return self;
        }

        /// Enable DISTINCT on the query
        ///
        /// Example:
        /// ```zig
        /// .distinct().select(&.{ .email })
        /// ```
        pub fn distinct(self: *Self) *Self {
            self.distinct_enabled = true;
            return self;
        }

        /// Select with an aggregate function
        ///
        /// Example:
        /// ```zig
        /// .selectAggregate(.sum, .amount, "total_amount")
        /// ```
        pub fn selectAggregate(self: *Self, agg: AggregateType, field: FE, alias: []const u8) *Self {
            const _field = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}({s}) AS {s}",
                .{ agg.toSql(), @tagName(field), alias },
            ) catch return self;
            self.select_clauses.append(self.arena.allocator(), _field) catch return self;
            return self;
        }

        /// Select raw SQL expression
        ///
        /// Example:
        /// ```zig
        /// .selectRaw("COUNT(*) AS total")
        /// ```
        pub fn selectRaw(self: *Self, raw_sql: []const u8) *Self {
            const _raw = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}",
                .{raw_sql},
            ) catch return self;
            self.select_clauses.append(self.arena.allocator(), _raw) catch return self;
            return self;
        }

        /// Add a WHERE clause. Multiple calls are ANDed together.
        ///
        /// Example:
        /// ```zig
        /// .where(.{ .field = .age, .operator = .gt, .value = "$1" })
        /// ```
        pub fn where(self: *Self, clause: WhereClause) *Self {
            const sql = self.buildWhereClauseSql(clause) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add an OR WHERE clause.
        ///
        /// Example:
        /// ```zig
        /// .orWhere(.{ .field = .age, .operator = .gt, .value = "$1" })
        /// ```
        pub fn orWhere(self: *Self, clause: WhereClause) *Self {
            const sql = self.buildWhereClauseSql(clause) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"or",
            }) catch return self;
            return self;
        }

        fn buildWhereClauseSql(self: *Self, clause: WhereClause) ![]const u8 {
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
            if (clause.value) |val| {
                return try std.fmt.allocPrint(
                    self.arena.allocator(),
                    "{s} {s} {s}",
                    .{ @tagName(clause.field), op_str, val },
                );
            }

            return "";
        }

        /// Add a BETWEEN clause
        ///
        /// Example:
        /// ```zig
        /// .whereBetween(.age, "$1", "$2")
        /// ```
        pub fn whereBetween(self: *Self, field: FE, low: []const u8, high: []const u8, valueType: InType) *Self {
            const str = switch (valueType) {
                .string => std.fmt.allocPrint(
                    self.arena.allocator(),
                    "'{s}' AND '{s}'",
                    .{ low, high },
                ) catch return self,
                .integer => std.fmt.allocPrint(
                    self.arena.allocator(),
                    "{s} AND {s}",
                    .{ low, high },
                ) catch return self,
                .boolean => std.fmt.allocPrint(
                    self.arena.allocator(),
                    "{s} AND {s}",
                    .{ low, high },
                ) catch return self,
            };

            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} BETWEEN {s}",
                .{ @tagName(field), str },
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add a NOT BETWEEN clause
        ///
        /// Example:
        /// ```zig
        /// .whereNotBetween(.age, "$1", "$2")
        /// ```
        pub fn whereNotBetween(self: *Self, field: FE, low: []const u8, high: []const u8, valueType: InType) *Self {
            const str = switch (valueType) {
                .string => std.fmt.allocPrint(
                    self.arena.allocator(),
                    "'{s}' AND '{s}'",
                    .{ low, high },
                ) catch return self,
                .integer => std.fmt.allocPrint(
                    self.arena.allocator(),
                    "{s} AND {s}",
                    .{ low, high },
                ) catch return self,
                .boolean => std.fmt.allocPrint(
                    self.arena.allocator(),
                    "{s} AND {s}",
                    .{ low, high },
                ) catch return self,
            };
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} NOT BETWEEN {s}",
                .{ @tagName(field), str },
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add a WHERE IN clause with values
        ///
        /// Example:
        /// ```zig
        /// .whereIn(.status, &.{ "'active'", "'pending'" })
        /// ```
        pub fn whereIn(self: *Self, field: FE, values: []const []const u8, valueType: InType) *Self {
            var values_str = std.ArrayList(u8){};
            values_str.appendSlice(self.arena.allocator(), "(") catch return self;
            for (values, 0..) |val, i| {
                switch (valueType) {
                    .string => {
                        values_str.append(self.arena.allocator(), '\'') catch return self;
                    },
                    .integer => {},
                    .boolean => {},
                }
                values_str.appendSlice(self.arena.allocator(), val) catch return self;
                switch (valueType) {
                    .string => {
                        values_str.append(self.arena.allocator(), '\'') catch return self;
                    },
                    .integer => {},
                    .boolean => {},
                }
                if (i < values.len - 1) {
                    values_str.appendSlice(self.arena.allocator(), ", ") catch return self;
                }
            }
            values_str.appendSlice(self.arena.allocator(), ")") catch return self;

            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} IN {s}",
                .{ @tagName(field), values_str.items },
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add a WHERE NOT IN clause with values
        ///
        /// Example:
        /// ```zig
        /// .whereNotIn(.status, &.{ "'deleted'", "'archived'" })
        /// ```
        pub fn whereNotIn(self: *Self, field: FE, values: []const []const u8, valueType: InType) *Self {
            var values_str = std.ArrayList(u8){};
            values_str.appendSlice(self.arena.allocator(), "(") catch return self;
            for (values, 0..) |val, i| {
                switch (valueType) {
                    .string => {
                        values_str.append(self.arena.allocator(), '\'') catch return self;
                    },
                    .integer => {},
                    .boolean => {},
                }
                values_str.appendSlice(self.arena.allocator(), val) catch return self;
                switch (valueType) {
                    .string => {
                        values_str.append(self.arena.allocator(), '\'') catch return self;
                    },
                    .integer => {},
                    .boolean => {},
                }
                if (i < values.len - 1) {
                    values_str.appendSlice(self.arena.allocator(), ", ") catch return self;
                }
            }
            values_str.appendSlice(self.arena.allocator(), ")") catch return self;

            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} NOT IN {s}",
                .{ @tagName(field), values_str.items },
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add a raw WHERE clause
        ///
        /// Example:
        /// ```zig
        /// .whereRaw("age > $1 AND age < $2")
        /// ```
        pub fn whereRaw(self: *Self, raw_sql: []const u8) *Self {
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}",
                .{raw_sql},
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add an OR raw WHERE clause
        ///
        /// Example:
        /// ```zig
        /// .orWhereRaw("status = 'vip' OR role = 'admin'")
        /// ```
        pub fn orWhereRaw(self: *Self, raw_sql: []const u8) *Self {
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}",
                .{raw_sql},
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"or",
            }) catch return self;
            return self;
        }

        /// Add a WHERE NULL clause
        ///
        /// Example:
        /// ```zig
        /// .whereNull(.deleted_at)
        /// ```
        pub fn whereNull(self: *Self, field: FE) *Self {
            return self.where(.{
                .field = field,
                .operator = .is_null,
            });
        }

        /// Add a WHERE NOT NULL clause
        ///
        /// Example:
        /// ```zig
        /// .whereNotNull(.email_verified_at)
        /// ```
        pub fn whereNotNull(self: *Self, field: FE) *Self {
            return self.where(.{
                .field = field,
                .operator = .is_not_null,
            });
        }

        /// Add a WHERE EXISTS subquery
        ///
        /// Example:
        /// ```zig
        /// .whereExists("SELECT 1 FROM orders WHERE orders.user_id = users.id")
        /// ```
        pub fn whereExists(self: *Self, subquery: []const u8) *Self {
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "EXISTS ({s})",
                .{subquery},
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add a WHERE NOT EXISTS subquery
        ///
        /// Example:
        /// ```zig
        /// .whereNotExists("SELECT 1 FROM bans WHERE bans.user_id = users.id")
        /// ```
        pub fn whereNotExists(self: *Self, subquery: []const u8) *Self {
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "NOT EXISTS ({s})",
                .{subquery},
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add a subquery in WHERE clause
        ///
        /// Example:
        /// ```zig
        /// .whereSubquery(.id, .in, "SELECT user_id FROM premium_users")
        /// ```
        pub fn whereSubquery(self: *Self, field: FE, operator: Operator, subquery: []const u8) *Self {
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} {s} ({s})",
                .{ @tagName(field), operator.toSql(), subquery },
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        /// Add a JOIN clause
        ///
        /// Example:
        /// ```zig
        /// .join(.inner, "posts", "users.id = posts.user_id")
        /// ```
        pub fn join(self: *Self, join_type: JoinType, table: []const u8, on_clause: []const u8) *Self {
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} {s} ON {s}",
                .{ join_type.toSql(), table, on_clause },
            ) catch return self;
            self.join_clauses.append(self.arena.allocator(), sql) catch return self;
            return self;
        }

        /// Add an INNER JOIN clause
        ///
        /// Example:
        /// ```zig
        /// .innerJoin("posts", "users.id = posts.user_id")
        /// ```
        pub fn innerJoin(self: *Self, table: []const u8, on_clause: []const u8) *Self {
            return self.join(.inner, table, on_clause);
        }

        /// Add a LEFT JOIN clause
        ///
        /// Example:
        /// ```zig
        /// .leftJoin("posts", "users.id = posts.user_id")
        /// ```
        pub fn leftJoin(self: *Self, table: []const u8, on_clause: []const u8) *Self {
            return self.join(.left, table, on_clause);
        }

        /// Add a RIGHT JOIN clause
        ///
        /// Example:
        /// ```zig
        /// .rightJoin("posts", "users.id = posts.user_id")
        /// ```
        pub fn rightJoin(self: *Self, table: []const u8, on_clause: []const u8) *Self {
            return self.join(.right, table, on_clause);
        }

        /// Add a FULL OUTER JOIN clause
        ///
        /// Example:
        /// ```zig
        /// .fullJoin("posts", "users.id = posts.user_id")
        /// ```
        pub fn fullJoin(self: *Self, table: []const u8, on_clause: []const u8) *Self {
            return self.join(.full, table, on_clause);
        }

        /// Add GROUP BY clause
        ///
        /// Example:
        /// ```zig
        /// .groupBy(&.{ .status, .role })
        /// ```
        pub fn groupBy(self: *Self, fields: []const FE) *Self {
            for (fields) |field| {
                const _field = std.fmt.allocPrint(
                    self.arena.allocator(),
                    "{s}",
                    .{@tagName(field)},
                ) catch return self;
                self.group_clauses.append(self.arena.allocator(), _field) catch return self;
            }
            return self;
        }

        /// Add GROUP BY with raw SQL
        ///
        /// Example:
        /// ```zig
        /// .groupByRaw("DATE(created_at)")
        /// ```
        pub fn groupByRaw(self: *Self, raw_sql: []const u8) *Self {
            const _raw = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}",
                .{raw_sql},
            ) catch return self;
            self.group_clauses.append(self.arena.allocator(), _raw) catch return self;
            return self;
        }

        /// Add HAVING clause
        ///
        /// Example:
        /// ```zig
        /// .having("COUNT(*) > $1")
        /// ```
        pub fn having(self: *Self, condition: []const u8) *Self {
            const _cond = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}",
                .{condition},
            ) catch return self;
            self.having_clauses.append(self.arena.allocator(), _cond) catch return self;
            return self;
        }

        /// Add HAVING with aggregate function
        ///
        /// Example:
        /// ```zig
        /// .havingAggregate(.count, .id, .gt, "$1")
        /// ```
        pub fn havingAggregate(self: *Self, agg: AggregateType, field: FE, operator: Operator, value: []const u8) *Self {
            const _cond = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}({s}) {s} {s}",
                .{ agg.toSql(), @tagName(field), operator.toSql(), value },
            ) catch return self;
            self.having_clauses.append(self.arena.allocator(), _cond) catch return self;
            return self;
        }

        /// Set ORDER BY clause (can be called multiple times)
        ///
        /// Example:
        /// ```zig
        /// .orderBy(.{ .field = .created_at, .direction = .desc })
        /// .orderBy(.{ .field = .name, .direction = .asc })
        /// ```
        pub fn orderBy(self: *Self, clause: OrderByClause) *Self {
            const direction_str = clause.toSql();
            const _clause = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s} {s}",
                .{ @tagName(clause.field), direction_str },
            ) catch return self;
            self.order_clauses.append(self.arena.allocator(), _clause) catch return self;
            return self;
        }

        /// Add raw ORDER BY clause
        ///
        /// Example:
        /// ```zig
        /// .orderByRaw("RANDOM()")
        /// ```
        pub fn orderByRaw(self: *Self, raw_sql: []const u8) *Self {
            const _raw = std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}",
                .{raw_sql},
            ) catch return self;
            self.order_clauses.append(self.arena.allocator(), _raw) catch return self;
            return self;
        }

        /// Set LIMIT
        ///
        /// Example:
        /// ```zig
        /// .limit(10)
        /// ```
        pub fn limit(self: *Self, n: u64) *Self {
            self.limit_val = n;
            return self;
        }

        /// Set OFFSET
        ///
        /// Example:
        /// ```zig
        /// .offset(10)
        /// ```
        pub fn offset(self: *Self, n: u64) *Self {
            self.offset_val = n;
            return self;
        }

        /// Paginate results (convenience method for limit + offset)
        ///
        /// Example:
        /// ```zig
        /// .paginate(2, 20) // Page 2 with 20 items per page
        /// ```
        pub fn paginate(self: *Self, page: u64, per_page: u64) *Self {
            const actual_page = if (page == 0) 1 else page;
            self.limit_val = per_page;
            self.offset_val = (actual_page - 1) * per_page;
            return self;
        }

        /// Include soft-deleted records
        pub fn withDeleted(self: *Self) *Self {
            self.include_deleted = true;
            return self;
        }

        /// Only get soft-deleted records
        ///
        /// Example:
        /// ```zig
        /// .onlyDeleted()
        /// ```
        pub fn onlyDeleted(self: *Self) *Self {
            self.include_deleted = true;
            const sql = std.fmt.allocPrint(
                self.arena.allocator(),
                "deleted_at IS NOT NULL",
                .{},
            ) catch return self;
            self.where_clauses.append(self.arena.allocator(), .{
                .sql = sql,
                .clause_type = .@"and",
            }) catch return self;
            return self;
        }

        pub fn buildSql(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
            var sql = std.ArrayList(u8){};
            defer sql.deinit(allocator);

            const table_name = T.tableName();

            // SELECT clause
            if (self.distinct_enabled) {
                try sql.appendSlice(allocator, "SELECT DISTINCT ");
            } else {
                try sql.appendSlice(allocator, "SELECT ");
            }

            if (self.select_clauses.items.len > 0) {
                for (self.select_clauses.items, 0..) |clause, i| {
                    try sql.appendSlice(allocator, clause);
                    if (i < self.select_clauses.items.len - 1) {
                        try sql.appendSlice(allocator, ", ");
                    }
                }
                try sql.appendSlice(allocator, " ");
            } else {
                try sql.appendSlice(allocator, "* ");
            }

            // FROM clause
            try sql.writer(allocator).print("FROM {s}", .{table_name});

            // JOIN clauses
            for (self.join_clauses.items) |join_sql| {
                try sql.appendSlice(allocator, " ");
                try sql.appendSlice(allocator, join_sql);
            }

            var first_where = true;

            // Handle soft deletes
            const has_deleted_at = @hasField(T, "deleted_at");
            if (has_deleted_at and !self.include_deleted) {
                try sql.appendSlice(allocator, " WHERE deleted_at IS NULL");
                first_where = false;
            }

            // WHERE clauses
            for (self.where_clauses.items) |clause| {
                if (first_where) {
                    try sql.appendSlice(allocator, " WHERE ");
                    first_where = false;
                } else {
                    try sql.writer(allocator).print(" {s} ", .{clause.clause_type.toSql()});
                }
                try sql.appendSlice(allocator, clause.sql);
            }

            // GROUP BY clause
            if (self.group_clauses.items.len > 0) {
                try sql.appendSlice(allocator, " GROUP BY ");
                for (self.group_clauses.items, 0..) |group, i| {
                    try sql.appendSlice(allocator, group);
                    if (i < self.group_clauses.items.len - 1) {
                        try sql.appendSlice(allocator, ", ");
                    }
                }
            }

            // HAVING clause
            if (self.having_clauses.items.len > 0) {
                try sql.appendSlice(allocator, " HAVING ");
                for (self.having_clauses.items, 0..) |having_clause, i| {
                    try sql.appendSlice(allocator, having_clause);
                    if (i < self.having_clauses.items.len - 1) {
                        try sql.appendSlice(allocator, " AND ");
                    }
                }
            }

            // ORDER BY clause
            if (self.order_clauses.items.len > 0) {
                try sql.appendSlice(allocator, " ORDER BY ");
                for (self.order_clauses.items, 0..) |order, i| {
                    try sql.appendSlice(allocator, order);
                    if (i < self.order_clauses.items.len - 1) {
                        try sql.appendSlice(allocator, ", ");
                    }
                }
            }

            // LIMIT clause
            if (self.limit_val) |l| {
                var buf: [32]u8 = undefined;
                const _limit = try std.fmt.bufPrint(&buf, " LIMIT {d}", .{l});
                try sql.appendSlice(allocator, _limit);
            }

            // OFFSET clause
            if (self.offset_val) |o| {
                var buf: [32]u8 = undefined;
                const _offset = try std.fmt.bufPrint(&buf, " OFFSET {d}", .{o});
                try sql.appendSlice(allocator, _offset);
            }

            return sql.toOwnedSlice(allocator);
        }

        /// Check if the query has custom projections that can't be mapped to the model type.
        /// This includes:
        /// - Aggregate functions (COUNT, SUM, etc.)
        /// - Raw selects with aliases (AS)
        /// - JOIN clauses (result columns from multiple tables)
        /// - GROUP BY clauses (typically used with aggregates)
        /// - HAVING clauses (requires GROUP BY)
        /// - DISTINCT with custom selects
        fn hasCustomProjection(self: *Self) bool {
            // JOINs produce columns from multiple tables - can't map to single model
            if (self.join_clauses.items.len > 0) {
                return true;
            }

            // GROUP BY typically means aggregation - result shape differs from model
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

        /// Execute query and return list of items.
        /// Returns an error if the query contains custom projections that can't map to model type K:
        /// - JOINs (use `fetchRaw` or `fetchAs` with a custom struct)
        /// - GROUP BY / HAVING clauses
        /// - Aggregate functions (selectAggregate)
        /// - Raw selects with aliases or table prefixes
        ///
        /// Example:
        /// ```zig
        /// const users = try User.query()
        ///     .where(.{ .field = .status, .operator = .eq, .value = "'active'" })
        ///     .fetch(&pool, allocator, .{});
        /// defer allocator.free(users);
        /// ```
        pub fn fetch(self: *Self, db: Executor, allocator: std.mem.Allocator, args: anytype) ![]T {
            // Guard: reject queries with custom projections that can't map to K
            if (self.hasCustomProjection()) {
                return error.CustomProjectionRequiresFetchAs;
            }

            const temp_allocator = self.arena.allocator();
            const sql = try self.buildSql(temp_allocator);

            var result = try db.queryOpts(sql, args, .{
                .column_names = true,
            });
            defer result.deinit();

            var items = std.ArrayList(T){};
            errdefer items.deinit(allocator);

            var mapper = result.mapper(T, .{ .allocator = allocator });
            while (try mapper.next()) |item| {
                try items.append(allocator, item);
            }
            return items.toOwnedSlice(allocator);
        }

        /// Execute query and return list of items mapped to a custom result type.
        /// Use this when you have custom selects, aggregates, or need a different shape than the model.
        ///
        /// Example:
        /// ```zig
        /// const UserSummary = struct { id: i64, total_posts: i64 };
        /// const summaries = try User.query()
        ///     .select(&.{.id})
        ///     .selectAggregate(.count, .id, "total_posts")
        ///     .groupBy(&.{.id})
        ///     .fetchAs(UserSummary, &pool, allocator, .{});
        /// defer allocator.free(summaries);
        /// ```
        pub fn fetchAs(self: *Self, comptime R: type, db: Executor, allocator: std.mem.Allocator, args: anytype) ![]R {
            const temp_allocator = self.arena.allocator();
            const sql = try self.buildSql(temp_allocator);

            var result = try db.queryOpts(sql, args, .{
                .column_names = true,
            });
            defer result.deinit();

            var items = std.ArrayList(R){};
            errdefer items.deinit(allocator);

            var mapper = result.mapper(R, .{ .allocator = allocator });
            while (try mapper.next()) |item| {
                try items.append(allocator, item);
            }
            return items.toOwnedSlice(allocator);
        }

        /// Execute query and return the raw pg.Result.
        /// Use this for complex queries with joins, subqueries, or when you need full control.
        /// The caller is responsible for calling result.deinit() when done.
        ///
        /// Example:
        /// ```zig
        /// var result = try User.query()
        ///     .innerJoin("posts", "users.id = posts.user_id")
        ///     .selectRaw("users.*, posts.title")
        ///     .fetchRaw(&pool, .{});
        /// defer result.deinit();
        ///
        /// while (try result.next()) |row| {
        ///     const user_id = row.get(i64, 0);
        ///     const post_title = row.get([]const u8, 1);
        ///     // ...
        /// }
        /// ```
        pub fn fetchRaw(self: *Self, db: Executor, args: anytype) !pg.Result {
            const temp_allocator = self.arena.allocator();
            const sql = try self.buildSql(temp_allocator);

            return try db.queryOpts(sql, args, .{
                .column_names = true,
            });
        }

        /// Execute query and return first item or null.
        /// Returns an error if the query contains custom projections (JOINs, GROUP BY, aggregates, etc.).
        /// Use `firstAs` for custom result types or `firstRaw` for direct access.
        pub fn first(self: *Self, db: Executor, allocator: std.mem.Allocator, args: anytype) !?T {
            // Guard: reject queries with custom projections that can't map to K
            if (self.hasCustomProjection()) {
                return error.CustomProjectionRequiresFetchAs;
            }

            self.limit_val = 1;
            const temp_allocator = self.arena.allocator();
            const sql = try self.buildSql(temp_allocator);

            var result = try db.queryOpts(sql, args, .{
                .column_names = true,
            });
            defer result.deinit();

            var mapper = result.mapper(T, .{ .allocator = allocator });
            if (try mapper.next()) |item| {
                return item;
            }
            return null;
        }

        /// Execute query and return first item mapped to a custom result type, or null.
        ///
        /// Example:
        /// ```zig
        /// const UserStats = struct { id: i64, post_count: i64 };
        /// const stats = try User.query()
        ///     .select(&.{.id})
        ///     .selectAggregate(.count, .id, "post_count")
        ///     .where(.{ .field = .id, .operator = .eq, .value = "$1" })
        ///     .firstAs(UserStats, &pool, allocator, .{user_id});
        /// ```
        pub fn firstAs(self: *Self, comptime R: type, db: Executor, allocator: std.mem.Allocator, args: anytype) !?R {
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

        /// Execute query and return first row as pg.QueryRow or null.
        /// The caller is responsible for calling row.deinit() when done.
        ///
        /// Example:
        /// ```zig
        /// if (try User.query()
        ///     .selectRaw("users.*, COUNT(posts.id) as post_count")
        ///     .innerJoin("posts", "users.id = posts.user_id")
        ///     .firstRaw(&pool, .{})) |row|
        /// {
        ///     defer row.deinit();
        ///     const name = row.get([]const u8, 1);
        ///     const post_count = row.get(i64, 2);
        /// }
        /// ```
        pub fn firstRaw(self: *Self, db: Executor, args: anytype) !?pg.Result {
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

        /// Delete a record
        pub fn delete(self: *Self, db: Executor, args: anytype) !void {
            const temp_allocator = self.arena.allocator();
            var comp_sql = std.ArrayList(u8){};
            defer comp_sql.deinit(temp_allocator);

            const table_name = T.tableName();
            try comp_sql.writer(temp_allocator).print("DELETE FROM {s}", .{table_name});

            var first_where = true;
            // Handle soft deletes
            const has_deleted_at = @hasField(T, "deleted_at");
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

        /// Count records matching the query
        pub fn count(self: *Self, db: Executor, args: anytype) !i64 {
            const temp_allocator = self.arena.allocator();

            var sql = std.ArrayList(u8){};
            defer sql.deinit(temp_allocator);

            const table_name = T.tableName();
            try sql.appendSlice(temp_allocator, "SELECT COUNT(*) FROM ");
            try sql.appendSlice(temp_allocator, table_name);

            // JOIN clauses
            for (self.join_clauses.items) |join_sql| {
                try sql.appendSlice(temp_allocator, " ");
                try sql.appendSlice(temp_allocator, join_sql);
            }

            var first_where = true;
            const has_deleted_at = @hasField(T, "deleted_at");
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

        /// Check if any records match the query
        ///
        /// Example:
        /// ```zig
        /// const has_users = try User.query()
        ///     .where(.{ .field = .status, .operator = .eq, .value = "'active'" })
        ///     .exists(&pool);
        /// ```
        pub fn exists(self: *Self, db: Executor, args: anytype) !bool {
            const c = try self.count(db, args);
            return c > 0;
        }

        /// Get a single column as a slice
        ///
        /// Example:
        /// ```zig
        /// const emails = try User.query().pluck(&pool, allocator, .email, .{});
        /// ```
        pub fn pluck(self: *Self, db: Executor, allocator: std.mem.Allocator, field: FE, args: anytype) ![][]const u8 {
            const temp_allocator = self.arena.allocator();

            var sql = std.ArrayList(u8){};
            defer sql.deinit(temp_allocator);

            const table_name = T.tableName();
            try sql.writer(temp_allocator).print("SELECT {s} FROM {s}", .{ @tagName(field), table_name });

            var first_where = true;
            const has_deleted_at = @hasField(T, "deleted_at");
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

        /// Get the sum of a column
        ///
        /// Example:
        /// ```zig
        /// const total = try Order.query().sum(&pool, .amount, .{});
        /// ```
        pub fn sum(self: *Self, db: Executor, field: FE, args: anytype) !f64 {
            return self.aggregate(db, .sum, field, args);
        }

        /// Get the average of a column
        ///
        /// Example:
        /// ```zig
        /// const avg_rating = try Review.query().avg(&pool, .rating, .{});
        /// ```
        pub fn avg(self: *Self, db: Executor, field: FE, args: anytype) !f64 {
            return self.aggregate(db, .avg, field, args);
        }

        /// Get the minimum value of a column
        ///
        /// Example:
        /// ```zig
        /// const min_price = try Product.query().min(&pool, .price, .{});
        /// ```
        pub fn min(self: *Self, db: Executor, field: FE, args: anytype) !f64 {
            return self.aggregate(db, .min, field, args);
        }

        /// Get the maximum value of a column
        ///
        /// Example:
        /// ```zig
        /// const max_price = try Product.query().max(&pool, .price, .{});
        /// ```
        pub fn max(self: *Self, db: Executor, field: FE, args: anytype) !f64 {
            return self.aggregate(db, .max, field, args);
        }

        fn aggregate(self: *Self, db: Executor, agg: AggregateType, field: FE, args: anytype) !f64 {
            const temp_allocator = self.arena.allocator();

            var sql = std.ArrayList(u8){};
            defer sql.deinit(temp_allocator);

            const table_name = T.tableName();
            try sql.writer(temp_allocator).print("SELECT {s}({s}) FROM {s}", .{
                agg.toSql(),
                @tagName(field),
                table_name,
            });

            var first_where = true;
            const has_deleted_at = @hasField(T, "deleted_at");
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
    };
}
