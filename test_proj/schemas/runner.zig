const std = @import("std");
const registry = @import("registry.zig");
const fluentorm = @import("fluentorm");
const model_generator = fluentorm.model_generator;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Use merged schemas - multiple schema files with same table_name are combined
    const schemas = try registry.getAllSchemas(allocator);
    defer {
        for (schemas) |*s| s.deinit();
        allocator.free(schemas);
    }

    const output_dir = "src/models/generated";
    

    try std.fs.cwd().makePath(output_dir);


    // Generate models (always)
    for (schemas) |schema_item| {
        const schema_file = try std.fmt.allocPrint(allocator, "{s}.zig", .{schema_item.name});
        defer allocator.free(schema_file);
        try model_generator.generateModel(allocator, schema_item, schema_file, output_dir);
    }

    try model_generator.generateRegistryFile(allocator, schemas, output_dir);
    std.debug.print("Models generated in {s}\n", .{output_dir});
}
