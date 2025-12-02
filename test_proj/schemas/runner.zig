const std = @import("std");
const registry = @import("registry.zig");
const fluentorm = @import("fluentorm");
const sql_generator = fluentorm.sql_generator;
const model_generator = fluentorm.model_generator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Use merged schemas - multiple schema files with same table_name are combined
    const schemas = try registry.getAllSchemasMerged(allocator);
    defer {
        for (schemas) |*s| s.deinit();
        allocator.free(schemas);
    }

    const output_dir = "src/models/generated";
    const sql_output_dir = "migrations";

    try std.fs.cwd().makePath(output_dir);
    try std.fs.cwd().makePath(sql_output_dir);

    for (schemas, 0..) |schema, i| {
        // Use schema name as the source file name for comments
        const schema_file = try std.fmt.allocPrint(allocator, "{s}.zig", .{schema.name});
        defer allocator.free(schema_file);

        // Use index as file prefix for now (will be replaced by migration system)
        const file_prefix = try std.fmt.allocPrint(allocator, "{d:0>2}", .{i + 1});
        defer allocator.free(file_prefix);

        try sql_generator.writeSchemaToFile(allocator, schema, sql_output_dir, file_prefix);
        try model_generator.generateModel(allocator, schema, schema_file, output_dir);
    }

    try model_generator.generateBarrelFile(allocator, schemas, output_dir);
}
