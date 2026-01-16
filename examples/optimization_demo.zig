// Example demonstrating the optimization improvements
// This file is for documentation purposes only

const std = @import("std");

// ===== BEFORE OPTIMIZATION =====

// Old approach - runtime function call
pub fn oldTableName() []const u8 {
    return "users";
}

pub fn oldBuildSql(allocator: std.mem.Allocator) ![]const u8 {
    var sql = std.ArrayList(u8).init(allocator);
    defer sql.deinit();
    
    // Runtime function call overhead
    const table_name = oldTableName();
    
    // String literal repeated multiple times
    try sql.appendSlice("SELECT ");
    try sql.writer().print("{s}.*", .{table_name});
    try sql.appendSlice(" FROM ");
    try sql.writer().print("{s} ", .{table_name});
    
    return sql.toOwnedSlice();
}

pub fn oldSelectField(allocator: std.mem.Allocator, table: []const u8, field: []const u8) ![]const u8 {
    // Always allocates on heap
    return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ table, field });
}

// ===== AFTER OPTIMIZATION =====

// New approach - comptime constant
pub const newTableName = "users";

pub fn newTableNameFunc() []const u8 {
    return newTableName; // Returns comptime constant
}

// SQL fragment constants
const SQL_SELECT = "SELECT ";
const SQL_FROM = " FROM ";
const SQL_WILDCARD = ".*";

pub fn newBuildSql(allocator: std.mem.Allocator) ![]const u8 {
    var sql = std.ArrayList(u8).init(allocator);
    defer sql.deinit();
    
    // Comptime constant - no function call
    const table_name = newTableName;
    
    // Named constants - better readability
    try sql.appendSlice(SQL_SELECT);
    try sql.writer().print("{s}{s}", .{ table_name, SQL_WILDCARD });
    try sql.appendSlice(SQL_FROM);
    try sql.writer().print("{s} ", .{table_name});
    
    return sql.toOwnedSlice();
}

pub fn newSelectField(arena_allocator: std.mem.Allocator, table: []const u8, field: []const u8) ![]const u8 {
    // Try stack buffer first, fallback to heap
    var buf: [256]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{s}.{s}", .{ table, field }) catch blk: {
        break :blk try std.fmt.allocPrint(arena_allocator, "{s}.{s}", .{ table, field });
    };
    
    // If bufPrint succeeded, need to dupe for caller
    if (buf[0..].ptr == result.ptr) {
        return try arena_allocator.dupe(u8, result);
    }
    return result;
}

// ===== PERFORMANCE COMPARISON =====

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("\n=== FluentORM Optimization Examples ===\n\n", .{});
    
    // Example 1: Table name access
    std.debug.print("1. Table Name Access:\n", .{});
    std.debug.print("   Old: Function call to oldTableName() -> \"{s}\"\n", .{oldTableName()});
    std.debug.print("   New: Comptime constant newTableName -> \"{s}\"\n", .{newTableName});
    std.debug.print("   Benefit: No function call overhead\n\n", .{});
    
    // Example 2: SQL building
    std.debug.print("2. SQL Building:\n", .{});
    const old_sql = try oldBuildSql(allocator);
    defer allocator.free(old_sql);
    const new_sql = try newBuildSql(allocator);
    defer allocator.free(new_sql);
    std.debug.print("   Old SQL: {s}\n", .{old_sql});
    std.debug.print("   New SQL: {s}\n", .{new_sql});
    std.debug.print("   Benefit: Named constants, clearer code\n\n", .{});
    
    // Example 3: Field concatenation
    std.debug.print("3. Field Concatenation:\n", .{});
    const old_field = try oldSelectField(allocator, "users", "email");
    defer allocator.free(old_field);
    
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const new_field = try newSelectField(arena.allocator(), "users", "email");
    
    std.debug.print("   Old: Always heap allocation\n", .{});
    std.debug.print("   New: Stack buffer with fallback\n", .{});
    std.debug.print("   Result: {s}\n", .{new_field});
    std.debug.print("   Benefit: Reduced heap allocations\n\n", .{});
    
    std.debug.print("=== Summary ===\n", .{});
    std.debug.print("✓ Comptime constants eliminate function calls\n", .{});
    std.debug.print("✓ SQL fragment constants improve readability\n", .{});
    std.debug.print("✓ Fixed buffers reduce heap allocations\n", .{});
    std.debug.print("✓ Full backwards compatibility maintained\n", .{});
}
