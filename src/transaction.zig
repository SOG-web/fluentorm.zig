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

// Keep the old model-specific Transaction for backward compatibility during transition
// This will be deprecated in the future
pub fn ModelTransaction(comptime T: type) type {
    return struct {
        conn: *pg.Conn,
        committed: bool = false,
        rolled_back: bool = false,

        const Self = @This();

        /// Begin a new transaction
        pub fn begin(conn: *pg.Conn) !Self {
            try conn.exec("BEGIN", .{});
            return Self{
                .conn = conn,
            };
        }

        /// Commit the transaction
        pub fn commit(self: *Self) !void {
            if (self.rolled_back) {
                return error.TransactionAlreadyRolledBack;
            }
            if (self.committed) {
                return error.TransactionAlreadyCommitted;
            }

            try self.conn.exec("COMMIT", .{});
            self.committed = true;
        }

        /// Rollback the transaction
        pub fn rollback(self: *Self) !void {
            if (self.committed) {
                return error.TransactionAlreadyCommitted;
            }
            if (self.rolled_back) {
                return; // Already rolled back, ignore
            }

            try self.conn.exec("ROLLBACK", .{});
            self.rolled_back = true;
        }

        /// Auto-rollback if not committed (for defer)
        pub fn deinit(self: *Self) void {
            if (!self.committed and !self.rolled_back) {
                self.conn.exec("ROLLBACK", .{}) catch {};
            }
        }

        // Transaction-aware CRUD operations

        /// Insert within transaction
        pub fn insert(self: *Self, allocator: std.mem.Allocator, data: anytype) ![]const u8 {
            if (!@hasDecl(T, "insertSQL")) {
                @compileError("Model must implement 'insertSQL() []const u8'");
            }
            if (!@hasDecl(T, "insertParams")) {
                @compileError("Model must implement 'insertParams(data: CreateInput) anytype'");
            }

            const sql = T.insertSQL();
            const params = T.insertParams(data);

            var result = try self.conn.query(sql, params);
            defer result.deinit();

            if (try result.next()) |row| {
                const id = row.get([]const u8, 0);
                return try allocator.dupe(u8, id);
            }

            return error.InsertFailed;
        }

        /// Update within transaction
        pub fn update(self: *Self, id: []const u8, data: anytype) !void {
            if (!@hasDecl(T, "updateSQL")) {
                @compileError("Model must implement 'updateSQL() []const u8'");
            }
            if (!@hasDecl(T, "updateParams")) {
                @compileError("Model must implement 'updateParams(id: []const u8, data: UpdateInput) anytype'");
            }

            const sql = T.updateSQL();
            const params = T.updateParams(id, data);

            _ = try self.conn.exec(sql, params);
        }

        /// Delete within transaction
        pub fn softDelete(self: *Self, id: []const u8) !void {
            if (!@hasField(T, "deleted_at")) {
                @compileError("Model must have 'deleted_at' field to support soft delete");
            }
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            // Use arena for temporary SQL string
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const table_name = T.tableName();
            const sql = try std.fmt.allocPrint(temp_allocator, "UPDATE {s} SET deleted_at = CURRENT_TIMESTAMP WHERE id = $1", .{table_name});
            _ = try self.conn.exec(sql, .{id});
        }

        /// Hard delete within transaction
        pub fn hardDelete(self: *Self, id: []const u8) !void {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            // Use arena for temporary SQL string
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const table_name = T.tableName();
            const sql = try std.fmt.allocPrint(temp_allocator, "DELETE FROM {s} WHERE id = $1", .{table_name});
            _ = try self.conn.exec(sql, .{id});
        }
    };
}
