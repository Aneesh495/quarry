#!/usr/bin/env python3
"""
test_http_server.py
Integration test suite verifying Quarry embedded HTTP REST API daemon,
endpoint routing, JSON serialization, and status codes.
"""

import sys
import unittest
import subprocess
import json

class TestQuarryHttpServer(unittest.TestCase):
    def test_http_endpoint_dispatch(self):
        """Tests that Quarry HTTP daemon router processes endpoints and emits valid HTTP 1.1 frames."""
        terra_script = """
        local server = require("src.server/http")
        local C = require("src.common.c").C

        local terra run_tests() : int
            var s : server.HttpServer
            s:init(8080)

            var buf : int8[2048]

            -- 1. Test /health
            s:handle_request("GET", "/health", nil, &(buf[0]), 2048)
            if C.strstr(&(buf[0]), "200 OK") == nil or C.strstr(&(buf[0]), "healthy") == nil then
                return 1
            end

            -- 2. Test /metrics
            s:handle_request("GET", "/metrics", nil, &(buf[0]), 2048)
            if C.strstr(&(buf[0]), "200 OK") == nil or C.strstr(&(buf[0]), "jit_kernels_compiled") == nil then
                return 2
            end

            -- 3. Test /query
            s:handle_request("POST", "/query", "SELECT 1", &(buf[0]), 2048)
            if C.strstr(&(buf[0]), "200 OK") == nil or C.strstr(&(buf[0]), "rows_scanned") == nil then
                return 3
            end

            -- 4. Test 404 Not Found
            s:handle_request("GET", "/non_existent_route", nil, &(buf[0]), 2048)
            if C.strstr(&(buf[0]), "404 Not Found") == nil then
                return 4
            end

            return 0
        end

        local code = run_tests()
        if code ~= 0 then os.exit(code) end
        """

        result = subprocess.run(
            ["terra", "-e", terra_script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        self.assertEqual(result.returncode, 0, f"HTTP server tests failed with code {result.returncode}:\n{result.stderr}")
        print("PASS: Quarry HTTP REST API router passed all endpoint tests (/health, /metrics, /query, 404)")

if __name__ == "__main__":
    unittest.main()
