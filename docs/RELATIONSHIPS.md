# Relationships

This guide details how to define and use relationships between tables using FluentORM's TableSchema API.

## Overview

Relationships define how tables reference each other using foreign keys. FluentORM generates helper methods for navigating between related models, making it easy to fetch associated data.

FluentORM uses **efficient correlated subqueries with JSONB aggregation** for `hasMany` relationships to prevent Cartesian products and maintain query performance.

## Defining Relationships

FluentORM provides **convenience methods** for common relationship types, plus the generic `t.foreign()` method for advanced use cases.

### Quick Reference

| Relationship | Method           | Description                                              |
| ------------ | ---------------- | -------------------------------------------------------- |
| Many-to-One  | `t.belongsTo()`  | This table has a FK to another table (e.g., post → user) |
| One-to-One   | `t.hasOne()`     | This table has a unique FK to another table              |
| One-to-Many  | `t.hasMany()`    | Another table has FKs pointing to this table             |
| Many-to-Many | `t.manyToMany()` | Junction table relationship                              |
| Generic      | `t.foreign()`    | Low-level method with full control                       |

### Using Convenience Methods

```zig
pub fn build(t: *TableSchema) void {
    // ... other fields ...

    t.uuid(.{ .name = "user_id" }); // Foreign key column

    // Define the relationship using convenience method
    t.belongsTo(.{
        .name = "post_author",
        .column = "user_id",
        .references_table = "users",
        .on_delete = .cascade,
    });
}
```

### Using the Generic Foreign Method

```zig
pub fn build(t: *TableSchema) void {
    // ... other fields ...

    t.uuid(.{ .name = "user_id" }); // Foreign key column

    // Define the relationship using generic method
    t.foreign(.{
        .name = "post_author",
        .column = "user_id",
        .references_table = "users",
        .references_column = "id",
        .relationship_type = .many_to_one,
        .on_delete = .cascade,
    });
}
```

## Foreign Key Configuration

The `.foreign()` method accepts these options:

| Property            | Type   | Required | Description                                                       |
| ------------------- | ------ | -------- | ----------------------------------------------------------------- |
| `name`              | string | **Yes**  | Unique name for the relationship (used in generated method names) |
| `column`            | string | **Yes**  | Column in the current table that holds the foreign key            |
| `references_table`  | string | **Yes**  | Name of the target table                                          |
| `references_column` | string | **Yes**  | Column in the target table (usually `"id"`)                       |
| `relationship_type` | enum   | **Yes**  | Type of relationship (see below)                                  |
| `on_delete`         | enum   | No       | Action when referenced record is deleted (default: `.no_action`)  |
| `on_update`         | enum   | No       | Action when referenced record is updated (default: `.no_action`)  |

## Relationship Types

### Many-to-One (belongsTo)

The current table has a foreign key pointing to another table. This is the most common relationship type.

**Example**: Many posts belong to one user.

```zig
// In schemas/02_posts.zig
pub fn build(t: *TableSchema) void {
    t.uuid(.{ .name = "id", .primary_key = true });
    t.string(.{ .name = "title" });
    t.uuid(.{ .name = "user_id" }); // Foreign key

    // Using convenience method (recommended)
    t.belongsTo(.{
        .name = "post_author",
        .column = "user_id",
        .references_table = "users",
        .on_delete = .cascade,
    });
}
```

**belongsTo Options**:

| Option              | Type   | Default      | Description                              |
| ------------------- | ------ | ------------ | ---------------------------------------- |
| `name`              | string | **required** | Relationship name (used in method names) |
| `column`            | string | **required** | FK column in this table                  |
| `references_table`  | string | **required** | Target table name                        |
| `references_column` | string | `"id"`       | Target column (usually PK)               |
| `on_delete`         | enum   | `.no_action` | Action on parent delete                  |
| `on_update`         | enum   | `.no_action` | Action on parent update                  |

**Generated SQL**:

```sql
CONSTRAINT fk_post_author FOREIGN KEY (user_id)
REFERENCES users(id)
ON DELETE CASCADE
```

**Generated Method**:

```zig
// Fetch the user who authored this post
const author = try post.fetchPostAuthor(&pool, allocator);
defer if (author) |a| allocator.free(a);
```

### One-to-Many (hasMany)

