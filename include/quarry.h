/*
 * Quarry Embedded Columnar Database Engine
 * Public C Foreign Function Interface Header
 */

#ifndef QUARRY_H
#define QUARRY_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define QUARRY_OK         0
#define QUARRY_ROW        100
#define QUARRY_DONE       101
#define QUARRY_ERROR      -1

typedef struct quarry_db quarry_db_t;
typedef struct quarry_stmt quarry_stmt_t;

/* Lifecycle management */
quarry_db_t* quarry_open(const char *db_path);
void quarry_close(quarry_db_t *db);

/* Direct query execution */
int quarry_exec(quarry_db_t *db, const char *sql);

/* Cursor and statement lifecycle */
quarry_stmt_t* quarry_prepare(quarry_db_t *db, const char *sql);
int quarry_step(quarry_stmt_t *stmt);
int quarry_column_count(quarry_stmt_t *stmt);
const char* quarry_column_name(quarry_stmt_t *stmt, int col_idx);
int quarry_column_type(quarry_stmt_t *stmt, int col_idx);

/* Typed column accessors */
int64_t quarry_column_int64(quarry_stmt_t *stmt, int col_idx);
double quarry_column_double(quarry_stmt_t *stmt, int col_idx);
const char* quarry_column_text(quarry_stmt_t *stmt, int col_idx);
int quarry_column_is_null(quarry_stmt_t *stmt, int col_idx);

void quarry_finalize(quarry_stmt_t *stmt);

/* Vector search interface */
int quarry_vector_knn(quarry_db_t *db, const char *table, uint32_t vec_col_idx, const float *query_vec, uint32_t dim, uint32_t k, uint32_t *out_ids, float *out_dists);

#ifdef __cplusplus
}
#endif

#endif /* QUARRY_H */
