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

### 1. ✅ DONE - **Query Builder Arena Allocator** (HIGH IMPACT)

**Implemented:** Added `initWithAllocator()` and `initWithArena()` methods:
```zig
// Default - uses page_allocator
var query = Users.query();

// Custom backing allocator
var query = Users.queryWithAllocator(gpa.allocator());

// Existing arena (http.zig use case)
var query = Users.queryWithArena(request.arena);
```

---

### 2. **Comptime Table Name Strings** (MEDIUM IMPACT) - TODO

Make `tablename()` a comptime constant instead of function call.

---

### 3. **Comptime Base SELECT Clause** (HIGH IMPACT) - TODO

Pre-generate `"SELECT users.* FROM users"` at compile time.

---

### 4. ✅ DONE - **Reuse Query Builder Instances** (HIGH IMPACT)

**Documented:** Added to `docs/QUERY.md` with examples showing `reset()` usage.

---

### 5. **Lazy ArrayList Initialization** (MEDIUM IMPACT) - TODO

Only allocate `join_clauses`, `having_clauses` when actually used.

---

## 📊 Priority Matrix

| Optimization | Impact | Status |
|-------------|--------|--------|
| Custom allocator support | High | ✅ DONE |
| Query builder reuse docs | High | ✅ DONE |
| Comptime base SELECT | High | 🔴 TODO |
| Comptime table_name const | Medium | 🟡 TODO |
| Lazy ArrayList init | Medium | 🟡 TODO |

---

## Implementation Recommendations

### Phase 1: Quick Wins
1. ~~Custom allocator support~~ ✅ DONE
2. ~~Query builder reuse docs~~ ✅ DONE
3. Add `base_select` comptime constant
4. Change `tablename()` to `const table_name`

### Phase 2: Structural Improvements
1. Implement lazy ArrayList initialization
2. Add comptime validation for common query patterns

### Phase 3: Advanced (Future)
1. Query plan caching for repeated queries
2. Prepared statement reuse
3. Connection-level query caching