One record in the current table can be referenced by multiple records in another table. Use the `hasMany()` method to define this relationship.

**Example**: One user has many posts.

```zig
// In schemas/01_users.zig
pub fn build(t: *TableSchema) void {
    t.uuid(.{ .name = "id", .primary_key = true });
    t.string(.{ .name = "name" });

    // Define one-to-many relationship using hasMany()
    // Note: The FK constraint is in the posts table, not here
    // This is metadata for generating fetch methods and includes
    t.hasMany(.{
        .name = "user_posts",
        .foreign_table = "posts",
        .foreign_column = "user_id",
    });

    // You can define multiple hasMany relationships
    t.hasMany(.{
        .name = "user_comments",
        .foreign_table = "comments",
        .foreign_column = "user_id",
    });
}
```

**Generated Methods**:

```zig
// Fetch all posts by this user
const posts = try user.fetchPosts(&pool, allocator);
defer allocator.free(posts);

// Fetch all comments by this user
const comments = try user.fetchComments(&pool, allocator);
defer allocator.free(comments);
```

**hasMany Options**:

| Option           | Type   | Description                                        |
| ---------------- | ------ | -------------------------------------------------- |
| `name`           | string | Relationship name (used to generate method suffix) |
| `foreign_table`  | string | The child table that has the FK                    |
| `foreign_column` | string | The FK column in the child table                   |

> [!NOTE] > `hasMany()` does not create a FK constraint. The FK constraint should be defined in the child table using `belongsTo()` or `foreign()`.

#### Define Multiple hasMany at Once

```zig
t.hasManyList(&.{
    .{ .name = "user_posts", .foreign_table = "posts", .foreign_column = "user_id" },
    .{ .name = "user_comments", .foreign_table = "comments", .foreign_column = "user_id" },
});
```

### One-to-One (hasOne)

A strict one-to-one mapping between two tables.

**Example**: One user has one profile.

```zig
// In schemas/02_profiles.zig
pub fn build(t: *TableSchema) void {
    t.uuid(.{ .name = "id", .primary_key = true });
    t.uuid(.{ .name = "user_id", .unique = true }); // Unique constraint enforces 1:1
    t.string(.{ .name = "bio" });

    // Using convenience method (recommended)
    t.hasOne(.{
        .name = "profile_user",
        .column = "user_id",
        .references_table = "users",
        .on_delete = .cascade,
    });
}
```

**Generated Method**:

```zig
// Returns a single user or null
const user = try profile.fetchProfileUser(&pool, allocator);
defer if (user) |u| allocator.free(u);
```

**hasOne Options**:

| Option              | Type   | Default      | Description             |
| ------------------- | ------ | ------------ | ----------------------- |
| `name`              | string | **required** | Relationship name       |
| `column`            | string | **required** | FK column in this table |
| `references_table`  | string | **required** | Target table name       |
| `references_column` | string | `"id"`       | Target column           |
| `on_delete`         | enum   | `.no_action` | Action on parent delete |
| `on_update`         | enum   | `.no_action` | Action on parent update |

### Many-to-Many (manyToMany)

Many-to-many relationships require a junction (join) table. Use `manyToMany()` to define the relationship on the junction table.

**Example**: Posts can have multiple categories, and categories can have multiple posts.

```zig
// Junction table: schemas/05_post_categories.zig
pub fn build(t: *TableSchema) void {
    t.uuid(.{ .name = "id", .primary_key = true });
    t.uuid(.{ .name = "post_id" });
    t.uuid(.{ .name = "category_id" });

    // Using manyToMany convenience method
    t.manyToMany(.{
        .name = "post_category_post",
        .column = "post_id",
        .references_table = "posts",
        .references_column = "id",
    });

    t.manyToMany(.{
        .name = "post_category_category",
        .column = "category_id",
        .references_table = "categories",
        .references_column = "id",
    });
}
```

**manyToMany Options**:

| Option              | Type   | Default      | Description                 |
| ------------------- | ------ | ------------ | --------------------------- |
| `name`              | string | **required** | Relationship name           |
| `column`            | string | **required** | FK column in junction table |
| `references_table`  | string | **required** | Target table name           |
| `references_column` | string | **required** | Target column               |
| `on_delete`         | enum   | `.cascade`   | Action on parent delete     |
| `on_update`         | enum   | `.no_action` | Action on parent update     |

