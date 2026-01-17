const std = @import("std");
const pg = @import("pg");

/// PostgreSQL error details extracted from pg.zig
/// This provides user-friendly access to error information
pub const PgError = struct {
    /// PostgreSQL error code (e.g., "23505" for unique violation)
    /// See: https://www.postgresql.org/docs/current/errcodes-appendix.html
    code: []const u8,
    /// Human-readable error message
    message: []const u8,
    /// Error severity (e.g., "ERROR", "FATAL")
    severity: []const u8,
    /// Additional details about the error (e.g., "Key (id)=(123) already exists.")
    detail: ?[]const u8 = null,
    /// Hint for resolving the error
    hint: ?[]const u8 = null,
    /// Name of the constraint that was violated
    constraint: ?[]const u8 = null,
    /// Table name involved in the error
    table: ?[]const u8 = null,
    /// Schema name involved in the error
    schema: ?[]const u8 = null,
    /// Column name involved in the error
    column: ?[]const u8 = null,

    /// Check if the error is a unique constraint violation (duplicate key)
    pub fn isUniqueViolation(self: PgError) bool {
        return std.mem.eql(u8, self.code, "23505");
    }

    /// Check if the error is a foreign key violation
    pub fn isForeignKeyViolation(self: PgError) bool {
        return std.mem.eql(u8, self.code, "23503");
    }

    /// Check if the error is a not-null violation
    pub fn isNotNullViolation(self: PgError) bool {
        return std.mem.eql(u8, self.code, "23502");
    }

    /// Check if the error is a check constraint violation
    pub fn isCheckViolation(self: PgError) bool {
        return std.mem.eql(u8, self.code, "23514");
    }

    /// Check if the error is a syntax error
    pub fn isSyntaxError(self: PgError) bool {
        return std.mem.eql(u8, self.code, "42601");
    }

    /// Check if the error is "table does not exist"
    pub fn isUndefinedTable(self: PgError) bool {
        return std.mem.eql(u8, self.code, "42P01");
    }

    /// Check if the error is "column does not exist"
    pub fn isUndefinedColumn(self: PgError) bool {
        return std.mem.eql(u8, self.code, "42703");
    }

    /// Format the error for logging/display
    pub fn format(self: PgError, writer: anytype) !void {
        try writer.print("[{s}] {s}: {s}", .{ self.code, self.severity, self.message });
        if (self.detail) |d| {
            try writer.print("\n  Detail: {s}", .{d});
        }
        if (self.hint) |h| {
            try writer.print("\n  Hint: {s}", .{h});
        }
        if (self.constraint) |c| {
            try writer.print("\n  Constraint: {s}", .{c});
        }
        if (self.table) |t| {
            try writer.print("\n  Table: {s}", .{t});
        }
        if (self.column) |col| {
            try writer.print("\n  Column: {s}", .{col});
        }
    }

    /// Get a formatted error string (allocates memory)
    pub fn toString(self: PgError, allocator: std.mem.Allocator) ![]u8 {
        var buf = std.ArrayList(u8).init(allocator);
        errdefer buf.deinit();
        try self.format(buf.writer());
        return buf.toOwnedSlice();
    }
};

/// ORM-specific error codes for better error categorization
pub const ErrorCode = enum {
    /// A unique constraint was violated (duplicate key)
    UniqueViolation,
    /// A foreign key constraint was violated
    ForeignKeyViolation,
    /// A not-null constraint was violated
    NotNullViolation,
    /// A check constraint was violated
    CheckViolation,
    /// The operation returned no rows when rows were expected
    NoRowsReturned,
    /// The operation returned more rows than expected
    TooManyRows,
    /// SQL syntax error
    SyntaxError,
    /// Table does not exist
    UndefinedTable,
    /// Column does not exist
    UndefinedColumn,
    /// A database connection error
    ConnectionError,
    /// General database error
    DatabaseError,
    /// Unknown/other error
    Unknown,

    /// Get a user-friendly description of the error code
    pub fn description(self: ErrorCode) []const u8 {
        return switch (self) {
            .UniqueViolation => "A record with this value already exists",
            .ForeignKeyViolation => "Referenced record does not exist",
            .NotNullViolation => "A required field was not provided",
            .CheckViolation => "Value failed validation constraint",
            .NoRowsReturned => "Operation did not affect any records",
            .TooManyRows => "Operation affected more records than expected",
            .SyntaxError => "Invalid SQL syntax",
            .UndefinedTable => "Table does not exist",
            .UndefinedColumn => "Column does not exist",
            .ConnectionError => "Database connection error",
            .DatabaseError => "Database error occurred",
            .Unknown => "An unexpected error occurred",
        };
    }
};

