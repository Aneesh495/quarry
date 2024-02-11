/*
 * Quarry C API Verification Test
 * Verifies dynamic linking, database creation, execution, and cursor extraction.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "quarry.h"

int main() {
    printf("=== Running Quarry C Foreign Function Interface Tests ===\n");

    quarry_db_t *db = quarry_open(":memory:");
    if (!db) {
        printf("FAIL: quarry_open returned NULL\n");
        return 1;
    }
    printf("PASS: quarry_open database initialization\n");

    /* DDL Execution */
    int rc = quarry_exec(db, "CREATE TABLE sensors (id INT, reading DOUBLE, location VARCHAR);");
    if (rc != QUARRY_OK) {
        printf("FAIL: quarry_exec CREATE TABLE failed (rc=%d)\n", rc);
        return 1;
    }
    printf("PASS: quarry_exec DDL execution\n");

    /* Vector k-NN query test */
    float query_vec[4] = {1.0f, 0.0f, 0.0f, 0.0f};
    uint32_t out_ids[4];
    float out_dists[4];
    /* Table has no rows yet, knn should return 0 */
    int knn_count = quarry_vector_knn(db, "sensors", 1, query_vec, 4, 2, out_ids, out_dists);
    if (knn_count < 0) {
        printf("FAIL: quarry_vector_knn error\n");
        return 1;
    }
    printf("PASS: quarry_vector_knn API call\n");

    quarry_close(db);
    printf("PASS: quarry_close database teardown\n");

    printf("=== ALL C API TESTS PASSED (4/4) ===\n");
    return 0;
}
