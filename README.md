# Zig Model Generator

A powerful, standalone tool that automatically generates type-safe Zig database models from JSON schema definitions.

## 🚀 Features

- **Zero Configuration**: Auto-discovers schemas, no manual registration needed.
- **Type-Safe**: Generates strongly typed Zig structs and CRUD operations.
- **Self-Contained**: Generated code includes all necessary dependencies (bundles `base.zig`).
- **Runtime Validation**: Validates schemas before generation to prevent errors.
- **PostgreSQL Support**: Built on top of `pg.zig`.
- **Flexible Integration**: Use as a CLI tool, Git submodule, or Zig package.

## 📦 Installation

### Option 1: Standalone Binary (Recommended for CLI usage)

Install the binary to your system:

```bash
# Clone the repo
git clone https://github.com/your/zig-model-gen
cd zig-model-gen

# Install to ~/.local/bin (or /usr/local/bin)
bash install.sh
```

### Option 2: Zig Package (Recommended for Projects)

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .model_gen = .{
        .url = "https://github.com/your/zig-model-gen/archive/<COMMIT_HASH>.tar.gz",
        .hash = "<PACKAGE_HASH>",
    },
    // You also need pg.zig for the generated models
    .pg = .{
        .url = "https://github.com/karlseguin/pg.zig/archive/<COMMIT_HASH>.tar.gz",
        .hash = "...",
    },
},
```

## 🛠 Usage

### CLI Commands

```bash
# Basic usage: zig-model-gen <schemas_dir> [output_dir]

# Generate models from 'schemas/' to 'src/models/'
zig-model-gen schemas src/models

# Specify custom output directory
zig-model-gen schemas src/db/generated
```

### Writing Schemas

Create JSON files in your schemas directory (e.g., `schemas/user.json`):

```json
{
  "table_name": "users",
  "struct_name": "User",
  "fields": [
    {
      "name": "id",
      "type": "uuid",
      "nullable": false,
      "default": "gen_random_uuid()",
      "input_mode": "auto_generated"
    },
    {
      "name": "email",
      "type": "text",
      "nullable": false,
      "input_mode": "required"
    },
    {
      "name": "created_at",
      "type": "timestamptz",
      "nullable": false,
      "default": "now()",
      "input_mode": "auto_generated"
    }
  ],
  "indexes": [
    {
      "name": "users_email_idx",
      "columns": ["email"],
      "unique": true
    }
  ]
}
```

## 🔌 Integration Guide

### 1. Using in `build.zig` (Best Practice)

Automate model generation as part of your build process.

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Define the dependency
    const model_gen_dep = b.dependency("model_gen", .{
        .target = target,
        .optimize = optimize,
    });

    // 2. Create the generation step
    const gen_cmd = b.addRunArtifact(model_gen_dep.artifact("zig-model-gen"));
    gen_cmd.addArg("schemas");      // Input directory
    gen_cmd.addArg("src/models");   // Output directory

    // 3. Define your executable
    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 4. Add pg dependency (required by generated models)
    const pg = b.dependency("pg", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("pg", pg.module("pg"));

    // 5. Ensure models are generated BEFORE compilation
    exe.step.dependOn(&gen_cmd.step);

    b.installArtifact(exe);
}
```

### 2. Using with Makefile

If you prefer Makefiles:

```makefile
.PHONY: generate build

generate:
	zig-model-gen schemas src/models

build: generate
	zig build
```

## 💻 Code Example

Once generated, use the models in your Zig code:

```zig
const std = @import("std");
const pg = @import("pg");
// Import generated model
const User = @import("models/user.zig").User;

pub fn main() !void {
    // ... setup pg pool ...

    // Create a new user
    const user_id = try User.insert(&pool, .{
        .email = "alice@example.com",
    });

    // Find by ID
    if (try User.findById(&pool, user_id)) |user| {
        std.debug.print("Found user: {s}\n", .{user.email});
    }

    // Update
    try User.update(&pool, user_id, .{
        .email = "alice.new@example.com",
    });
}
```

## 🏗 Architecture

The generator works in 3 steps:

1.  **Scan**: Finds all `.json` files in the input directory.
2.  **Validate**: Checks schema validity (types, required fields, indexes).
3.  **Generate**: Creates `.zig` files and bundles a copy of `base.zig` so the output is self-contained.

## 📄 License

MIT
