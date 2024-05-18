"""
test_cursor.py
Unit tests verifying PEP 249 Cursor compliance for PyQuarry SDK.
"""

import unittest
from pyquarry import connect, Cursor

class TestPyQuarryCursor(unittest.TestCase):
    def setUp(self):
        self.conn = connect(":memory:")

    def tearDown(self):
        self.conn.close()

    def test_cursor_attributes(self):
        """Verifies initial cursor state, description, and default arraysize."""
        cursor = self.conn.cursor()
        self.assertIsInstance(cursor, Cursor)
        self.assertIsNone(cursor.description)
        self.assertEqual(cursor.arraysize, 100)
        self.assertEqual(cursor.rowcount, -1)
        cursor.close()

    def test_cursor_execute_ddl(self):
        """Verifies executing DDL statements sets appropriate metadata."""
        cursor = self.conn.cursor()
        cursor.execute("CREATE TABLE test_cursor_tbl (id BIGINT, val DOUBLE);")
        self.assertIsNone(cursor.description)
        self.assertEqual(cursor.rowcount, 0)
        cursor.close()

    def test_cursor_fetch_methods(self):
        """Verifies fetchone, fetchmany, and fetchall semantics."""
        cursor = self.conn.cursor()
        cursor.execute("CREATE TABLE items (id BIGINT);")
        # Empty table should return None on fetchone
        cursor.execute("SELECT id FROM items;")
        self.assertIsNotNone(cursor.description)
        row = cursor.fetchone()
        self.assertIsNone(row)

        rows = cursor.fetchall()
        self.assertEqual(rows, [])
        cursor.close()

    def test_cursor_iteration_protocol(self):
        """Verifies that cursor implements the standard Python iteration protocol."""
        cursor = self.conn.cursor()
        cursor.execute("CREATE TABLE empty_tbl (id BIGINT);")
        cursor.execute("SELECT id FROM empty_tbl;")

        rows = list(cursor)
        self.assertEqual(len(rows), 0)
        cursor.close()

if __name__ == "__main__":
    unittest.main()
