const pg = @import("pg");

/// Unified database executor - abstracts over Pool or Conn
/// This allows model methods to work with both direct pool access
/// and transactional connection access using the same API.
pub const Executor = union(enum) {
    pool: *pg.Pool,
    conn: *pg.Conn,

    /// Execute a query and return the result
    pub fn query(self: Executor, sql: []const u8, args: anytype) !pg.Result {
        return switch (self) {
            .pool => |p| try p.query(sql, args),
            .conn => |c| try c.query(sql, args),
        };
    }

    /// Execute a query with options and return the result
    pub fn queryOpts(self: Executor, sql: []const u8, args: anytype, opts: pg.Conn.QueryOpts) !pg.Result {
        return switch (self) {
            .pool => |p| try p.queryOpts(sql, args, opts),
            .conn => |c| try c.queryOpts(sql, args, opts),
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
    pub fn prepare(self: Executor, sql: []const u8) !pg.Stmt {
        return switch (self) {
            .pool => |p| blk: {
                const conn = try p.acquire();
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
};
