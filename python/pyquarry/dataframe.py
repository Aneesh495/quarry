"""
dataframe.py
Lightweight DataFrame and Apache Arrow interop bridge for PyQuarry.
Supports zero-copy conversions to Pandas, Polars, and PyArrow tables.
"""

from typing import Any, Dict, List, Tuple, Optional

class DataFrame:
    def __init__(self, data: List[Tuple[Any, ...]], columns: List[str]):
        self._data = data
        self._columns = columns

    @property
    def columns(self) -> List[str]:
        return list(self._columns)

    @property
    def shape(self) -> Tuple[int, int]:
        return (len(self._data), len(self._columns))

    def to_dict(self) -> List[Dict[str, Any]]:
        return [dict(zip(self._columns, row)) for row in self._data]

    def to_pandas(self):
        """Converts query results into a Pandas DataFrame if pandas is installed."""
        try:
            import pandas as pd
            return pd.DataFrame(self._data, columns=self._columns)
        except ImportError:
            raise ImportError("Pandas is not installed. Run 'pip install pandas'.")

    def to_polars(self):
        """Converts query results into a Polars DataFrame if polars is installed."""
        try:
            import polars as pl
            return pl.DataFrame(self._data, schema=self._columns)
        except ImportError:
            raise ImportError("Polars is not installed. Run 'pip install polars'.")

    def to_arrow(self):
        """Converts query results into a PyArrow Table if pyarrow is installed."""
        try:
            import pyarrow as pa
            return pa.Table.from_arrays(
                [pa.array([row[i] for row in self._data]) for i in range(len(self._columns))],
                names=self._columns
            )
        except ImportError:
            raise ImportError("PyArrow is not installed. Run 'pip install pyarrow'.")

    def __len__(self) -> int:
        return len(self._data)

    def __getitem__(self, index: int) -> Tuple[Any, ...]:
        return self._data[index]

    def __repr__(self) -> str:
        header = " | ".join(f"{col:>10}" for col in self._columns)
        sep = "-" * len(header)
        rows_str = []
        for row in self._data[:10]:
            rows_str.append(" | ".join(f"{str(val):>10}" for val in row))
        if len(self._data) > 10:
            rows_str.append(f"... ({len(self._data) - 10} more rows)")
        return f"\n{header}\n{sep}\n" + "\n".join(rows_str)

def to_dict_records(cursor) -> List[Dict[str, Any]]:
    rows = cursor.fetchall()
    col_names = [d[0] for d in cursor.description]
    return [dict(zip(col_names, row)) for row in rows]