To query many-to-many relationships, you'll need to join through the junction table using the query builder.

```zig
// Get all categories for a post
var query = PostCategory.query();
defer query.deinit();

const post_cats = try query
    .where(.{ .field = .post_id, .operator = .eq, .value = .{ .string = "$1" } })
    .fetch(&pool, allocator, .{post_id});
defer allocator.free(post_cats);

for (post_cats) |pc| {
    if (try pc.fetchPostCategoryCategory(&pool, allocator)) |cat| {
        defer allocator.free(cat);
        std.debug.print("Category: {s}\n", .{cat.name});
    }
}
```

## Efficient hasMany Implementation

### How hasMany Prevents Cartesian Products

FluentORM uses **correlated subqueries with JSONB aggregation** instead of traditional JOINs for `hasMany` relationships. This prevents Cartesian products that would otherwise multiply rows.

**Traditional JOIN (❌ Creates Cartesian Product)**:

```sql
-- If a user has 10 posts and 100 comments, this returns 1000 rows
SELECT users.*, posts.*, comments.*
FROM users
LEFT JOIN posts ON posts.user_id = users.id
LEFT JOIN comments ON comments.user_id = users.id
WHERE users.id = $1
```

**FluentORM Subquery Approach (✅ Returns 1 Row)**:

```sql
SELECT users.*,
  (SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id,
    'title', title,
    'created_at', (extract(epoch from created_at) * 1000000)::bigint,
    ...
  )), '[]'::jsonb)
   FROM posts
   WHERE posts.user_id = users.id) AS posts,
  (SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id,
    'content', content,
    ...
  )), '[]'::jsonb)
   FROM comments
   WHERE comments.user_id = users.id) AS comments
FROM users
WHERE users.id = $1
```

### Timestamp Handling in JSON Aggregations

Timestamps are automatically cast to **microsecond epochs** in JSONB aggregations for compatibility with Zig's `i64` type:

```sql
'created_at', (extract(epoch from created_at) * 1000000)::bigint
```

This ensures proper JSON serialization and parsing without data loss.

### Custom Field Selection

You can specify which fields to include in relationships:

```zig
var query = Users.query();
defer query.deinit();

_ = query.include(.{
    .posts = .{
        .model_name = .posts,
        .select = &.{ "id", "title", "created_at" }  // Only these fields
    }
});

// Generate SQL with only selected fields in the jsonb_build_object
const users = try query.fetchWithRel(
    Users.Rel.UsersWithPosts,
    &pool,
    allocator,
    .{}
);
```

### Filtering Related Data

Add WHERE clauses to included relationships:

```zig
var query = Users.query();
defer query.deinit();

_ = query.include(.{
    .comments = .{
        .model_name = .comments,
        .where = &.{.{
            .where_type = .@"and",
            .field = .is_approved,
            .operator = .eq,
            .value = .{ .boolean = true }
        }}
    }
});

const users = try query.fetchWithRel(
    Users.Rel.UsersWithComments,
    &pool,
    allocator,
    .{}
);
// Only approved comments are loaded
```

## Multiple Includes

Load multiple relationships in a single query efficiently:

### Using fetchWithRel (Typed Parsing)

```zig
var query = Users.query();
defer query.deinit();

_ = query
    .include(.{ .posts = .{ .model_name = .posts } })
    .include(.{ .comments = .{ .model_name = .comments } });

const users = try query.fetchWithRel(
    Users.Rel.UsersWithAllRelations,  // Generated type with all relations
    &pool,
    allocator,
    .{}
);
defer allocator.free(users);

for (users) |user| {
    std.debug.print("User: {s}\n", .{user.name});

    if (user.posts) |posts| {
        std.debug.print("  Posts: {d}\n", .{posts.len});
        for (posts) |post| {
            std.debug.print("    - {s}\n", .{post.title});
        }
    }

    if (user.comments) |comments| {
        std.debug.print("  Comments: {d}\n", .{comments.len});
    }
}
```

### Using fetchAs (Custom Projections)

For custom handling or when you only need specific fields:

