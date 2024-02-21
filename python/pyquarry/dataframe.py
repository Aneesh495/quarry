"""
DataFrame and Apache Arrow interop bridge for PyQuarry.
"""

from typing import Any, Dict, List

def to_dict_records(cursor) -> List[Dict[str, Any]]:
    rows = cursor.fetchall()
    col_names = [d[0] for d in cursor.description]
    records = []
    for row in rows:
        records.append(dict(zip(col_names, row)))
    return records
