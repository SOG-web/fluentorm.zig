const std = @import("std");
const pg = @import("pg");

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

    /// Derive error code from PostgreSQL error code
    pub fn fromPgCode(code: []const u8) ErrorCode {
        // https://www.postgresql.org/docs/current/errcodes-appendix.html
        if (std.mem.eql(u8, code, "23505")) return .UniqueViolation;
        if (std.mem.eql(u8, code, "23503")) return .ForeignKeyViolation;
        if (std.mem.eql(u8, code, "23502")) return .NotNullViolation;
        if (std.mem.eql(u8, code, "23514")) return .CheckViolation;
        if (std.mem.eql(u8, code, "42601")) return .SyntaxError;
        if (std.mem.eql(u8, code, "42P01")) return .UndefinedTable;
        if (std.mem.eql(u8, code, "42703")) return .UndefinedColumn;
        return .DatabaseError;
    }
};

/// ORM-level error result that provides detailed error information.
/// This is the main error type returned by ORM operations.
/// Uses pg.Error directly to avoid duplication.
pub const OrmError = struct {
    /// Categorized error code for easy handling
    code: ErrorCode,
    /// Human-readable error message
    message: []const u8,
    /// The underlying Zig error (if any)
    err: ?anyerror = null,
    /// PostgreSQL error details (direct reference to pg.Error)
    /// Note: This is only valid while the connection is held
    pg_error: ?pg.Error = null,

    /// Create an OrmError from a pg.Error (from conn.err)
    pub fn fromPgError(pge: pg.Error) OrmError {
        return .{
            .code = ErrorCode.fromPgCode(pge.code),
            .message = pge.message,
            .err = error.PG,
            .pg_error = pge,
        };
    }

    /// Create an OrmError from a Zig error
    pub fn fromError(e: anyerror) OrmError {
        return .{
            .code = .Unknown,
            .message = @errorName(e),
            .err = e,
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
    /// Uses pg.Error.isUnique() when available
    pub fn isUniqueViolation(self: OrmError) bool {
        if (self.pg_error) |pge| {
            return pge.isUnique();
        }
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

    /// Get the constraint name if available
    pub fn constraintName(self: OrmError) ?[]const u8 {
        if (self.pg_error) |pge| {
            return pge.constraint;
        }
        return null;
    }

    /// Get the table name if available
    pub fn tableName(self: OrmError) ?[]const u8 {
        if (self.pg_error) |pge| {
            return pge.table;
        }
        return null;
    }

    /// Get the column name if available
    pub fn columnName(self: OrmError) ?[]const u8 {
        if (self.pg_error) |pge| {
            return pge.column;
        }
        return null;
    }

    /// Get the detail message if available
    pub fn detail(self: OrmError) ?[]const u8 {
        if (self.pg_error) |pge| {
            return pge.detail;
        }
        return null;
    }

    /// Get the hint if available
    pub fn hint(self: OrmError) ?[]const u8 {
        if (self.pg_error) |pge| {
            return pge.hint;
        }
        return null;
    }

    /// Get the PostgreSQL error code if available
    pub fn pgCode(self: OrmError) ?[]const u8 {
        if (self.pg_error) |pge| {
            return pge.code;
        }
        return null;
    }

    /// Log the error with full details
    pub fn log(self: OrmError) void {
        std.log.err("[{s}] {s}", .{ @tagName(self.code), self.message });
        if (self.pg_error) |pge| {
            if (pge.detail) |d| {
                std.log.err("  Detail: {s}", .{d});
            }
            if (pge.constraint) |c| {
                std.log.err("  Constraint: {s}", .{c});
            }
            if (pge.hint) |h| {
                std.log.err("  Hint: {s}", .{h});
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

/// Convert any error to an OrmError, extracting PG error details if available.
/// This is the main helper for converting errors in catch blocks.
pub fn toOrmError(e: anyerror, conn: ?*pg.Conn) OrmError {
    if (e == error.PG) {
        if (conn) |c| {
            if (c.err) |pge| {
                return OrmError.fromPgError(pge);
            }
        }
    }
    return OrmError.fromError(e);
}

/// Log an error with full details. Useful for debugging.
pub fn logError(e: anyerror, conn: ?*pg.Conn) void {
    const orm_err = toOrmError(e, conn);
    orm_err.log();
}
