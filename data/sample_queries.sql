-- Quarry Sample Analytical and Hybrid Vector SQL Queries
-- Demonstrating columnar aggregations, hash joins, predicate pushdown, and vector distance search.

-- Query 1: TPC-H Pricing Summary Report (Q1)
SELECT l_returnflag, l_linestatus, SUM(l_quantity) AS sum_qty, SUM(l_extendedprice) AS sum_base_price, AVG(l_discount) AS avg_disc, COUNT(*) AS count_order
FROM lineitem
GROUP BY l_returnflag, l_linestatus
ORDER BY l_returnflag, l_linestatus;

-- Query 2: TPC-H Forecasting Revenue Change (Q6)
SELECT SUM(l_extendedprice * l_discount) AS revenue
FROM lineitem
WHERE l_shipdate >= '1994-01-01' AND l_shipdate <= '1995-01-01' AND l_discount >= 0.05 AND l_discount <= 0.07 AND l_quantity < 24;

-- Query 3: Customer and Orders Join with Spending Threshold
SELECT c.c_name, c.c_mktsegment, SUM(o.o_totalprice) AS total_spent
FROM customer c JOIN orders o ON c.c_custkey = o.o_custkey
WHERE o.o_orderdate >= '1995-01-01'
GROUP BY c.c_name, c.c_mktsegment
ORDER BY total_spent DESC
LIMIT 10;

-- Query 4: High-Volume Lineitem Discounted Revenue by Ship Mode
SELECT l_shipmode, COUNT(*) AS lines_count, SUM(l_extendedprice * (1.0 - l_discount)) AS discounted_revenue
FROM lineitem
WHERE l_quantity > 30
GROUP BY l_shipmode
ORDER BY discounted_revenue DESC;

-- Query 5: Urgent Priority Shipping Efficiency
SELECT o.o_orderpriority, COUNT(*) AS num_orders, AVG(o.o_totalprice) AS avg_price
FROM orders o
WHERE o.o_orderpriority = '1-URGENT'
GROUP BY o.o_orderpriority;

-- Query 6: Three-Way Join (Customer, Orders, Lineitem)
SELECT c.c_mktsegment, SUM(l.l_extendedprice * (1.0 - l.l_discount)) AS revenue
FROM customer c JOIN orders o ON c.c_custkey = o.o_custkey
WHERE o.o_orderdate >= '1995-03-01'
GROUP BY c.c_mktsegment
ORDER BY revenue DESC;

-- Query 7: Filter with Inlined Constant Arithmetic (Constant Folding)
SELECT l_orderkey, l_extendedprice * (1.0 - 0.05) AS discounted_price
FROM lineitem
WHERE l_discount > (0.10 / 2.0)
LIMIT 50;

-- Query 8: Document Semantic Search with Category Pruning (Hybrid Vector Query)
SELECT doc_id, title, category, VECTOR_DISTANCE(embedding, [0.12, -0.45, 0.88, 0.03]) AS distance
FROM document_embeddings
WHERE category = 'technology' AND publish_year >= 2022
ORDER BY distance ASC
LIMIT 5;

-- Query 9: Multi-Modal Product Visual Similarity Search
SELECT product_id, sku, price, VECTOR_DISTANCE(image_embedding, [0.05, 0.91, -0.22, 0.34]) AS score
FROM product_catalog
WHERE price <= 250.0 AND stock_qty > 0
ORDER BY score ASC
LIMIT 8;

-- Query 10: TPC-H Shipping Modes and Order Priority (Q12)
SELECT l_shipmode, COUNT(*) AS high_priority_count
FROM lineitem
WHERE l_commitdate < l_receiptdate AND (l_shipmode = 'MAIL' OR l_shipmode = 'SHIP')
GROUP BY l_shipmode;

-- Query 11: Window Function Row Numbering
SELECT l_orderkey, l_partkey, l_extendedprice, ROW_NUMBER() OVER (PARTITION BY l_orderkey ORDER BY l_extendedprice DESC) AS rank
FROM lineitem
LIMIT 100;

-- Query 12: Promotion Effect Query (Q14)
SELECT 100.0 * SUM(l_extendedprice * (1.0 - l_discount)) / SUM(l_extendedprice * (1.0 - l_discount)) AS promo_revenue
FROM lineitem
WHERE l_shipdate >= '1995-09-01';

-- Query 13: Discounted Revenue Compound Predicate (Q19)
SELECT SUM(l_extendedprice * (1.0 - l_discount)) AS revenue
FROM lineitem
WHERE (l_quantity >= 1 AND l_quantity <= 11 AND (l_shipmode = 'AIR' OR l_shipmode = 'REG AIR'))
   OR (l_quantity >= 10 AND l_quantity <= 20 AND (l_shipmode = 'AIR' OR l_shipmode = 'REG AIR'))
   OR (l_quantity >= 20 AND l_quantity <= 30 AND (l_shipmode = 'AIR' OR l_shipmode = 'REG AIR'));

-- Query 14: Null Value Filter Pushdown
SELECT c_name, c_phone
FROM customer
WHERE c_acctbal IS NOT NULL AND c_acctbal > 0.0
LIMIT 25;

-- Query 15: Cross-Table Foreign Key Integrity Verification
SELECT COUNT(*) AS unmatched_orders
FROM orders o LEFT OUTER JOIN customer c ON o.o_custkey = c.c_custkey
WHERE c.c_custkey IS NULL;

-- Query 16: Top-K Vector Nearest Neighbors Flat Scan
SELECT doc_id, VECTOR_DISTANCE(embedding, [0.0, 1.0, 0.0, 0.0]) AS dist
FROM document_embeddings
ORDER BY dist ASC
LIMIT 10;

-- Query 17: Multi-Column Sorting with Offset Pagination
SELECT l_orderkey, l_linenumber, l_extendedprice
FROM lineitem
ORDER BY l_orderkey ASC, l_extendedprice DESC
LIMIT 20 OFFSET 40;

-- Query 18: High-Dimensional Cosine Similarity Search
SELECT product_id, title, COSINE_SIMILARITY(embedding, [0.7071, 0.7071, 0.0, 0.0]) AS similarity
FROM document_embeddings
WHERE similarity >= 0.85
ORDER BY similarity DESC;

-- Query 19: JIT Fused Pipeline Execution with Complex Math
SELECT l_orderkey, (l_extendedprice * (1.0 - l_discount) * (1.0 + l_tax)) AS total_charge
FROM lineitem
WHERE l_tax < 0.05 AND l_discount > 0.02
LIMIT 1000;

-- Query 20: Comprehensive Relational Table Count and Metrics
SELECT COUNT(*) AS total_lineitems, COUNT(DISTINCT l_orderkey) AS distinct_orders, SUM(l_quantity) AS total_volume
FROM lineitem;