/// ORM-level error result that provides detailed error information.
/// This is the main error type returned by ORM operations.
pub const OrmError = struct {
    /// Categorized error code for easy handling
    code: ErrorCode,
    /// Human-readable error message
    message: []const u8,
    /// The underlying Zig error (if any)
    err: ?anyerror = null,
    /// PostgreSQL-specific error details (if available)
    pg_error: ?PgError = null,

    /// Create an OrmError from a PostgreSQL error
    pub fn fromPgError(pge: PgError) OrmError {
        const code: ErrorCode = if (pge.isUniqueViolation())
            .UniqueViolation
        else if (pge.isForeignKeyViolation())
            .ForeignKeyViolation
        else if (pge.isNotNullViolation())
            .NotNullViolation
        else if (pge.isCheckViolation())
            .CheckViolation
        else if (pge.isSyntaxError())
            .SyntaxError
        else if (pge.isUndefinedTable())
            .UndefinedTable
        else if (pge.isUndefinedColumn())
            .UndefinedColumn
        else
            .DatabaseError;

        return .{
            .code = code,
            .message = pge.message,
            .err = error.PG,
            .pg_error = pge,
        };
    }

    /// Create an OrmError from a Zig error
    pub fn fromError(err: anyerror) OrmError {
        return .{
            .code = .Unknown,
            .message = @errorName(err),
            .err = err,
            .pg_error = null,
        };
    }

    /// Create an OrmError for "no rows returned" scenario
    pub fn noRows(operation: []const u8) OrmError {
        return .{
            .code = .NoRowsReturned,
            .message = operation,
            .err = null,
            .pg_error = null,
        };
    }

    /// Check if this is a unique constraint violation
    pub fn isUniqueViolation(self: OrmError) bool {
        return self.code == .UniqueViolation;
    }

    /// Check if this is a foreign key violation
    pub fn isForeignKeyViolation(self: OrmError) bool {
        return self.code == .ForeignKeyViolation;
    }

    /// Check if this is a not-null violation
    pub fn isNotNullViolation(self: OrmError) bool {
        return self.code == .NotNullViolation;
    }

    /// Get the constraint name that was violated (if available)
    pub fn constraintName(self: OrmError) ?[]const u8 {
        if (self.pg_error) |pge| {
            return pge.constraint;
        }
        return null;
    }

    /// Get the table name involved (if available)
    pub fn tableName(self: OrmError) ?[]const u8 {
        if (self.pg_error) |pge| {
            return pge.table;
        }
        return null;
    }

    /// Get the column name involved (if available)
    pub fn columnName(self: OrmError) ?[]const u8 {
        if (self.pg_error) |pge| {
            return pge.column;
        }
        return null;
    }

    /// Get additional error details (if available)
    pub fn detail(self: OrmError) ?[]const u8 {
        if (self.pg_error) |pge| {
            return pge.detail;
        }
        return null;
    }

    /// Format the error for logging/display
    pub fn format(self: OrmError, writer: anytype) !void {
        try writer.print("[{s}] {s}", .{ @tagName(self.code), self.message });
        if (self.pg_error) |pge| {
            if (pge.detail) |d| {
                try writer.print("\n  Detail: {s}", .{d});
            }
            if (pge.constraint) |c| {
                try writer.print("\n  Constraint: {s}", .{c});
            }
            if (pge.table) |t| {
                try writer.print("\n  Table: {s}", .{t});
            }
        }
    }

    /// Log the error using std.log
    pub fn log(self: OrmError) void {
        std.log.err("[{s}] {s}", .{ @tagName(self.code), self.message });
        if (self.pg_error) |pge| {
            if (pge.detail) |d| {
                std.log.err("  Detail: {s}", .{d});
            }
            if (pge.constraint) |c| {
                std.log.err("  Constraint: {s}", .{c});
            }
        }
    }
};

/// Result type for ORM operations that can fail with detailed errors.
/// Use this as the return type for operations that need to return detailed error info.
pub fn Result(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: OrmError,

        const Self = @This();

        /// Check if the result is successful
        pub fn isOk(self: Self) bool {
            return self == .ok;
        }

        /// Check if the result is an error
        pub fn isErr(self: Self) bool {
            return self == .err;
        }

        /// Unwrap the value, or return the Zig error if present
        pub fn unwrap(self: Self) !T {
            return switch (self) {
                .ok => |v| v,
                .err => |e| if (e.err) |underlying| underlying else error.OrmError,
            };
        }

        /// Get the error if present
        pub fn getErr(self: Self) ?OrmError {
            return switch (self) {
                .ok => null,
                .err => |e| e,
            };
        }
    };
}

/// Extract PgError from a pg.Conn after an error.PG occurred
pub fn extractPgError(conn: *pg.Conn) ?PgError {
    if (conn.err) |pge| {
        return PgError{
            .code = pge.code,
            .message = pge.message,
            .severity = pge.severity,
            .detail = pge.detail,
            .hint = pge.hint,
            .constraint = pge.constraint,
            .table = pge.table,
            .schema = pge.schema,
            .column = pge.column,
        };
    }
    return null;
}

/// Convert any error to an OrmError, extracting PG error details if available.
/// This is the main helper for converting errors in catch blocks.
pub fn toOrmError(err: anyerror, conn: ?*pg.Conn) OrmError {
    if (err == error.PG) {
        if (conn) |c| {
            if (extractPgError(c)) |pge| {
                return OrmError.fromPgError(pge);
            }
        }
    }
    return OrmError.fromError(err);
}

/// Log an error with full details. Useful for debugging.
pub fn logError(err: anyerror, conn: ?*pg.Conn) void {
    const orm_err = toOrmError(err, conn);
    orm_err.log();
}
