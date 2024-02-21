"""
Unit test suite for the Quarry Python SDK.
"""

import unittest
from pyquarry import connect

class TestPyQuarry(unittest.TestCase):
    def test_connection_and_ddl(self):
        conn = connect(":memory:")
        self.assertIsNotNone(conn)

        # Create table
        cur = conn.execute("CREATE TABLE metrics (id INT, latency DOUBLE);")
        self.assertIsNotNone(cur)

        # Empty vector search test
        results = conn.vector_search("metrics", 1, [1.0, 0.0, 0.0, 0.0], 5)
        self.assertEqual(len(results), 0)

        conn.close()

if __name__ == "__main__":
    unittest.main()