```zig
const UserWithJsonRelations = struct {
    name: []const u8,
    posts: ?[]const u8,     // Raw JSONB string
    comments: ?[]const u8,  // Raw JSONB string
};

var query = Users.query();
defer query.deinit();

_ = query
    .select(&.{.name})
    .include(.{ .posts = .{ .model_name = .posts } })
    .include(.{ .comments = .{ .model_name = .comments } });

const results = try query.fetchAs(UserWithJsonRelations, &pool, allocator, .{});
defer allocator.free(results);

for (results) |res| {
    std.debug.print("User: {s}\n", .{res.name});
    std.debug.print("  Posts JSON: {s}\n", .{res.posts orelse "[]"});
    std.debug.print("  Comments JSON: {s}\n", .{res.comments orelse "[]"});
}
```

## Referential Actions

Control what happens when a referenced record is deleted or updated:

| Action         | Description                                            |
| -------------- | ------------------------------------------------------ |
| `.cascade`     | Delete/update dependent rows automatically             |
| `.set_null`    | Set the foreign key to NULL                            |
| `.set_default` | Set the foreign key to its default value               |
| `.restrict`    | Prevent the change if there are dependent rows         |
| `.no_action`   | Similar to RESTRICT, but checks are deferred (default) |

**Example with CASCADE**:

```zig
t.foreign(.{
    .name = "post_author",
    .column = "user_id",
    .references_table = "users",
    .references_column = "id",
    .relationship_type = .many_to_one,
    .on_delete = .cascade, // Delete all posts when user is deleted
});
```

**Example with SET NULL**:

```zig
t.foreign(.{
    .name = "post_author",
    .column = "user_id",
    .references_table = "users",
    .references_column = "id",
    .relationship_type = .many_to_one,
    .on_delete = .set_null, // Set user_id to NULL when user is deleted
});

// Make sure the column is nullable!
t.uuid(.{ .name = "user_id", .not_null = false });
```

## Using Generated Relationship Methods

When you define a relationship, FluentORM generates `fetch*` methods on your model.

### Method Naming

| Definition                                      | Generated Method      | Return Type    |
| ----------------------------------------------- | --------------------- | -------------- |
| `belongsTo(.{ .name = "post_author", ... })`    | `fetchPostAuthor()`   | `!?Users`      |
| `hasOne(.{ .name = "profile_user", ... })`      | `fetchProfileUser()`  | `!?Users`      |
| `hasMany(.{ .name = "user_posts", ... })`       | `fetchPosts()`        | `![]Posts`     |
| `manyToMany(.{ .name = "post_category", ... })` | `fetchPostCategory()` | `!?Categories` |

### Example: Fetch Related Records

```zig
const std = @import("std");
const pg = @import("pg");
const models = @import("models/generated/root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}();
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Setup database connection
    var pool = try pg.Pool.init(allocator, .{
        .size = 5,
        .connect = .{ .host = "localhost", .port = 5432 },
        .auth = .{ .username = "postgres", .password = "password", .database = "mydb" },
    });
    defer pool.deinit();

    // Fetch a post
    const post = (try models.Posts.findById(&pool, allocator, post_id)).?;
    defer allocator.free(post);

    // Fetch the author using belongsTo relationship
    if (try post.fetchUser(&pool, allocator)) |author| {
        defer allocator.free(author);
        std.debug.print("Post authored by: {s}\n", .{author.name});
    }

    // Fetch a user
    const user = (try models.Users.findById(&pool, allocator, user_id)).?;
    defer allocator.free(user);

    // Fetch all posts by this user using hasMany relationship
    const user_posts = try user.fetchPosts(&pool, allocator);
    defer allocator.free(user_posts);

    for (user_posts) |p| {
        std.debug.print("Post: {s}\n", .{p.title});
    }

    // Fetch all comments by this user
    const user_comments = try user.fetchComments(&pool, allocator);
    defer allocator.free(user_comments);
}
```

## Naming Conventions

The generated method name depends on the relationship type:

### For belongsTo, hasOne, manyToMany

- **Pattern**: `fetch{PascalCaseRelationshipName}`
- **Example**: `name = "post_author"` → `fetchPostAuthor()`

### For hasMany

- **Pattern**: `fetch{PascalCaseForeignTable}` (derived from relationship name)
- **Example**: `name = "user_posts"` → `fetchPosts()`

