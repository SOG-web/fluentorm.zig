# FluentORM Comptime & Runtime Optimization Analysis

## Executive Summary

FluentORM already uses several comptime optimizations (SQL string generation, field enums, type validation). This document identifies additional opportunities for comptime optimization and runtime performance improvements.

---

## ✅ Already Optimized (Good Patterns Found)

### 1. Static SQL Strings (Comptime)
The generated models already use comptime string literals for INSERT/UPDATE/UPSERT:
```zig
pub fn insertSQL() []const u8 {
    return \\INSERT INTO users (email, name, ...) VALUES ($1, $2, ...) RETURNING id;
}
```
**No change needed** - these are already resolved at compile time.

### 2. Field Enums (Comptime)
Field and relation enums are generated at compile time:
```zig
pub const FieldEnum = enum { id, email, name, ... };
pub const RelationEnum = enum { posts, comments };
```

### 3. Type Validation (Comptime)
`@hasDecl` checks happen at compile time:
```zig
if (!@hasDecl(T, "tableName")) {
    @compileError("Model must implement 'tableName() []const u8'");
}
```

---

## 🔧 Optimization Opportunities

### 1. **Query Builder Arena Allocator** (HIGH IMPACT)

**Current Issue:**
```zig
pub fn init() Self {
    return Self{
        .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
        // ...
    };
}
```
Using `page_allocator` directly has overhead for each allocation.

**Recommended Fix:**
Allow passing a custom allocator or use a fixed buffer for small queries:
```zig
pub fn init() Self {
    return initWithAllocator(std.heap.page_allocator);
}

pub fn initWithAllocator(backing_allocator: std.mem.Allocator) Self {
    return Self{
        .arena = std.heap.ArenaAllocator.init(backing_allocator),
        // ...
    };
}
```

**Location:** [src/model_gen/query.zig](file:///c:/Users/SOG/Documents/GitHub/fluentorm.zig/src/model_gen/query.zig) lines 151-170

---

### 2. **Comptime Table Name Strings** (MEDIUM IMPACT)

**Current Issue:**
`tableName()` is a function call, evaluated at runtime:
```zig
pub fn tablename(_: *Self) []const u8 {
    return Model.tableName();
}
```

**Recommended Fix:**
Make it a comptime constant:
```zig
pub const table_name = Model.tableName();
```

And use `@This().table_name` instead of `self.tablename()`.

**Location:** [src/model_gen/query.txt](file:///c:/Users/SOG/Documents/GitHub/fluentorm.zig/src/model_gen/query.txt) line 152-154

---

### 3. **Precomputed Static SQL Fragments** (MEDIUM IMPACT)

**Current Issue:**
Static fragments like `"SELECT "`, `" FROM "`, `" WHERE "` are repeated:
```zig
try sql.appendSlice(allocator, "SELECT ");
try sql.appendSlice(allocator, " FROM ");
try sql.appendSlice(allocator, " WHERE ");
```

**Recommended Fix:**
Use comptime string constants:
```zig
const SQL_SELECT = "SELECT ";
const SQL_FROM = " FROM ";
const SQL_WHERE = " WHERE ";
// use: try sql.appendSlice(allocator, SQL_SELECT);
```
This is already optimized by the compiler, but explicit constants improve readability.

---

### 4. **Comptime Base SELECT Clause** (HIGH IMPACT)

**Current Issue:**
The base `SELECT table.* FROM table` is built at runtime:
```zig
try sql.writer(allocator).print("{s}.*", .{table_name});
try sql.writer(allocator).print(" FROM {s} ", .{table_name});
```

**Recommended Fix:**
Pre-generate base SELECT clause at comptime:
```zig
// In generated model.zig
pub const base_select = "SELECT users.* FROM users";
pub const base_select_prefix = "SELECT users.*, ";

// In buildSql:
if (!has_custom_select and join_clauses.items.len == 0) {
    try sql.appendSlice(allocator, Model.base_select);
} else {
    // ... dynamic construction
}
```

**Location:** [src/model_gen/model.zig](file:///c:/Users/SOG/Documents/GitHub/fluentorm.zig/src/model_gen/model.zig) - add base_select generation

---

### 5. **Reuse Query Builder Instances** (HIGH IMPACT)

**Current Issue:**
Each query creates new ArrayLists:
```zig
var query = Users.query();  // allocates multiple ArrayLists
defer query.deinit();       // deallocates all
```

**Recommended Pattern:**
Add a `reset()` method (already exists) but document/encourage reuse:
```zig
// Efficient pattern for multiple queries:
var query = Users.query();
defer query.deinit();

const result1 = try query.where(...).fetch(db, allocator, .{});
query.reset();  // Clear state, reuse memory
const result2 = try query.where(...).fetch(db, allocator, .{});
```

---

### 6. **Avoid fmt.allocPrint for Simple Concatenation** (LOW IMPACT)

**Current Issue:**
Using `fmt.allocPrint` for simple string concatenation:
```zig
const _field = std.fmt.allocPrint(
    self.arena.allocator(),
    "{s}.{s}",
    .{ self.tablename(), @tagName(field) },
) catch return;
```

**Alternative:** For known-length strings, use fixed buffers:
```zig
var buf: [128]u8 = undefined;
const field_str = std.fmt.bufPrint(&buf, "{s}.{s}", .{table_name, @tagName(field)}) catch return;
```
However, this requires knowing max length. Keep current approach for flexibility.

---

### 7. **Lazy ArrayList Initialization** (MEDIUM IMPACT)

**Current Issue:**
All ArrayLists are initialized in `init()` even if unused:
```zig
.join_clauses = std.ArrayList(JoinClause){},
.having_clauses = std.ArrayList([]const u8){},
```

**Recommended Fix:**
Use null/optional ArrayLists:
```zig
join_clauses: ?std.ArrayList(JoinClause) = null,

// In join():
if (self.join_clauses == null) {
    self.join_clauses = std.ArrayList(JoinClause){};
}
self.join_clauses.?.append(...)
```
This avoids allocations for simple queries that don't use JOINs/HAVING.

---

### 8. **Comptime Operator SQL Strings** (ALREADY OPTIMIZED)

The `Operator.toSql()` already uses comptime switch:
```zig
pub fn toSql(self: Operator) []const u8 {
    return switch (self) {
        .eq => "=",
        .neq => "!=",
        // ...
    };
}
```
**No change needed** - compiler optimizes this.

---

## 📊 Priority Matrix

| Optimization | Impact | Effort | Priority |
|-------------|--------|--------|----------|
| Comptime base SELECT | High | Low | 🔴 P1 |
| Custom allocator support | High | Low | 🔴 P1 |
| Query builder reuse docs | High | Minimal | 🔴 P1 |
| Comptime table_name const | Medium | Low | 🟡 P2 |
| Lazy ArrayList init | Medium | Medium | 🟡 P2 |
| SQL fragment constants | Low | Minimal | 🟢 P3 |

---

## Implementation Recommendations

### Phase 1: Quick Wins (< 1 hour)
1. Add `base_select` comptime constant to generated models
2. Change `tablename()` to `const table_name`
3. Document query builder reuse pattern

### Phase 2: Structural Improvements (2-4 hours)
1. Add custom allocator support to query builder `init()`
2. Implement lazy ArrayList initialization
3. Add comptime validation for common query patterns

### Phase 3: Advanced (Future)
1. Query plan caching for repeated queries
2. Prepared statement reuse
3. Connection-level query caching
