import os
import ctypes
from typing import List, Tuple, Any, Optional

def _find_libquarry() -> str:
    # Look in ../../lib relative to this file
    base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    dylib_path = os.path.join(base_dir, "lib", "libquarry.dylib")
    so_path = os.path.join(base_dir, "lib", "libquarry.so")
    if os.path.exists(dylib_path):
        return dylib_path
    if os.path.exists(so_path):
        return so_path
    raise RuntimeError(f"Could not locate libquarry shared library in {os.path.join(base_dir, 'lib')}")

class _QuarryBindings:
    def __init__(self):
        lib_path = _find_libquarry()
        self.lib = ctypes.CDLL(lib_path)

        # quarry_open(const char*) -> db*
        self.lib.quarry_open.argtypes = [ctypes.c_char_p]
        self.lib.quarry_open.restype = ctypes.c_void_p

        # quarry_close(db*)
        self.lib.quarry_close.argtypes = [ctypes.c_void_p]
        self.lib.quarry_close.restype = None

        # quarry_exec(db*, const char*) -> int
        self.lib.quarry_exec.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.lib.quarry_exec.restype = ctypes.c_int

        # quarry_prepare(db*, const char*) -> stmt*
        self.lib.quarry_prepare.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.lib.quarry_prepare.restype = ctypes.c_void_p

        # quarry_step(stmt*) -> int
        self.lib.quarry_step.argtypes = [ctypes.c_void_p]
        self.lib.quarry_step.restype = ctypes.c_int

        # quarry_column_count(stmt*) -> int
        self.lib.quarry_column_count.argtypes = [ctypes.c_void_p]
        self.lib.quarry_column_count.restype = ctypes.c_int

        # quarry_column_int64(stmt*, int) -> int64
        self.lib.quarry_column_int64.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.lib.quarry_column_int64.restype = ctypes.c_int64

        # quarry_column_double(stmt*, int) -> double
        self.lib.quarry_column_double.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.lib.quarry_column_double.restype = ctypes.c_double

        # quarry_column_text(stmt*, int) -> const char*
        self.lib.quarry_column_text.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.lib.quarry_column_text.restype = ctypes.c_char_p

        # quarry_column_is_null(stmt*, int) -> int
        self.lib.quarry_column_is_null.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.lib.quarry_column_is_null.restype = ctypes.c_int

        # quarry_finalize(stmt*)
        self.lib.quarry_finalize.argtypes = [ctypes.c_void_p]
        self.lib.quarry_finalize.restype = None

        # quarry_vector_knn
        self.lib.quarry_vector_knn.argtypes = [
            ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32,
            ctypes.POINTER(ctypes.c_float), ctypes.c_uint32, ctypes.c_uint32,
            ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(ctypes.c_float)
        ]
        self.lib.quarry_vector_knn.restype = ctypes.c_int

_BINDINGS = None
def _get_bindings() -> _QuarryBindings:
    global _BINDINGS
    if _BINDINGS is None:
        _BINDINGS = _QuarryBindings()
    return _BINDINGS

class Cursor:
    def __init__(self, db_handle: int):
        self._db = db_handle
        self._stmt = None
        self._bindings = _get_bindings()
        self.description = None

    def execute(self, sql: str) -> "Cursor":
        if self._stmt:
            self._bindings.lib.quarry_finalize(self._stmt)
            self._stmt = None

        sql_bytes = sql.encode("utf-8")
        # Check if DDL
        stripped = sql.strip().upper()
        if stripped.startswith("CREATE") or stripped.startswith("INSERT") or stripped.startswith("COPY"):
            rc = self._bindings.lib.quarry_exec(self._db, sql_bytes)
            if rc != 0:
                raise RuntimeError(f"Quarry DDL error (rc={rc})")
            return self

        stmt = self._bindings.lib.quarry_prepare(self._db, sql_bytes)
        if not stmt:
            raise RuntimeError(f"Quarry query preparation failed: {sql}")
        self._stmt = stmt
        col_count = self._bindings.lib.quarry_column_count(self._stmt)
        self.description = [(f"col_{i}", None, None, None, None, None, None) for i in range(col_count)]
        return self

    def fetchall(self) -> List[Tuple[Any, ...]]:
        if not self._stmt:
            return []
        rows = []
        col_count = len(self.description)
        while True:
            rc = self._bindings.lib.quarry_step(self._stmt)
            if rc == 100: # QUARRY_ROW
                row = []
                for i in range(col_count):
                    if self._bindings.lib.quarry_column_is_null(self._stmt, i):
                        row.append(None)
                    else:
                        val = self._bindings.lib.quarry_column_int64(self._stmt, i)
                        row.append(val)
                rows.append(tuple(row))
            elif rc == 101: # QUARRY_DONE
                break
            else:
                raise RuntimeError(f"Error during query step (rc={rc})")
        return rows

    def close(self):
        if self._stmt:
            self._bindings.lib.quarry_finalize(self._stmt)
            self._stmt = None

class Connection:
    def __init__(self, db_path: str = ":memory:"):
        self._bindings = _get_bindings()
        self._db = self._bindings.lib.quarry_open(db_path.encode("utf-8"))
        if not self._db:
            raise RuntimeError("Failed to open Quarry database instance")

    def cursor(self) -> Cursor:
        return Cursor(self._db)

    def execute(self, sql: str) -> Cursor:
        cur = self.cursor()
        return cur.execute(sql)

    def vector_search(self, table: str, col_idx: int, query_vec: List[float], k: int) -> List[Tuple[int, float]]:
        dim = len(query_vec)
        q_arr = (ctypes.c_float * dim)(*query_vec)
        out_ids = (ctypes.c_uint32 * k)()
        out_dists = (ctypes.c_float * k)()

        rc = self._bindings.lib.quarry_vector_knn(
            self._db, table.encode("utf-8"), col_idx,
            q_arr, dim, k, out_ids, out_dists
        )
        if rc < 0:
            raise RuntimeError("Vector search failed")

        results = []
        for i in range(rc):
            results.append((int(out_ids[i]), float(out_dists[i])))
        return results

    def close(self):
        if self._db:
            self._bindings.lib.quarry_close(self._db)
            self._db = None

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

def connect(database: str = ":memory:") -> Connection:
    return Connection(database)
