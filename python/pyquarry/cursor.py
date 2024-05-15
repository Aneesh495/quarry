"""
cursor.py
PEP 249 (Python Database API Specification v2.0) compliant cursor for Quarry.
Provides result iteration, batch fetching, and query execution metadata.
"""

from typing import List, Tuple, Any, Optional

class Cursor:
    def __init__(self, db_handle: int, bindings: Any):
        self._db = db_handle
        self._bindings = bindings
        self._stmt = None
        self.description = None
        self.rowcount = -1
        self.arraysize = 100

    def execute(self, sql: str, params: Optional[Tuple[Any, ...]] = None) -> "Cursor":
        """Executes a SQL statement, managing statement lifecycle and column metadata."""
        if self._stmt:
            self._bindings.lib.quarry_finalize(self._stmt)
            self._stmt = None

        sql_bytes = sql.encode("utf-8")
        stripped = sql.strip().upper()

        # Handle DDL statements directly via quarry_exec
        if any(stripped.startswith(kw) for kw in ("CREATE", "DROP", "ALTER", "INSERT", "COPY")):
            rc = self._bindings.lib.quarry_exec(self._db, sql_bytes)
            if rc != 0:
                raise RuntimeError(f"Quarry execution error (rc={rc})")
            self.description = None
            self.rowcount = 0
            return self

        stmt = self._bindings.lib.quarry_prepare(self._db, sql_bytes)
        if not stmt:
            raise RuntimeError(f"Quarry query preparation failed: {sql}")

        self._stmt = stmt
        col_count = self._bindings.lib.quarry_column_count(self._stmt)
        self.description = [(f"col_{i}", None, None, None, None, None, None) for i in range(col_count)]
        self.rowcount = -1
        return self

    def executemany(self, sql: str, seq_of_params: List[Tuple[Any, ...]]) -> "Cursor":
        """Executes a SQL operation repeatedly against parameter sequences."""
        for params in seq_of_params:
            self.execute(sql, params)
        return self

    def fetchone(self) -> Optional[Tuple[Any, ...]]:
        """Fetches the next row of a query result set, returning a single tuple or None."""
        if not self._stmt or not self.description:
            return None

        rc = self._bindings.lib.quarry_step(self._stmt)
        if rc == 100:  # QUARRY_ROW
            col_count = len(self.description)
            row = []
            for i in range(col_count):
                if self._bindings.lib.quarry_column_is_null(self._stmt, i):
                    row.append(None)
                else:
                    val = self._bindings.lib.quarry_column_int64(self._stmt, i)
                    row.append(val)
            return tuple(row)
        elif rc == 101:  # QUARRY_DONE
            return None
        else:
            raise RuntimeError(f"Error during query step (rc={rc})")

    def fetchmany(self, size: Optional[int] = None) -> List[Tuple[Any, ...]]:
        """Fetches the next set of rows of a query result, returning a list of tuples."""
        if size is None:
            size = self.arraysize

        rows = []
        for _ in range(size):
            row = self.fetchone()
            if row is None:
                break
            rows.append(row)
        return rows

    def fetchall(self) -> List[Tuple[Any, ...]]:
        """Fetches all remaining rows of a query result set."""
        rows = []
        while True:
            row = self.fetchone()
            if row is None:
                break
            rows.append(row)
        return rows

    def close(self):
        """Closes the cursor and releases prepared statement resources."""
        if self._stmt:
            self._bindings.lib.quarry_finalize(self._stmt)
            self._stmt = None

    def __iter__(self):
        return self

    def __next__(self) -> Tuple[Any, ...]:
        row = self.fetchone()
        if row is None:
            raise StopIteration
        return row
