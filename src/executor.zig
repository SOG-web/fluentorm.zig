const pg = @import("pg");

const err = @import("error.zig");

/// Unified database executor - abstracts over Pool or Conn
/// This allows model methods to work with both direct pool access
/// and transactional connection access using the same API.
pub const Executor = union(enum) {
    pool: *pg.Pool,
    conn: *pg.Conn,

    /// Execute a query and return the result
    pub fn query(self: Executor, sql: []const u8, args: anytype) !*pg.Result {
        return switch (self) {
            .pool => |p| try p.query(sql, args),
            .conn => |c| try c.query(sql, args),
        };
    }

    /// Execute a query with options and return the result
    pub fn queryOpts(self: Executor, sql: []const u8, args: anytype, opts: pg.Conn.QueryOpts) !*pg.Result {
        return switch (self) {
            .pool => |p| try p.queryOpts(sql, args, opts),
            .conn => |c| try c.queryOpts(sql, args, opts),
        };
    }

    pub fn row(self: Executor, sql: []const u8, args: anytype) !?pg.QueryRow {
        return switch (self) {
            .pool => |p| try p.row(sql, args),
            .conn => |c| try c.row(sql, args),
        };
    }

    pub fn rowOpts(self: Executor, sql: []const u8, args: anytype, opts: pg.Conn.QueryOpts) !?pg.QueryRow {
        return switch (self) {
            .pool => |p| try p.rowOpts(sql, args, opts),
            .conn => |c| try c.rowOpts(sql, args, opts),
        };
    }

    /// Execute a statement without returning results
    pub fn exec(self: Executor, sql: []const u8, args: anytype) !void {
        switch (self) {
            .pool => |p| _ = try p.exec(sql, args),
            .conn => |c| _ = try c.exec(sql, args),
        }
    }

    /// Prepare a statement for later execution
    /// Note: In pool mode, this acquires a connection that MUST be released manually
    /// using executor.releaseConn(stmt.conn).
    pub fn prepare(self: Executor, sql: []const u8) !pg.Stmt {
        return switch (self) {
            .pool => |p| blk: {
                const conn = try p.acquire();
                errdefer p.release(conn);
                break :blk try conn.prepare(sql);
            },
            .conn => |c| try c.prepare(sql),
        };
    }

    /// Create an Executor from a Pool
    pub fn fromPool(pool: *pg.Pool) Executor {
        return .{ .pool = pool };
    }

    /// Create an Executor from a Conn
    pub fn fromConn(conn: *pg.Conn) Executor {
        return .{ .conn = conn };
    }

    /// Check if this executor is using a connection (transaction mode)
    pub fn isTransaction(self: Executor) bool {
        return self == .conn;
    }

    /// Get the underlying connection if in transaction mode.
    /// For pool mode, this acquires a connection that must be released.
    pub fn getConn(self: Executor) !*pg.Conn {
        return switch (self) {
            .pool => |p| try p.acquire(),
            .conn => |c| c,
        };
    }

    /// Release a connection back to the pool (only needed for pool mode)
    pub fn releaseConn(self: Executor, conn: *pg.Conn) void {
        switch (self) {
            .pool => |p| p.release(conn),
            .conn => {}, // In transaction mode, don't release
        }
    }

    /// Get the last PostgreSQL error from the connection (if any).
    /// This should be called after catching an error.PG to get detailed error info.
    /// Note: For pool mode, this requires a connection that was acquired and not yet released.
    pub fn getLastPgError(self: Executor, conn: ?*pg.Conn) ?pg.Error {
        // If a specific connection is provided, use it
        if (conn) |c| {
            return c.err;
        }
        // For conn mode, we can access the error directly
        return switch (self) {
            .conn => |c| c.err,
            .pool => null, // Pool mode requires a connection to be passed
        };
    }

    // =========================================================================
    // Error-aware methods - these acquire connection first so errors can be
    // extracted from conn.err even in pool mode
    // =========================================================================

    /// Execute a query with error details available on failure.
    /// Returns QueryResult which contains either the result or an OrmError with full PG details.
    pub fn queryWithErr(self: Executor, sql: []const u8, args: anytype) QueryResult {
        return self.queryOptsWithErr(sql, args, .{});
    }

    /// Execute a query with options, with error details available on failure.
    pub fn queryOptsWithErr(self: Executor, sql: []const u8, args: anytype, opts_: pg.Conn.QueryOpts) QueryResult {
        // Acquire connection first so we have access to conn.err on failure
        const conn = self.getConn() catch |e| {
            return .{ .err = err.OrmError.fromError(e) };
        };

        var opts = opts_;
        // In pool mode, let result.deinit() release the connection
        if (self == .pool) {
            opts.release_conn = true;
        }

        const result = conn.queryOpts(sql, args, opts) catch |e| {
            const orm_err = err.toOrmError(e, conn);
            self.releaseConn(conn);
            return .{ .err = orm_err };
        };

        return .{ .ok = result };
    }

    /// Execute a single-row query with error details available on failure.
    pub fn rowWithErr(self: Executor, sql: []const u8, args: anytype) RowResult {
        return self.rowOptsWithErr(sql, args, .{});
    }

    /// Execute a single-row query with options, with error details available on failure.
    pub fn rowOptsWithErr(self: Executor, sql: []const u8, args: anytype, opts_: pg.Conn.QueryOpts) RowResult {
        const conn = self.getConn() catch |e| {
            return .{ .err = err.OrmError.fromError(e) };
        };

        var opts = opts_;
        if (self == .pool) {
            opts.release_conn = true;
        }

        const result = conn.rowOpts(sql, args, opts) catch |e| {
            const orm_err = err.toOrmError(e, conn);
            self.releaseConn(conn);
            return .{ .err = orm_err };
        };

        return .{ .ok = result };
    }

    /// Execute a statement with error details available on failure.
    pub fn execWithErr(self: Executor, sql: []const u8, args: anytype) ExecResult {
        const conn = self.getConn() catch |e| {
            return .{ .err = err.OrmError.fromError(e) };
        };

        const result = conn.exec(sql, args) catch |e| {
            const orm_err = err.toOrmError(e, conn);
            self.releaseConn(conn);
            return .{ .err = orm_err };
        };

        self.releaseConn(conn);
        return .{ .ok = result };
    }
};

