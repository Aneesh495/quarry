-- Quarry Database Schema Definitions
-- Standard TPC-H relational analytical tables and multimodal vector embedding catalog.

-- 1. Lineitem table
CREATE TABLE lineitem (
    l_orderkey BIGINT,
    l_partkey BIGINT,
    l_suppkey BIGINT,
    l_linenumber BIGINT,
    l_quantity BIGINT,
    l_extendedprice DOUBLE,
    l_discount DOUBLE,
    l_tax DOUBLE,
    l_returnflag VARCHAR,
    l_linestatus VARCHAR,
    l_shipdate VARCHAR,
    l_commitdate VARCHAR,
    l_receiptdate VARCHAR,
    l_shipmode VARCHAR
);

-- 2. Orders table
CREATE TABLE orders (
    o_orderkey BIGINT,
    o_custkey BIGINT,
    o_orderstatus VARCHAR,
    o_totalprice DOUBLE,
    o_orderdate VARCHAR,
    o_orderpriority VARCHAR
);

-- 3. Customer table
CREATE TABLE customer (
    c_custkey BIGINT,
    c_name VARCHAR,
    c_address VARCHAR,
    c_nationkey BIGINT,
    c_phone VARCHAR,
    c_acctbal DOUBLE,
    c_mktsegment VARCHAR
);

-- 4. Part table
CREATE TABLE part (
    p_partkey BIGINT,
    p_name VARCHAR,
    p_mfgr VARCHAR,
    p_brand VARCHAR,
    p_type VARCHAR,
    p_size BIGINT,
    p_container VARCHAR,
    p_retailprice DOUBLE
);

-- 5. Supplier table
CREATE TABLE supplier (
    s_suppkey BIGINT,
    s_name VARCHAR,
    s_address VARCHAR,
    s_nationkey BIGINT,
    s_phone VARCHAR,
    s_acctbal DOUBLE
);

-- 6. Document embeddings for hybrid semantic search
CREATE TABLE document_embeddings (
    doc_id BIGINT,
    title VARCHAR,
    category VARCHAR,
    publish_year BIGINT,
    embedding VECTOR(384)
);

-- 7. Product catalog with multi-modal image embeddings
CREATE TABLE product_catalog (
    product_id BIGINT,
    sku VARCHAR,
    category VARCHAR,
    price DOUBLE,
    stock_qty BIGINT,
    image_embedding VECTOR(512)
);
