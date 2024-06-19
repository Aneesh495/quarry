# Quarry C API Reference

Quarry exports a stable, zero-overhead C foreign function interface (FFI) defined in `include/quarry.h` and compiled into `lib/libquarry.dylib` (macOS) and `lib/libquarry.so` (Linux). The C API enables seamless embedding into C, C++, Rust, Go, Python, and Zig runtimes.

## Header File: `include/quarry.h`

```c
#ifndef QUARRY_H
#define QUARRY_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Return and Step Codes
#define QUARRY_OK       0
#define QUARRY_ERROR   -1
#define QUARRY_ROW     100
#define QUARRY_DONE    101

typedef struct quarry_db quarry_db;
typedef struct quarry_stmt quarry_stmt;

// Lifecycle Management
quarry_db* quarry_open(const char* path);
void quarry_close(quarry_db* db);

// Execution Primitives
int32_t quarry_exec(quarry_db* db, const char* sql);
quarry_stmt* quarry_prepare(quarry_db* db, const char* sql);
int32_t quarry_step(quarry_stmt* stmt);
void quarry_finalize(quarry_stmt* stmt);

// Column Inspection
int32_t quarry_column_count(quarry_stmt* stmt);
int64_t quarry_column_int64(quarry_stmt* stmt, int32_t col_idx);
double quarry_column_double(quarry_stmt* stmt, int32_t col_idx);
const char* quarry_column_text(quarry_stmt* stmt, int32_t col_idx);
int32_t quarry_column_is_null(quarry_stmt* stmt, int32_t col_idx);

// Vector Search
int32_t quarry_vector_knn(
    quarry_db* db,
    const char* table_name,
    uint32_t vec_col_idx,
    const float* query_vec,
    uint32_t dim,
    uint32_t k,
    uint32_t* out_ids,
    float* out_dists
);

#ifdef __cplusplus
}
#endif

#endif // QUARRY_H
```

---

## Function Documentation

### `quarry_open`
```c
quarry_db* quarry_open(const char* path);
```
- **Description**: Initializes an in-memory or persisted Quarry database instance.
- **Parameters**: `path`: File path to database file, or `NULL` / `":memory:"` for an in-memory catalog.
- **Returns**: Opaque pointer to `quarry_db`, or `NULL` if initialization fails.

### `quarry_close`
```c
void quarry_close(quarry_db* db);
```
- **Description**: Releases all catalog structures, table memory chunks, and allocated memory arenas.
- **Parameters**: `db`: Active database instance.

### `quarry_exec`
```c
int32_t quarry_exec(quarry_db* db, const char* sql);
```
- **Description**: Directly parses and executes a DDL statement (`CREATE TABLE`, `DROP TABLE`).
- **Returns**: `QUARRY_OK` (0) on success, or negative error code on failure.

### `quarry_prepare`
```c
quarry_stmt* quarry_prepare(quarry_db* db, const char* sql);
```
- **Description**: Parses, validates, and optimizes a SQL `SELECT` statement into an active query statement iterator.
- **Returns**: Opaque pointer to `quarry_stmt`, or `NULL` on syntax or planning error.

### `quarry_step`
```c
int32_t quarry_step(quarry_stmt* stmt);
```
- **Description**: Advances the statement cursor to the next result row.
- **Returns**:
  - `QUARRY_ROW` (100): Row available for inspection via `quarry_column_*`.
  - `QUARRY_DONE` (101): Execution completed, no further rows available.
  - Negative error code on execution failure.

### `quarry_vector_knn`
```c
int32_t quarry_vector_knn(
    quarry_db* db,
    const char* table_name,
    uint32_t vec_col_idx,
    const float* query_vec,
    uint32_t dim,
    uint32_t k,
    uint32_t* out_ids,
    float* out_dists
);
```
- **Description**: Runs SIMD-accelerated k-NN search across vector embeddings in the specified table.
- **Returns**: Number of matched nearest neighbors written to `out_ids` and `out_dists`.

---

## Complete Compilable Example

```c
#include <stdio.h>
#include <quarry.h>

int main(void) {
    // 1. Open in-memory database
    quarry_db* db = quarry_open(":memory:");
    if (!db) {
        fprintf(stderr, "Failed to open Quarry database\n");
        return 1;
    }

    // 2. Create table
    quarry_exec(db, "CREATE TABLE lineitem (id BIGINT, price DOUBLE);");

    // 3. Prepare and step through query
    quarry_stmt* stmt = quarry_prepare(db, "SELECT id, price FROM lineitem;");
    if (stmt) {
        while (quarry_step(stmt) == QUARRY_ROW) {
            int64_t id = quarry_column_int64(stmt, 0);
            double price = quarry_column_double(stmt, 1);
            printf("Row: id=%lld, price=%.2f\n", id, price);
        }
        quarry_finalize(stmt);
    }

    // 4. Close database
    quarry_close(db);
    return 0;
}
```

Compile with:
```bash
clang -O3 -Iinclude main.c -Llib -lquarry -o main
./main
```