/// Result type for query operations with error details
pub const QueryResult = union(enum) {
    ok: *pg.Result,
    err: err.OrmError,

    pub fn isOk(self: QueryResult) bool {
        return self == .ok;
    }

    pub fn unwrap(self: QueryResult) !*pg.Result {
        return switch (self) {
            .ok => |r| r,
            .err => |e| if (e.err) |underlying| underlying else error.OrmError,
        };
    }

    pub fn getErr(self: QueryResult) ?err.OrmError {
        return switch (self) {
            .ok => null,
            .err => |e| e,
        };
    }
};

/// Result type for single-row operations with error details
pub const RowResult = union(enum) {
    ok: ?pg.QueryRow,
    err: err.OrmError,

    pub fn isOk(self: RowResult) bool {
        return self == .ok;
    }

    pub fn unwrap(self: RowResult) !?pg.QueryRow {
        return switch (self) {
            .ok => |r| r,
            .err => |e| if (e.err) |underlying| underlying else error.OrmError,
        };
    }

    pub fn getErr(self: RowResult) ?err.OrmError {
        return switch (self) {
            .ok => null,
            .err => |e| e,
        };
    }
};

/// Result type for exec operations with error details
pub const ExecResult = union(enum) {
    ok: ?i64,
    err: err.OrmError,

    pub fn isOk(self: ExecResult) bool {
        return self == .ok;
    }

    pub fn unwrap(self: ExecResult) !?i64 {
        return switch (self) {
            .ok => |r| r,
            .err => |e| if (e.err) |underlying| underlying else error.OrmError,
        };
    }

    pub fn getErr(self: ExecResult) ?err.OrmError {
        return switch (self) {
            .ok => null,
            .err => |e| e,
        };
    }
};
