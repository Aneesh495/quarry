#!/usr/bin/env python3
"""
generate_sample_data.py
High-throughput synthetic data generator for Quarry analytical database.
Emits lineitem, customer, and orders tables compatible with standard TPC-H benchmarks.
"""

import os
import sys
import random
import argparse
from datetime import date, timedelta

def generate_tpch_lineitem(num_rows: int, output_path: str):
    print(f"Generating {num_rows} rows of lineitem data -> {output_path}")
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    start_date = date(1992, 1, 1)
    date_range = 2500

    shipmodes = ["MAIL", "SHIP", "RAIL", "AIR", "TRUCK", "FOB", "REG AIR"]
    flags = ["A", "N", "R"]
    statuses = ["O", "F"]

    with open(output_path, "w", encoding="utf-8") as f:
        # Header
        f.write("l_orderkey,l_partkey,l_suppkey,l_linenumber,l_quantity,l_extendedprice,l_discount,l_tax,l_returnflag,l_linestatus,l_shipdate,l_commitdate,l_receiptdate,l_shipmode\n")

        for i in range(num_rows):
            orderkey = (i // 4) + 1
            partkey = random.randint(1, 20000)
            suppkey = random.randint(1, 1000)
            linenumber = (i % 4) + 1
            quantity = random.randint(1, 50)
            price = quantity * random.randint(100, 1500)
            discount = random.randint(0, 10)
            tax = random.randint(0, 8)
            flag = random.choice(flags)
            status = random.choice(statuses)

            s_date = start_date + timedelta(days=random.randint(0, date_range))
            c_date = s_date + timedelta(days=random.randint(1, 30))
            r_date = s_date + timedelta(days=random.randint(1, 30))
            shipmode = random.choice(shipmodes)

            f.write(f"{orderkey},{partkey},{suppkey},{linenumber},{quantity},{price},{discount},{tax},{flag},{status},{s_date.strftime('%Y-%m-%d')},{c_date.strftime('%Y-%m-%d')},{r_date.strftime('%Y-%m-%d')},{shipmode}\n")

    print(f"Done. Wrote {os.path.getsize(output_path)} bytes.")

def generate_tpch_customer(num_rows: int, output_path: str):
    print(f"Generating {num_rows} rows of customer data -> {output_path}")
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    segments = ["BUILDING", "AUTOMOBILE", "MACHINERY", "HOUSEHOLD", "FURNITURE"]

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("c_custkey,c_name,c_address,c_nationkey,c_phone,c_acctbal,c_mktsegment\n")
        for i in range(num_rows):
            custkey = i + 1
            name = f"Customer#{custkey:09d}"
            address = f"Address {custkey} Blvd"
            nationkey = random.randint(0, 24)
            phone = f"{nationkey:02d}-{random.randint(100, 999)}-{random.randint(100, 999)}-{random.randint(1000, 9999)}"
            acctbal = random.randint(-999, 9999)
            segment = random.choice(segments)
            f.write(f"{custkey},{name},{address},{nationkey},{phone},{acctbal},{segment}\n")

    print(f"Done. Wrote {os.path.getsize(output_path)} bytes.")

def generate_tpch_orders(num_rows: int, output_path: str):
    print(f"Generating {num_rows} rows of orders data -> {output_path}")
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    priorities = ["1-URGENT", "2-HIGH", "3-MEDIUM", "4-NOT SPECIFIED", "5-LOW"]
    statuses = ["O", "F", "P"]
    start_date = date(1992, 1, 1)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("o_orderkey,o_custkey,o_orderstatus,o_totalprice,o_orderdate,o_orderpriority\n")
        for i in range(num_rows):
            orderkey = i + 1
            custkey = random.randint(1, num_rows // 3 + 1)
            status = random.choice(statuses)
            totalprice = random.randint(1000, 500000)
            orderdate = start_date + timedelta(days=random.randint(0, 2400))
            priority = random.choice(priorities)
            f.write(f"{orderkey},{custkey},{status},{totalprice},{orderdate.strftime('%Y-%m-%d')},{priority}\n")

    print(f"Done. Wrote {os.path.getsize(output_path)} bytes.")

def main():
    parser = argparse.ArgumentParser(description="Quarry synthetic data generator")
    parser.add_argument("--lineitem-rows", type=int, default=50000, help="Number of lineitem rows")
    parser.add_argument("--customer-rows", type=int, default=5000, help="Number of customer rows")
    parser.add_argument("--orders-rows", type=int, default=15000, help="Number of orders rows")
    parser.add_argument("--out-dir", type=str, default="data/sample", help="Output directory")

    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    generate_tpch_lineitem(args.lineitem_rows, os.path.join(args.out_dir, "lineitem.csv"))
    generate_tpch_customer(args.customer_rows, os.path.join(args.out_dir, "customer.csv"))
    generate_tpch_orders(args.orders_rows, os.path.join(args.out_dir, "orders.csv"))
    print("All sample datasets successfully generated.")

if __name__ == "__main__":
    main()
