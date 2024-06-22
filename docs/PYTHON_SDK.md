# PyQuarry Python SDK Documentation

`pyquarry` is the official Python client library for the Quarry columnar database engine. It provides high-performance ctypes FFI bindings, a PEP 249 (Python DB-API 2.0) compliant cursor interface, native vector similarity search, and zero-copy conversions to Pandas, Polars, and Apache Arrow.

## Installation

From the repository root:
```bash
cd python
pip install .
```

To install optional DataFrame and Apache Arrow dependencies:
```bash
pip install .[all]
```

---

## Quickstart Guide

```python
import pyquarry

# 1. Open an in-memory database instance
conn = pyquarry.connect(":memory:")

# 2. Create tables via standard SQL DDL
conn.execute("""
    CREATE TABLE lineitem (
        l_orderkey BIGINT,
        l_extendedprice DOUBLE,
        l_discount DOUBLE
    );
""")

# 3. Query using the DB-API cursor interface
cursor = conn.cursor()
cursor.execute("SELECT l_orderkey, l_extendedprice * (1.0 - l_discount) FROM lineitem;")

for row in cursor:
    print(f"Order Key: {row[0]}, Net Price: {row[1]}")

cursor.close()
conn.close()
```

---

## PEP 249 DB-API 2.0 Compliance

`pyquarry.Cursor` implements standard database cursor operations:

### `execute(sql: str, params: Optional[tuple] = None)`
Prepares and executes a SQL query string. For DDL operations (`CREATE`, `DROP`), execution is applied immediately. For `SELECT` queries, prepares an active statement iterator and sets `cursor.description`.

### `fetchone() -> Optional[tuple]`
Fetches the next tuple from the active result set, returning `None` when iteration is exhausted.

### `fetchmany(size: Optional[int] = None) -> list[tuple]`
Fetches the next `size` rows (defaults to `cursor.arraysize = 100`).

### `fetchall() -> list[tuple]`
Fetches all remaining rows from the active query result set.

### `description`
A sequence of 7-item tuples describing result columns:
`(name, type_code, display_size, internal_size, precision, scale, null_ok)`

---

## Native Vector Search Integration

`pyquarry` exposes direct hardware SIMD-accelerated vector nearest neighbor search without requiring complex SQL query construction:

```python
import pyquarry

conn = pyquarry.connect(":memory:")

# Setup document table with 384-dimensional vector embeddings
conn.execute("""
    CREATE TABLE documents (
        doc_id BIGINT,
        title VARCHAR,
        embedding VECTOR(384)
    );
""")

# Query vector: 384-dimensional unit normalized float list
query_vector = [0.05] * 384

# Find top 5 nearest neighbors
results = conn.vector_search(
    table="documents",
    col_idx=2,          # embedding column index
    query_vec=query_vector,
    k=5                 # top-k
)

for doc_id, distance in results:
    print(f"Matched Document ID: {doc_id}, Distance: {distance:.4f}")

conn.close()
```

---

## DataFrame and Apache Arrow Bridge

`pyquarry.DataFrame` provides zero-copy bridges into leading Python data analytics ecosystems:

```python
from pyquarry.dataframe import DataFrame

# Query results can be wrapped in a DataFrame
df = DataFrame(
    data=[(1, 100.0, 0.05), (2, 250.0, 0.10)],
    columns=["order_key", "price", "discount"]
)

# 1. Convert to Pandas DataFrame
pandas_df = df.to_pandas()
print(pandas_df.describe())

# 2. Convert to Polars DataFrame
polars_df = df.to_polars()
print(polars_df.filter(polars_df["price"] > 150.0))

# 3. Convert to Apache Arrow Table (Zero-Copy)
arrow_table = df.to_arrow()
print(f"Arrow Table Schema:\n{arrow_table.schema}")
```
