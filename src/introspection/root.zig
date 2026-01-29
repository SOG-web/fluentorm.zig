// Database Introspection Module
// Provides functionality to introspect PostgreSQL databases and generate Zig models

pub const types = @import("types.zig");
pub const queries = @import("queries.zig");
pub const introspector = @import("introspector.zig");
pub const converter = @import("converter.zig");
pub const generator = @import("generator.zig");

// Re-export main types for convenience
pub const IntrospectedDatabase = types.IntrospectedDatabase;
pub const IntrospectedTable = types.IntrospectedTable;
pub const IntrospectedColumn = types.IntrospectedColumn;
pub const IntrospectedForeignKey = types.IntrospectedForeignKey;
pub const IntrospectedIndex = types.IntrospectedIndex;

pub const Introspector = introspector.Introspector;
pub const IntrospectorOptions = introspector.IntrospectorOptions;
pub const IntrospectorError = introspector.IntrospectorError;

pub const ConversionOptions = converter.ConversionOptions;
pub const GeneratorOptions = generator.GeneratorOptions;

/// Convenience function to perform full db pull operation
pub fn dbPull(
    allocator: std.mem.Allocator,
    database_url: []const u8,
    output_options: GeneratorOptions,
    introspect_options: IntrospectorOptions,
) !void {
    // Create connection pool
    var pool = try introspector.createPool(allocator, database_url);
    defer pool.deinit();

    // Perform introspection
    var intro = Introspector.init(allocator, pool, introspect_options);
    var db = try intro.introspect();
    defer db.deinit();

    // Print report
    const report = try generator.generateReport(allocator, &db);
    defer allocator.free(report);
    std.debug.print("{s}\n", .{report});

    // Generate model files
    try generator.generateModels(allocator, &db, output_options);
}

const std = @import("std");

test "introspection module" {
    // Basic compile test
    _ = types;
    _ = queries;
    _ = introspector;
    _ = converter;
    _ = generator;
}
