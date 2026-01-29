// Database Pull CLI
// Command line tool for introspecting PostgreSQL databases and generating Zig models
//
// Usage: fluent-db-pull [options]
//
// Options:
//   --database-url <url>    PostgreSQL connection URL (or use DATABASE_URL env)
//   --schema <name>         Database schema to introspect (default: public)
//   --output <dir>          Output directory for generated models (default: src/models/generated)
//   --schemas-dir <dir>     Output directory for schema definitions (default: schemas)
//   --include <tables>      Comma-separated list of tables to include
//   --exclude <tables>      Comma-separated list of tables to exclude
//   --env-file <path>       Path to .env file (default: .env)
//   --no-schemas            Skip generating schema definition files
//   --report-only           Only print introspection report, don't generate files
//   --help                  Show this help message

const std = @import("std");
const pg = @import("pg");
const Env = @import("dotenv");

const introspection = @import("introspection/root.zig");

const CliOptions = struct {
    database_url: ?[]const u8 = null,
    schema_name: []const u8 = "public",
    output_dir: []const u8 = "src/models/generated",
    schemas_dir: []const u8 = "schemas",
    include_tables: ?[]const []const u8 = null,
    exclude_tables: []const []const u8 = &.{},
    env_file: []const u8 = ".env",
    generate_schemas: bool = true,
    report_only: bool = false,
    show_help: bool = false,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const options = try parseArgs(allocator, args);
    defer {
        if (options.include_tables) |tables| {
            allocator.free(tables);
        }
    }

    if (options.show_help) {
        printHelp(args[0]);
        return;
    }

    // Load environment variables from .env file
    var env = loadEnvFile(allocator, options.env_file);
    defer if (env) |*e| e.deinit();

    // Get database URL from options or environment
    const database_url = options.database_url orelse blk: {
        // Try dotenv first, then process env
        if (env) |*e| {
            if (e.get("DATABASE_URL")) |url| {
                break :blk url;
            }
        }
        break :blk std.posix.getenv("DATABASE_URL");
    } orelse {
        std.debug.print("Error: DATABASE_URL not provided. Use --database-url or set DATABASE_URL environment variable.\n", .{});
        std.debug.print("Run with --help for usage information.\n", .{});
        return error.MissingDatabaseUrl;
    };

    std.debug.print("🔍 Introspecting database...\n", .{});
    std.debug.print("   Schema: {s}\n", .{options.schema_name});
    std.debug.print("   Output: {s}\n\n", .{options.output_dir});

    // Create connection pool
    var pool = introspection.introspector.createPool(allocator, database_url) catch |err| {
        std.debug.print("❌ Failed to connect to database: {}\n", .{err});
        std.debug.print("   URL: {s}\n", .{database_url[0..@min(database_url.len, 50)]});
        return err;
    };
    defer pool.deinit();

    // Perform introspection
    const introspect_options = introspection.IntrospectorOptions{
        .schema_name = options.schema_name,
        .include_tables = options.include_tables,
        .exclude_tables = options.exclude_tables,
    };

    var intro = introspection.Introspector.init(allocator, pool, introspect_options);
    var db = intro.introspect() catch |err| {
        std.debug.print("❌ Introspection failed: {}\n", .{err});
        return err;
    };
    defer db.deinit();

    // Generate and print report
    const report = try introspection.generator.generateReport(allocator, &db);
    defer allocator.free(report);
    std.debug.print("{s}\n", .{report});

    if (options.report_only) {
        std.debug.print("✅ Report complete (--report-only mode, no files generated)\n", .{});
        return;
    }

    // Generate model files
    const gen_options = introspection.GeneratorOptions{
        .output_dir = options.output_dir,
        .generate_schemas = options.generate_schemas,
        .schema_output_dir = options.schemas_dir,
    };

    introspection.generator.generateModels(allocator, &db, gen_options) catch |err| {
        std.debug.print("❌ Failed to generate models: {}\n", .{err});
        return err;
    };

    std.debug.print("\n🎉 Database pull complete!\n", .{});
    std.debug.print("\n📋 Next steps:\n", .{});
    std.debug.print("   1. Review generated schema files in {s}/\n", .{options.schemas_dir});
    std.debug.print("   2. Run 'zig build generate-models' to generate model code\n", .{});
}

fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !CliOptions {
    var options = CliOptions{};
    var i: usize = 1;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            options.show_help = true;
            return options;
        } else if (std.mem.eql(u8, arg, "--database-url") or std.mem.eql(u8, arg, "-d")) {
            i += 1;
            if (i >= args.len) return error.MissingArgValue;
            options.database_url = args[i];
        } else if (std.mem.eql(u8, arg, "--schema") or std.mem.eql(u8, arg, "-s")) {
            i += 1;
            if (i >= args.len) return error.MissingArgValue;
            options.schema_name = args[i];
        } else if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= args.len) return error.MissingArgValue;
            options.output_dir = args[i];
        } else if (std.mem.eql(u8, arg, "--schemas-dir")) {
            i += 1;
            if (i >= args.len) return error.MissingArgValue;
            options.schemas_dir = args[i];
        } else if (std.mem.eql(u8, arg, "--include")) {
            i += 1;
            if (i >= args.len) return error.MissingArgValue;
            options.include_tables = try parseTableList(allocator, args[i]);
        } else if (std.mem.eql(u8, arg, "--exclude")) {
            i += 1;
            if (i >= args.len) return error.MissingArgValue;
            options.exclude_tables = try parseTableList(allocator, args[i]);
        } else if (std.mem.eql(u8, arg, "--env-file")) {
            i += 1;
            if (i >= args.len) return error.MissingArgValue;
            options.env_file = args[i];
        } else if (std.mem.eql(u8, arg, "--no-schemas")) {
            options.generate_schemas = false;
        } else if (std.mem.eql(u8, arg, "--report-only")) {
            options.report_only = true;
        } else {
            std.debug.print("Unknown option: {s}\n", .{arg});
            return error.UnknownOption;
        }
    }

    return options;
}

fn parseTableList(allocator: std.mem.Allocator, input: []const u8) ![]const []const u8 {
    var tables = std.ArrayList([]const u8){};
    errdefer tables.deinit(allocator);

    var iter = std.mem.splitSequence(u8, input, ",");
    while (iter.next()) |table| {
        const trimmed = std.mem.trim(u8, table, " \t");
        if (trimmed.len > 0) {
            try tables.append(allocator, trimmed);
        }
    }

    return tables.toOwnedSlice(allocator);
}

fn loadEnvFile(allocator: std.mem.Allocator, env_file: []const u8) ?Env {
    // Try to load .env file, return null if file doesn't exist
    return Env.initWithPath(allocator, env_file, 1024 * 1024, true) catch |err| {
        if (err != error.FileNotFound) {
            std.debug.print("Warning: Could not load {s}: {}\n", .{ env_file, err });
        }
        return null;
    };
}

fn printHelp(program_name: []const u8) void {
    std.debug.print(
        \\Usage: {s} [options]
        \\
        \\Database introspection tool for FluentORM. Connects to a PostgreSQL
        \\database, reads the schema, and generates Zig model definitions.
        \\
        \\Options:
        \\  --database-url, -d <url>   PostgreSQL connection URL
        \\                             (or set DATABASE_URL environment variable)
        \\  --schema, -s <name>        Database schema to introspect (default: public)
        \\  --output, -o <dir>         Output directory for generated models
        \\                             (default: src/models/generated)
        \\  --schemas-dir <dir>        Output directory for schema definitions
        \\                             (default: schemas)
        \\  --include <tables>         Comma-separated list of tables to include
        \\  --exclude <tables>         Comma-separated list of tables to exclude
        \\  --env-file <path>          Path to .env file (default: .env)
        \\  --no-schemas               Skip generating schema definition files
        \\  --report-only              Only print introspection report
        \\  --help, -h                 Show this help message
        \\
        \\Examples:
        \\  {s} --database-url postgresql://user:pass@localhost:5432/mydb
        \\  {s} --schema myschema --include users,posts,comments
        \\  {s} --exclude migrations,temp_data
        \\  {s} --report-only
        \\
        \\Environment Variables:
        \\  DATABASE_URL    PostgreSQL connection URL (used if --database-url not provided)
        \\
    , .{ program_name, program_name, program_name, program_name, program_name });
}
