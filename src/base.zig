const std = @import("std");

const pg = @import("pg");

const executor = @import("executor.zig");
const Executor = executor.Executor;
const QueryResult = executor.QueryResult;
const RowResult = executor.RowResult;
const ExecResult = executor.ExecResult;

const TableFieldsUnion = @import("registry.zig").TableFieldsUnion;
const Tables = @import("registry.zig").Tables;
const err = @import("error.zig");
const OrmError = err.OrmError;

pub const Relationship = struct {
    name: []const u8,
    type: enum { hasOne, hasMany, belongsTo },
    foreign_table: Tables,
    foreign_key: TableFieldsUnion,
    local_key: TableFieldsUnion,
};

/// Base Model provides common database operations for any model type
/// Note: This is used internally by generated models.
/// For custom extensions, create wrapper structs (see docs/EXTENDING_MODELS.md)
pub fn BaseModel(comptime T: type) type {
    if (!@hasDecl(T, "tableName")) {
        @compileError("Struct must have a tableName field");
    }

    // Result type aliases for operations that return a value and can have detailed errors
    const InsertResult = err.Result([]const u8);
    const ModelResult = err.Result(T);
    const ModelListResult = err.Result([]T);
    const InsertManyResult = err.Result([]const []const u8);
    const VoidResult = err.Result(void);
    const CountResult = err.Result(i64);

    return struct {
        /// Truncates the table (removes all data but keeps structure)
        /// Returns OrmError on failure for detailed error info
        pub fn truncate(db: Executor) VoidResult {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const table_name = T.tableName();
            const sql = std.fmt.allocPrint(temp_allocator, "TRUNCATE TABLE {s} RESTART IDENTITY CASCADE", .{table_name}) catch |e| {
                return .{ .err = OrmError.fromError(e) };
            };

            const result = db.execWithErr(sql, .{});
            return switch (result) {
                .ok => .{ .ok = {} },
                .err => |e| .{ .err = e },
            };
        }

        /// Truncate implementation that can return Zig errors
        pub fn truncateOrError(db: Executor) !void {
            const result = truncate(db);
            return switch (result) {
                .ok => {},
                .err => |e| if (e.err) |underlying| underlying else error.OrmError,
            };
        }

        /// Checks if the table exists
        pub fn tableExists(db: Executor) !bool {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            const table_name = T.tableName();
            const sql =
                \\SELECT EXISTS (
                \\    SELECT FROM information_schema.tables
                \\    WHERE table_schema = 'public'
                \\    AND table_name = $1
                \\)
            ;
            var result = try db.query(sql, .{table_name});
            result.drain() catch {};
            defer result.deinit();
            return false; // TODO: parse result
        }

        /// Find a record by ID
        /// Returns OrmError on failure for detailed error info
        pub fn findById(db: Executor, allocator: std.mem.Allocator, id: []const u8) ModelResult {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const table_name = T.tableName();
            const has_deleted_at = @hasField(T, "deleted_at");
            const sql = if (has_deleted_at)
                std.fmt.allocPrint(temp_allocator, "SELECT * FROM {s} WHERE id = $1 AND deleted_at IS NULL", .{table_name}) catch |e| {
                    return .{ .err = OrmError.fromError(e) };
                }
            else
                std.fmt.allocPrint(temp_allocator, "SELECT * FROM {s} WHERE id = $1", .{table_name}) catch |e| {
                    return .{ .err = OrmError.fromError(e) };
                };

            const query_result = db.queryOptsWithErr(sql, .{id}, .{ .column_names = true });
            switch (query_result) {
                .err => |e| return .{ .err = e },
                .ok => |result| {
                    defer result.deinit();
                    var mapper = result.mapper(T, .{ .allocator = allocator });
                    const item = mapper.next() catch |e| {
                        return .{ .err = OrmError.fromError(e) };
                    };
                    if (item) |model| {
                        return .{ .ok = model };
                    }
                    return .{ .err = OrmError.noRows("findById: record not found") };
                },
            }
        }

        /// Find by ID implementation that can return Zig errors
        pub fn findByIdOrError(db: Executor, allocator: std.mem.Allocator, id: []const u8) !?T {
            const result = findById(db, allocator, id);
            return switch (result) {
                .ok => |v| v,
                .err => |e| {
                    if (e.code == .NoRowsReturned) return null;
                    if (e.err) |underlying| return underlying else return error.OrmError;
                },
            };
        }

        /// Find all records (optionally filtered by deleted_at)
        /// Returns OrmError on failure for detailed error info
        pub fn findAll(db: Executor, allocator: std.mem.Allocator, include_deleted: bool) ModelListResult {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const table_name = T.tableName();
            const has_deleted_at = @hasField(T, "deleted_at");
            const sql = if (!has_deleted_at or include_deleted)
                std.fmt.allocPrint(temp_allocator, "SELECT * FROM {s}", .{table_name}) catch |e| {
                    return .{ .err = OrmError.fromError(e) };
                }
            else
                std.fmt.allocPrint(temp_allocator, "SELECT * FROM {s} WHERE deleted_at IS NULL", .{table_name}) catch |e| {
                    return .{ .err = OrmError.fromError(e) };
                };

            const query_result = db.queryOptsWithErr(sql, .{}, .{ .column_names = true });
            switch (query_result) {
                .err => |e| return .{ .err = e },
                .ok => |result| {
                    defer result.deinit();
                    var items = std.ArrayList(T){};
                    errdefer items.deinit(allocator);

                    var mapper = result.mapper(T, .{ .allocator = allocator });
                    while (true) {
                        const item = mapper.next() catch |e| {
                            return .{ .err = OrmError.fromError(e) };
                        };
                        if (item) |model| {
                            items.append(allocator, model) catch |e| {
                                return .{ .err = OrmError.fromError(e) };
                            };
                        } else break;
                    }
                    return .{ .ok = items.toOwnedSlice(allocator) catch |e| {
                        return .{ .err = OrmError.fromError(e) };
                    } };
                },
            }
        }

        /// Find all implementation that can return Zig errors
        pub fn findAllOrError(db: Executor, allocator: std.mem.Allocator, include_deleted: bool) ![]T {
            const result = findAll(db, allocator, include_deleted);
            return switch (result) {
                .ok => |v| v,
                .err => |e| if (e.err) |underlying| underlying else error.OrmError,
            };
        }

        /// Insert a new record using CreateInput type
        /// Returns Result with either the ID or detailed OrmError
        pub fn insert(db: Executor, allocator: std.mem.Allocator, data: anytype) InsertResult {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            if (!@hasDecl(T, "insertSQL")) {
                @compileError("Model must implement 'insertSQL() []const u8'");
            }
            if (!@hasDecl(T, "insertParams")) {
                @compileError("Model must implement 'insertParams(data: CreateInput) anytype'");
            }

            const sql = T.insertSQL();
            const params = T.insertParams(data);

            const row_result = db.rowWithErr(sql, params);
            switch (row_result) {
                .err => |e| return .{ .err = e },
                .ok => |maybe_row| {
                    var row = maybe_row orelse return .{ .err = OrmError.noRows("insert: no row returned") };
                    defer row.deinit() catch {};
                    const id = row.get([]const u8, 0);
                    return .{ .ok = allocator.dupe(u8, id) catch |e| {
                        return .{ .err = OrmError.fromError(e) };
                    } };
                },
            }
        }

        /// Insert implementation that can return Zig errors (for use with try)
        pub fn insertOrError(db: Executor, allocator: std.mem.Allocator, data: anytype) ![]const u8 {
            const result = insert(db, allocator, data);
            return switch (result) {
                .ok => |v| v,
                .err => |e| if (e.err) |underlying| underlying else error.OrmError,
            };
        }

        /// Insert multiple new records in a single query
        /// Returns Result with either the IDs or detailed OrmError
        pub fn insertMany(
            db: Executor,
            allocator: std.mem.Allocator,
            data_list: []const T.CreateInput,
        ) InsertManyResult {
            if (data_list.len == 0) return .{ .ok = &[_][]const u8{} };

            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            if (!@hasDecl(T, "insertSQL")) {
                @compileError("Model must implement 'insertSQL() []const u8'");
            }
            if (!@hasDecl(T, "insertParams")) {
                @compileError("Model must implement 'insertParams(data: CreateInput) anytype'");
            }

            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const temp_alloc = arena.allocator();

            const base_sql = T.insertSQL();
            const values_token = " VALUES ";
            const values_index = std.mem.indexOf(u8, base_sql, values_token) orelse {
                return .{ .err = OrmError.fromError(error.InvalidModelSQL) };
            };
            const prefix = base_sql[0 .. values_index + values_token.len];

            const returning_token = " RETURNING ";
            const returning_index = std.mem.lastIndexOf(u8, base_sql, returning_token);
            const suffix = if (returning_index) |idx| base_sql[idx..] else "";

            const sample_data = data_list[0];
            const sample_params = T.insertParams(sample_data);
            const params_per_row = @typeInfo(@TypeOf(sample_params)).@"struct".fields.len;

            var sql_builder = std.ArrayList(u8){};
            defer sql_builder.deinit(temp_alloc);

            sql_builder.appendSlice(temp_alloc, prefix) catch |e| {
                return .{ .err = OrmError.fromError(e) };
            };

            var param_counter: usize = 1;
            for (0..data_list.len) |i| {
                if (i > 0) sql_builder.append(temp_alloc, ',') catch |e| {
                    return .{ .err = OrmError.fromError(e) };
                };
                sql_builder.append(temp_alloc, '(') catch |e| {
                    return .{ .err = OrmError.fromError(e) };
                };
                for (0..params_per_row) |j| {
                    if (j > 0) sql_builder.append(temp_alloc, ',') catch |e| {
                        return .{ .err = OrmError.fromError(e) };
                    };
                    sql_builder.writer(temp_alloc).print("${d}", .{param_counter}) catch |e| {
                        return .{ .err = OrmError.fromError(e) };
                    };
                    param_counter += 1;
                }
                sql_builder.append(temp_alloc, ')') catch |e| {
                    return .{ .err = OrmError.fromError(e) };
                };
            }

            if (suffix.len > 0) {
                sql_builder.appendSlice(temp_alloc, suffix) catch |e| {
                    return .{ .err = OrmError.fromError(e) };
                };
            }

            // Get connection for detailed error info
            const conn = db.getConn() catch |e| {
                return .{ .err = OrmError.fromError(e) };
            };
            defer db.releaseConn(conn);

            const query_str = sql_builder.items;

            var stmt = conn.prepare(query_str) catch |e| {
                return .{ .err = err.toOrmError(e, conn) };
            };
            errdefer stmt.deinit();

            for (data_list) |item| {
                const params = T.insertParams(item);
                inline for (params) |p| {
                    stmt.bind(p) catch |e| {
                        return .{ .err = err.toOrmError(e, conn) };
                    };
                }
            }

            var result = stmt.execute() catch |e| {
                return .{ .err = err.toOrmError(e, conn) };
            };
            defer result.deinit();

            var ids = std.ArrayList([]const u8){};
            errdefer {
                for (ids.items) |id| allocator.free(id);
                ids.deinit(allocator);
            }

            while (true) {
                const row = result.next() catch |e| {
                    return .{ .err = err.toOrmError(e, conn) };
                };
                if (row) |r| {
                    const id = r.get([]const u8, 0);
                    ids.append(allocator, allocator.dupe(u8, id) catch |e| {
                        return .{ .err = OrmError.fromError(e) };
                    }) catch |e| {
                        return .{ .err = OrmError.fromError(e) };
                    };
                } else break;
            }

            return .{ .ok = ids.toOwnedSlice(allocator) catch |e| {
                return .{ .err = OrmError.fromError(e) };
            } };
        }

        /// InsertMany implementation that can return Zig errors
        pub fn insertManyOrError(
            db: Executor,
            allocator: std.mem.Allocator,
            data_list: []const T.CreateInput,
        ) ![]const []const u8 {
            const result = insertMany(db, allocator, data_list);
            return switch (result) {
                .ok => |v| v,
                .err => |e| if (e.err) |underlying| underlying else error.OrmError,
            };
        }

        /// Insert a new record and return the full model
        /// Returns Result with either the model or detailed OrmError
        pub fn insertAndReturn(db: Executor, allocator: std.mem.Allocator, data: anytype) ModelResult {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            if (!@hasDecl(T, "insertSQL")) {
                @compileError("Model must implement 'insertSQL() []const u8'");
            }
            if (!@hasDecl(T, "insertParams")) {
                @compileError("Model must implement 'insertParams(data: CreateInput) anytype'");
            }

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const base_sql = T.insertSQL();
            const sql = blk: {
                if (std.mem.indexOf(u8, base_sql, "RETURNING id")) |_| {
                    break :blk std.mem.replaceOwned(u8, temp_allocator, base_sql, "RETURNING id", "RETURNING *") catch |e| {
                        return .{ .err = OrmError.fromError(e) };
                    };
                }
                break :blk base_sql;
            };

            const params = T.insertParams(data);

            const query_result = db.queryOptsWithErr(sql, params, .{ .column_names = true });
            switch (query_result) {
                .err => |e| return .{ .err = e },
                .ok => |result| {
                    defer result.deinit();
                    var mapper = result.mapper(T, .{ .allocator = allocator });
                    const item = mapper.next() catch |e| {
                        return .{ .err = OrmError.fromError(e) };
                    };
                    if (item) |model| {
                        return .{ .ok = model };
                    }
                    return .{ .err = OrmError.noRows("insertAndReturn: no row returned") };
                },
            }
        }

        /// InsertAndReturn implementation that can return Zig errors
        pub fn insertAndReturnOrError(db: Executor, allocator: std.mem.Allocator, data: anytype) !T {
            const result = insertAndReturn(db, allocator, data);
            return switch (result) {
                .ok => |v| v,
                .err => |e| if (e.err) |underlying| underlying else error.OrmError,
            };
        }

        /// Update an existing record
        /// Returns OrmError on failure for detailed error info
        pub fn update(db: Executor, id: []const u8, data: anytype) VoidResult {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            if (!@hasDecl(T, "updateSQL")) {
                @compileError("Model must implement 'updateSQL() []const u8'");
            }
            if (!@hasDecl(T, "updateParams")) {
                @compileError("Model must implement 'updateParams(id: []const u8, data: UpdateInput) anytype'");
            }

            const sql = T.updateSQL();
            const params = T.updateParams(id, data);

            const result = db.execWithErr(sql, params);
            return switch (result) {
                .ok => .{ .ok = {} },
                .err => |e| .{ .err = e },
            };
        }

        /// Update implementation that can return Zig errors
        pub fn updateOrError(db: Executor, id: []const u8, data: anytype) !void {
            const result = update(db, id, data);
            return switch (result) {
                .ok => {},
                .err => |e| if (e.err) |underlying| underlying else error.OrmError,
            };
        }

        /// Update an existing record and return the full updated model
        /// Returns Result with either the model or detailed OrmError
        pub fn updateAndReturn(db: Executor, allocator: std.mem.Allocator, id: []const u8, data: anytype) ModelResult {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            if (!@hasDecl(T, "updateSQL")) {
                @compileError("Model must implement 'updateSQL() []const u8'");
            }
            if (!@hasDecl(T, "updateParams")) {
                @compileError("Model must implement 'updateParams(id: []const u8, data: UpdateInput) anytype'");
            }

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const base_sql = T.updateSQL();
            const sql = blk: {
                if (std.mem.indexOf(u8, base_sql, "RETURNING")) |_| {
                    break :blk base_sql;
                }
                break :blk std.fmt.allocPrint(temp_allocator, "{s} RETURNING *", .{base_sql}) catch |e| {
                    return .{ .err = OrmError.fromError(e) };
                };
            };

            const params = T.updateParams(id, data);

            const query_result = db.queryOptsWithErr(sql, params, .{ .column_names = true });
            switch (query_result) {
                .err => |e| return .{ .err = e },
                .ok => |result| {
                    defer result.deinit();
                    var mapper = result.mapper(T, .{ .allocator = allocator });
                    const item = mapper.next() catch |e| {
                        return .{ .err = OrmError.fromError(e) };
                    };
                    if (item) |model| {
                        return .{ .ok = model };
                    }
                    return .{ .err = OrmError.noRows("updateAndReturn: no row returned") };
                },
            }
        }

        /// UpdateAndReturn implementation that can return Zig errors
        pub fn updateAndReturnOrError(db: Executor, allocator: std.mem.Allocator, id: []const u8, data: anytype) !T {
            const result = updateAndReturn(db, allocator, id, data);
            return switch (result) {
                .ok => |v| v,
                .err => |e| if (e.err) |underlying| underlying else error.OrmError,
            };
        }

        /// Upsert (insert or update) a record
        /// Returns Result with either the ID or detailed OrmError
        pub fn upsert(db: Executor, allocator: std.mem.Allocator, data: anytype) InsertResult {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            if (!@hasDecl(T, "upsertSQL")) {
                @compileError("Model must implement 'upsertSQL() []const u8'");
            }
            if (!@hasDecl(T, "upsertParams")) {
                @compileError("Model must implement 'upsertParams(data: CreateInput) anytype'");
            }

            const sql = T.upsertSQL();
            const params = T.upsertParams(data);

            const row_result = db.rowWithErr(sql, params);
            switch (row_result) {
                .err => |e| return .{ .err = e },
                .ok => |maybe_row| {
                    var row = maybe_row orelse return .{ .err = OrmError.noRows("upsert: no row returned") };
                    defer row.deinit() catch {};
                    const id = row.get([]const u8, 0);
                    return .{ .ok = allocator.dupe(u8, id) catch |e| {
                        return .{ .err = OrmError.fromError(e) };
                    } };
                },
            }
        }

        /// Upsert implementation that can return Zig errors
        pub fn upsertOrError(db: Executor, allocator: std.mem.Allocator, data: anytype) ![]const u8 {
            const result = upsert(db, allocator, data);
            return switch (result) {
                .ok => |v| v,
                .err => |e| if (e.err) |underlying| underlying else error.OrmError,
            };
        }

        /// Upsert (insert or update) a record and return the full model
        /// Returns Result with either the model or detailed OrmError
        pub fn upsertAndReturn(db: Executor, allocator: std.mem.Allocator, data: anytype) ModelResult {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            if (!@hasDecl(T, "upsertSQL")) {
                @compileError("Model must implement 'upsertSQL() []const u8'");
            }
            if (!@hasDecl(T, "upsertParams")) {
                @compileError("Model must implement 'upsertParams(data: CreateInput) anytype'");
            }

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const base_sql = T.upsertSQL();
            const sql = blk: {
                if (std.mem.indexOf(u8, base_sql, "RETURNING id")) |_| {
                    break :blk std.mem.replaceOwned(u8, temp_allocator, base_sql, "RETURNING id", "RETURNING *") catch |e| {
                        return .{ .err = OrmError.fromError(e) };
                    };
                }
                break :blk base_sql;
            };

            const params = T.upsertParams(data);

            const query_result = db.queryOptsWithErr(sql, params, .{ .column_names = true });
            switch (query_result) {
                .err => |e| return .{ .err = e },
                .ok => |result| {
                    defer result.deinit();
                    var mapper = result.mapper(T, .{ .allocator = allocator });
                    const item = mapper.next() catch |e| {
                        return .{ .err = OrmError.fromError(e) };
                    };
                    if (item) |model| {
                        return .{ .ok = model };
                    }
                    return .{ .err = OrmError.noRows("upsertAndReturn: no row returned") };
                },
            }
        }

        /// UpsertAndReturn implementation that can return Zig errors
        pub fn upsertAndReturnOrError(db: Executor, allocator: std.mem.Allocator, data: anytype) !T {
            const result = upsertAndReturn(db, allocator, data);
            return switch (result) {
                .ok => |v| v,
                .err => |e| if (e.err) |underlying| underlying else error.OrmError,
            };
        }

        /// Soft delete a record (sets deleted_at timestamp)
        /// Returns OrmError on failure for detailed error info
        pub fn softDelete(db: Executor, id: []const u8) VoidResult {
            if (!@hasField(T, "deleted_at")) {
                @compileError("Model must have 'deleted_at' field to support soft delete");
            }
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const table_name = T.tableName();
            const sql = std.fmt.allocPrint(temp_allocator, "UPDATE {s} SET deleted_at = CURRENT_TIMESTAMP WHERE id = $1", .{table_name}) catch |e| {
                return .{ .err = OrmError.fromError(e) };
            };

            const result = db.execWithErr(sql, .{id});
            return switch (result) {
                .ok => .{ .ok = {} },
                .err => |e| .{ .err = e },
            };
        }

        /// SoftDelete implementation that can return Zig errors
        pub fn softDeleteOrError(db: Executor, id: []const u8) !void {
            const result = softDelete(db, id);
            return switch (result) {
                .ok => {},
                .err => |e| if (e.err) |underlying| underlying else error.OrmError,
            };
        }

        /// Hard delete a record (permanently removes from database)
        /// Returns OrmError on failure for detailed error info
        pub fn hardDelete(db: Executor, id: []const u8) VoidResult {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const table_name = T.tableName();
            const sql = std.fmt.allocPrint(temp_allocator, "DELETE FROM {s} WHERE id = $1", .{table_name}) catch |e| {
                return .{ .err = OrmError.fromError(e) };
            };

            const result = db.execWithErr(sql, .{id});
            return switch (result) {
                .ok => .{ .ok = {} },
                .err => |e| .{ .err = e },
            };
        }

        /// HardDelete implementation that can return Zig errors
        pub fn hardDeleteOrError(db: Executor, id: []const u8) !void {
            const result = hardDelete(db, id);
            return switch (result) {
                .ok => {},
                .err => |e| if (e.err) |underlying| underlying else error.OrmError,
            };
        }

        /// Count records in the table
        /// Returns Result with either the count or detailed OrmError
        pub fn count(db: Executor, include_deleted: bool) CountResult {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const table_name = T.tableName();
            const has_deleted_at = @hasField(T, "deleted_at");
            const sql = if (!has_deleted_at or include_deleted)
                std.fmt.allocPrint(temp_allocator, "SELECT COUNT(*) FROM {s}", .{table_name}) catch |e| {
                    return .{ .err = OrmError.fromError(e) };
                }
            else
                std.fmt.allocPrint(temp_allocator, "SELECT COUNT(*) FROM {s} WHERE deleted_at IS NULL", .{table_name}) catch |e| {
                    return .{ .err = OrmError.fromError(e) };
                };

            const row_result = db.rowWithErr(sql, .{});
            switch (row_result) {
                .err => |e| return .{ .err = e },
                .ok => |maybe_row| {
                    var row = maybe_row orelse return .{ .err = OrmError.noRows("count: no row returned") };
                    defer row.deinit() catch {};
                    return .{ .ok = row.get(i64, 0) };
                },
            }
        }

        /// Count implementation that can return Zig errors
        pub fn countOrError(db: Executor, include_deleted: bool) !i64 {
            const result = count(db, include_deleted);
            return switch (result) {
                .ok => |v| v,
                .err => |e| if (e.err) |underlying| underlying else error.OrmError,
            };
        }

        /// From row
        pub fn fromRow(row: anytype, allocator: std.mem.Allocator) !T {
            return row.to(T, .{ .allocator = allocator });
        }
    };
}