Choose descriptive relationship names that reflect the domain relationship:

```zig
// Good names for belongsTo/hasOne
.name = "post_author"      // fetchPostAuthor() -> returns ?Users
.name = "order_customer"   // fetchOrderCustomer() -> returns ?Customers

// Good names for hasMany
.name = "user_posts"       // fetchPosts() -> returns []Posts
.name = "category_products" // fetchProducts() -> returns []Products

// Avoid generic names
.name = "relation1"        // fetchRelation1() (unclear)
```

### Model Naming

Generated model struct names use **PascalCase plural** form:

| Table Name        | Struct Name      | Import                           |
| ----------------- | ---------------- | -------------------------------- |
| `users`           | `Users`          | `@import("users.zig")`           |
| `posts`           | `Posts`          | `@import("posts.zig")`           |
| `post_categories` | `PostCategories` | `@import("post_categories.zig")` |

## Complex Queries with Relationships

For more complex queries involving relationships, use the query builder:

```zig
// Find all posts by a specific user
var query = models.Posts.query();
defer query.deinit();

const user_posts = try query
    .where(.{ .field = .user_id, .operator = .eq, .value = .{ .string = "$1" } })
    .orderBy(.{ .field = .created_at, .direction = .desc })
    .fetch(&pool, allocator, .{user_id});
defer allocator.free(user_posts);
```

See [QUERY.md](QUERY.md) for more details on the query builder.

## Explicit Relation Types (rel.zig)

FluentORM generates explicit relation types in `rel.zig` for each model. These types provide **full IntelliSense support** for eager-loaded relations.

### Generated Types

For a model with relations, the generator creates:

```
src/models/generated/users/
├── model.zig    # Base model
├── rel.zig      # Relation types (UsersWithPosts, etc.)
└── query.zig    # Query builder
```

Each `rel.zig` contains:

| Type                    | Description                                   |
| ----------------------- | --------------------------------------------- |
| `UsersWithPosts`        | User model with `posts: ?[]Posts` field       |
| `UsersWithComments`     | User model with `comments: ?[]Comments` field |
| `UsersWithAllRelations` | User model with all relation fields           |

### Accessing Relation Types

Access via the model's `Rel` namespace:

```zig
const Users = @import("models/generated/users/model.zig");

// Individual relation types
const UsersWithPosts = Users.Rel.UsersWithPosts;
const UsersWithComments = Users.Rel.UsersWithComments;

// All relations at once
const UsersWithAllRelations = Users.Rel.UsersWithAllRelations;
```

Or via the registry:

```zig
const Client = @import("models/generated/registry.zig").Client;

const UsersWithPosts = Client.Rel.Users.UsersWithPosts;
```

### Using with Eager Loading

Use `fetchWithRel` or `firstWithRel` to load relations with automatic JSONB parsing:

```zig
const UsersWithPosts = Users.Rel.UsersWithPosts;

var query = Users.query();
defer query.deinit();

// Eager load posts
const users = try query
    .include(.{ .posts = .{ .model_name = .posts } })
    .fetchWithRel(UsersWithPosts, &pool, allocator, .{});
defer allocator.free(users);

for (users) |user| {
    std.debug.print("User: {s}\n", .{user.name});

    // Full IntelliSense on user.posts!
    if (user.posts) |posts| {
        for (posts) |post| {
            std.debug.print("  - {s}\n", .{post.title});
        }
    }
}
```

### Helper Methods

Each relation type provides:

| Method                    | Description                                            |
| ------------------------- | ------------------------------------------------------ |
| `fromBase(model)`         | Convert base model to relation type (relations = null) |
| `toBase(self)`            | Extract base model from relation type                  |
| `fromRow(row, allocator)` | Parse database row with JSONB relation columns         |

```zig
// Convert base model to relation type
const base_user = try Users.findById(&pool, allocator, id);
var user_with_posts = UsersWithPosts.fromBase(base_user.?);

// Manually set posts if needed
user_with_posts.posts = some_posts;

// Convert back to base model
const base = user_with_posts.toBase();
```

## Type Safety

All relationship methods are fully type-safe:

- Return types match the referenced model
- Relationship names are checked at compile time
- Foreign key types are validated

If you try to call a relationship method that doesn't exist, you'll get a compile-time error.
