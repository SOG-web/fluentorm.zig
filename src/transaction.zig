const std = @import("std");

const pg = @import("pg");

const Executor = @import("executor.zig").Executor;

/// Generic transaction that works with any model.
/// Use this to perform multiple model operations atomically.
///
/// Example:
/// ```zig
/// var tx = try Transaction.begin(pool);
/// defer tx.deinit();
///
/// const user_id = try Users.insert(tx.executor(), allocator, user_data);
/// try Posts.insert(tx.executor(), allocator, .{ .user_id = user_id, ... });
/// try Posts.query().where(....).fetch(tx.executor(),....);
/// try tx.exec("UPDATE stats SET count = count + 1", .{});
///
/// try tx.commit();
/// ```
pub const Transaction = struct {
    pool: *pg.Pool,
    conn: *pg.Conn,
    committed: bool = false,
    rolled_back: bool = false,

    const Self = @This();

    /// Begin a new transaction
    pub fn begin(pool: *pg.Pool) !Self {
        const conn = try pool.acquire();
        errdefer pool.release(conn);
        try conn.begin();
        return Self{
            .pool = pool,
            .conn = conn,
        };
    }

    /// Get an Executor that can be passed to any model method
    pub fn executor(self: *Self) Executor {
        return Executor.fromConn(self.conn);
    }

    /// Commit the transaction
    pub fn commit(self: *Self) !void {
        if (self.rolled_back) {
            return error.TransactionAlreadyRolledBack;
        }
        if (self.committed) {
            return error.TransactionAlreadyCommitted;
        }

        try self.conn.commit();
        self.committed = true;
        self.pool.release(self.conn);
    }

    /// Rollback the transaction
    pub fn rollback(self: *Self) !void {
        if (self.committed) {
            return error.TransactionAlreadyCommitted;
        }
        if (self.rolled_back) {
            return; // Already rolled back, ignore
        }

        try self.conn.rollback();
        self.rolled_back = true;
        self.pool.release(self.conn);
    }

    /// Auto-rollback on deinit if not committed (for use with defer)
    pub fn deinit(self: *Self) void {
        if (!self.committed and !self.rolled_back) {
            self.conn.rollback() catch {};
            self.pool.release(self.conn);
        }
    }

    /// Execute raw SQL within the transaction
    pub fn exec(self: *Self, sql: []const u8, args: anytype) !void {
        _ = try self.conn.exec(sql, args);
    }

    /// Query raw SQL within the transaction
    pub fn query(self: *Self, sql: []const u8, args: anytype) !pg.Result {
        return try self.conn.query(sql, args);
    }

    /// Query with options within the transaction
    pub fn queryOpts(self: *Self, sql: []const u8, args: anytype, opts: pg.Conn.QueryOpts) !pg.Result {
        return try self.conn.queryOpts(sql, args, opts);
    }
};
