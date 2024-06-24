# HTTP REST API & Web Dashboard

Quarry embeds an ultra-lightweight, non-blocking HTTP 1.1 daemon (`src/server/http.t`) enabling microservices, analytical dashboards, and remote query clients to interface with the database over standard JSON REST APIs.

## REST Endpoints Specification

### 1. Health Probe: `GET /health`

Returns engine status and version metadata for container health checks and cluster orchestration.

#### Request
```bash
curl -X GET http://localhost:8080/health
```

#### Response (200 OK)
```json
{
  "status": "healthy",
  "engine": "quarry",
  "version": "1.0.0"
}
```

---

### 2. Telemetry Metrics: `GET /metrics`

Reports fine-grained runtime metrics including memory consumption, active queries, and JIT kernel cache statistics.

#### Request
```bash
curl -X GET http://localhost:8080/metrics
```

#### Response (200 OK)
```json
{
  "uptime_seconds": 3600,
  "active_queries": 0,
  "jit_kernels_compiled": 42,
  "buffer_pool_bytes": 16777216
}
```

---

### 3. Query Execution: `POST /query`

Executes a SQL statement and returns serialized result tuples and execution profiling metadata.

#### Request
```bash
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"query": "SELECT id, price * (100 - discount) / 100 AS net_price FROM lineitem WHERE price > 200 LIMIT 10;"}'
```

#### Response (200 OK)
```json
{
  "status": "success",
  "rows_scanned": 1000000,
  "execution_time_us": 850.5,
  "data": [
    {"id": 1, "net_price": 190.0},
    {"id": 2, "net_price": 285.0}
  ]
}
```

---

### 4. Interactive Web Console: `GET /`

Serving `web/index.html`, this endpoint delivers an interactive dark-mode SQL query console with real-time execution pipeline visualization:

- **SQL Editor**: Code input area with syntax highlighting and pre-loaded analytical and vector queries.
- **Metrics Bar**: Visualizes query execution time in microseconds, rows scanned, and JIT compilation status.
- **Pipeline DAG Visualizer**: Interactive flowchart displaying the physical query execution pipeline:
  ```
  [Scan lineitem] -> [PhysicalFilter] -> [PhysicalProject] -> [ResultSink]
  ```
- **Results Grid**: Tabular view of query outputs with column headers and row indexing.
