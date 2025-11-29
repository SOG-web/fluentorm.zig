# Relationship Documentation

This guide details how to define relationships between tables in your JSON schemas.

## Overview

Relationships are defined in the `relationships` array within your schema file. They allow you to define foreign key constraints and generate helper methods for navigating between models.

## Configuration

Each relationship object supports the following properties:

| Property     | Type   | Required | Default       | Description                                                   |
| ------------ | ------ | -------- | ------------- | ------------------------------------------------------------- |
| `name`       | string | **Yes**  | -             | A unique name for the relationship (used in generated code).  |
| `column`     | string | **Yes**  | -             | The column in the _current_ table that holds the foreign key. |
| `references` | object | **Yes**  | -             | Defines the target table and column.                          |
| `type`       | string | No       | `many_to_one` | The type of relationship.                                     |
| `on_delete`  | string | No       | `NO ACTION`   | Action to take when the referenced record is deleted.         |
| `on_update`  | string | No       | `NO ACTION`   | Action to take when the referenced record is updated.         |

### References Object

| Property | Type   | Required | Description                                              |
| -------- | ------ | -------- | -------------------------------------------------------- |
| `table`  | string | **Yes**  | The name of the target table.                            |
| `column` | string | **Yes**  | The name of the target column (usually the primary key). |

## Relationship Types

Supported values for `type`:

- `many_to_one` (Default): The current table holds a foreign key to another table.
- `one_to_many`: The current table is referenced by multiple records in another table.
- `one_to_one`: A strict one-to-one mapping.
- `many_to_many`: A complex relationship involving a junction table.

## Referential Actions

Supported values for `on_delete` and `on_update`:

- `CASCADE`: Propagate the change (delete dependent rows or update foreign keys).
- `SET NULL`: Set the foreign key column to NULL.
- `SET DEFAULT`: Set the foreign key column to its default value.
- `RESTRICT`: Prevent the change if there are dependent rows.
- `NO ACTION`: Similar to RESTRICT, but checks are deferred to the end of the transaction.

## Examples

### Many-to-One (Foreign Key)

A user belongs to an organization.

```json
{
  "name": "organization",
  "column": "organization_id",
  "type": "many_to_one",
  "references": {
    "table": "organizations",
    "column": "id"
  },
  "on_delete": "CASCADE"
}
```

### One-to-Many

An organization has many users.

```json
{
  "name": "users",
  "column": "id",
  "type": "one_to_many",
  "references": {
    "table": "users",
    "column": "organization_id"
  }
}
```

> **Note**: For `one_to_many`, the `column` is the primary key of the _current_ table, and `references.column` is the foreign key in the _target_ table.

## Generated SQL

The generator uses these definitions to create `FOREIGN KEY` constraints in the `createTable` SQL.

```sql
CONSTRAINT fk_organization FOREIGN KEY (organization_id)
REFERENCES organizations(id)
ON DELETE CASCADE
ON UPDATE NO ACTION
```
