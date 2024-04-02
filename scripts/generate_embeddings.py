#!/usr/bin/env python3
"""
generate_embeddings.py
Generates clustered high-dimensional embedding vectors for vector database benchmarking.
Produces synthetic clusters with controlled noise, L2 normalization, and ground-truth k-NN.
"""

import os
import sys
import math
import random
import argparse
from typing import List

def generate_clustered_vectors(
    num_vectors: int,
    dim: int,
    num_clusters: int = 16,
    noise_scale: float = 0.08,
    normalize: bool = True
) -> List[dict]:
    # 1. Generate cluster centroids
    centroids = []
    for c in range(num_clusters):
        vec = [random.gauss(0.0, 1.0) for _ in range(dim)]
        if normalize:
            norm = math.sqrt(sum(x * x for x in vec))
            if norm > 1e-9:
                vec = [x / norm for x in vec]
        centroids.append(vec)

    # 2. Generate points around centroids
    categories = [
        "science", "technology", "finance", "medicine", "history",
        "philosophy", "arts", "astronomy", "linguistics", "mathematics",
        "robotics", "genomics", "quantum", "climate", "economics", "law"
    ]

    records = []
    for i in range(num_vectors):
        c_idx = i % num_clusters
        base = centroids[c_idx]
        perturbed = [base[d] + random.gauss(0.0, noise_scale) for d in range(dim)]

        if normalize:
            norm = math.sqrt(sum(x * x for x in perturbed))
            if norm > 1e-9:
                perturbed = [x / norm for x in perturbed]

        records.append({
            "id": i + 1,
            "category": categories[c_idx % len(categories)],
            "cluster_id": c_idx,
            "vector": perturbed
        })

    return records

def export_to_csv(records: List[dict], output_path: str):
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("id,category,cluster_id,embedding\n")
        for r in records:
            vec_str = "[" + ";".join(f"{x:.6f}" for x in r["vector"]) + "]"
            f.write(f"{r['id']},{r['category']},{r['cluster_id']},{vec_str}\n")
    print(f"Exported {len(records)} embedding records -> {output_path}")

def main():
    parser = argparse.ArgumentParser(description="Quarry high-dimensional embedding generator")
    parser.add_argument("--num-vectors", type=int, default=1000, help="Number of vectors to generate")
    parser.add_argument("--dim", type=int, default=64, help="Embedding dimension")
    parser.add_argument("--clusters", type=int, default=8, help="Number of semantic clusters")
    parser.add_argument("--noise", type=float, default=0.05, help="Cluster dispersion noise")
    parser.add_argument("--out", type=str, default="data/sample/embeddings.csv", help="Output CSV path")

    args = parser.parse_args()

    print(f"Generating {args.num_vectors} vectors (dim={args.dim}, clusters={args.clusters})...")
    records = generate_clustered_vectors(
        num_vectors=args.num_vectors,
        dim=args.dim,
        num_clusters=args.clusters,
        noise_scale=args.noise,
        normalize=True
    )

    export_to_csv(records, args.out)

if __name__ == "__main__":
    main()
