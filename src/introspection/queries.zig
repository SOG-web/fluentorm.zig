// PostgreSQL System Catalog Queries for Database Introspection
// These queries extract schema information from PostgreSQL's information_schema and pg_catalog

const std = @import("std");

/// Query to get all user tables in a schema
pub const TABLES_QUERY =
    \\SELECT
    \\    table_name,
    \\    table_schema
    \\FROM information_schema.tables
    \\WHERE table_schema = $1
    \\    AND table_type = 'BASE TABLE'
    \\ORDER BY table_name
;

/// Query to get all columns for a table
pub const COLUMNS_QUERY =
    \\SELECT
    \\    c.column_name,
    \\    c.data_type,
    \\    c.udt_name,
    \\    c.is_nullable,
    \\    c.column_default,
    \\    c.is_identity,
    \\    c.identity_generation,
    \\    c.character_maximum_length,
    \\    c.numeric_precision,
    \\    c.numeric_scale,
    \\    c.ordinal_position
    \\FROM information_schema.columns c
    \\WHERE c.table_schema = $1
    \\    AND c.table_name = $2
    \\ORDER BY c.ordinal_position
;

/// Query to get primary key constraint for a table
pub const PRIMARY_KEY_QUERY =
    \\SELECT
    \\    tc.constraint_name,
    \\    kcu.column_name
    \\FROM information_schema.table_constraints tc
    \\JOIN information_schema.key_column_usage kcu
    \\    ON tc.constraint_name = kcu.constraint_name
    \\    AND tc.table_schema = kcu.table_schema
    \\WHERE tc.table_schema = $1
    \\    AND tc.table_name = $2
    \\    AND tc.constraint_type = 'PRIMARY KEY'
    \\ORDER BY kcu.ordinal_position
;

/// Query to get foreign key constraints for a table
pub const FOREIGN_KEYS_QUERY =
    \\SELECT
    \\    tc.constraint_name,
    \\    kcu.column_name,
    \\    ccu.table_schema AS foreign_table_schema,
    \\    ccu.table_name AS foreign_table_name,
    \\    ccu.column_name AS foreign_column_name,
    \\    rc.delete_rule,
    \\    rc.update_rule
    \\FROM information_schema.table_constraints tc
    \\JOIN information_schema.key_column_usage kcu
    \\    ON tc.constraint_name = kcu.constraint_name
    \\    AND tc.table_schema = kcu.table_schema
    \\JOIN information_schema.constraint_column_usage ccu
    \\    ON tc.constraint_name = ccu.constraint_name
    \\    AND tc.table_schema = ccu.table_schema
    \\JOIN information_schema.referential_constraints rc
    \\    ON tc.constraint_name = rc.constraint_name
    \\    AND tc.table_schema = rc.constraint_schema
    \\WHERE tc.table_schema = $1
    \\    AND tc.table_name = $2
    \\    AND tc.constraint_type = 'FOREIGN KEY'
    \\ORDER BY tc.constraint_name, kcu.ordinal_position
;

/// Query to get unique constraints for a table
pub const UNIQUE_CONSTRAINTS_QUERY =
    \\SELECT
    \\    tc.constraint_name,
    \\    kcu.column_name
    \\FROM information_schema.table_constraints tc
    \\JOIN information_schema.key_column_usage kcu
    \\    ON tc.constraint_name = kcu.constraint_name
    \\    AND tc.table_schema = kcu.table_schema
    \\WHERE tc.table_schema = $1
    \\    AND tc.table_name = $2
    \\    AND tc.constraint_type = 'UNIQUE'
    \\ORDER BY tc.constraint_name, kcu.ordinal_position
;

/// Query to get indexes for a table (using pg_catalog for more details)
pub const INDEXES_QUERY =
    \\SELECT
    \\    i.relname AS index_name,
    \\    a.attname AS column_name,
    \\    ix.indisunique AS is_unique,
    \\    ix.indisprimary AS is_primary,
    \\    am.amname AS index_type
    \\FROM pg_catalog.pg_class t
    \\JOIN pg_catalog.pg_index ix ON t.oid = ix.indrelid
    \\JOIN pg_catalog.pg_class i ON ix.indexrelid = i.oid
    \\JOIN pg_catalog.pg_namespace n ON t.relnamespace = n.oid
    \\JOIN pg_catalog.pg_am am ON i.relam = am.oid
    \\JOIN pg_catalog.pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
    \\WHERE n.nspname = $1
    \\    AND t.relname = $2
    \\    AND t.relkind = 'r'
    \\ORDER BY i.relname, array_position(ix.indkey, a.attnum)
;

/// Query to check if a schema exists
pub const SCHEMA_EXISTS_QUERY =
    \\SELECT EXISTS(
    \\    SELECT 1 FROM information_schema.schemata WHERE schema_name = $1
    \\) AS exists
;

/// Query to get all enum types in the database
pub const ENUM_TYPES_QUERY =
    \\SELECT
    \\    t.typname AS enum_name,
    \\    n.nspname AS schema_name,
    \\    e.enumlabel AS enum_value,
    \\    e.enumsortorder AS sort_order
    \\FROM pg_catalog.pg_type t
    \\JOIN pg_catalog.pg_namespace n ON t.typnamespace = n.oid
    \\JOIN pg_catalog.pg_enum e ON t.oid = e.enumtypid
    \\WHERE n.nspname = $1
    \\ORDER BY t.typname, e.enumsortorder
;

/// Query to get check constraints for a table
pub const CHECK_CONSTRAINTS_QUERY =
    \\SELECT
    \\    tc.constraint_name,
    \\    cc.check_clause
    \\FROM information_schema.table_constraints tc
    \\JOIN information_schema.check_constraints cc
    \\    ON tc.constraint_name = cc.constraint_name
    \\    AND tc.constraint_schema = cc.constraint_schema
    \\WHERE tc.table_schema = $1
    \\    AND tc.table_name = $2
    \\    AND tc.constraint_type = 'CHECK'
    \\    AND tc.constraint_name NOT LIKE '%_not_null'
    \\ORDER BY tc.constraint_name
;

/// Default schema to introspect
pub const DEFAULT_SCHEMA = "public";

/// Tables to exclude from introspection (system/migration tables)
pub const EXCLUDED_TABLES = [_][]const u8{
    "schema_migrations",
    "_prisma_migrations",
    "knex_migrations",
    "knex_migrations_lock",
    "typeorm_metadata",
    "ar_internal_metadata",
    "schema_migrations",
    "__diesel_schema_migrations",
    "flyway_schema_history",
    "databasechangelog",
    "databasechangeloglock",
};

/// Check if a table should be excluded from introspection
pub fn isExcludedTable(table_name: []const u8) bool {
    for (EXCLUDED_TABLES) |excluded| {
        if (std.mem.eql(u8, table_name, excluded)) {
            return true;
        }
    }
    return false;
}
