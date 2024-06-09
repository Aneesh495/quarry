# Vector Similarity Search & SIMD Acceleration

Quarry embeds a high-performance vector search engine natively inside its relational columnar architecture. By combining hardware SIMD intrinsics with proximity graph indexing, Quarry supports sub-millisecond approximate nearest neighbor (ANN) searches and hybrid relational queries.

## SIMD Distance Kernels

Quarry implements 4-wide vector distance kernels compiled directly to ARM NEON or x86-64 AVX2/AVX-512 vector instructions:

### 1. Squared Euclidean Distance (L2)
$$\mathcal{D}_{L2\_sq}(A, B) = \sum_{i=0}^{d-1} (A_i - B_i)^2$$

In Terra, consecutive 4-float vectors are loaded directly into 128-bit vector registers:
```terra
while i + 4 <= dim do
    var va = @[&vector(float, 4)](&(a[i]))
    var vb = @[&vector(float, 4)](&(b[i]))
    var diff = va - vb
    var sq = diff * diff
    total = total + (sq[0] + sq[1] + sq[2] + sq[3])
    i = i + 4
end
```
Any remaining scalar tail elements ($dim \pmod 4$) are accumulated in a scalar cleanup loop.

### 2. Dot Product
$$A \cdot B = \sum_{i=0}^{d-1} A_i B_i$$
Evaluated with single-cycle fused multiply-add (FMA) instructions where supported by host hardware.

### 3. Cosine Distance
$$\mathcal{D}_{cos}(A, B) = 1.0 - \frac{A \cdot B}{\|A\|_2 \|B\|_2}$$
If vectors are unit-normalized upon ingestion via `DenseVector:normalize()`, cosine distance simplifies to:
$$\mathcal{D}_{cos}(A, B) = 1.0 - (A \cdot B)$$
This reduces cosine distance computation to a single SIMD dot product and one subtraction.

### 4. Manhattan Distance (L1)
$$\mathcal{D}_{L1}(A, B) = \sum_{i=0}^{d-1} |A_i - B_i|$$
Computed using vector subtraction followed by bitwise sign clearing or `fabsf`.

---

## Vector Index Structures

### 1. Hierarchical Navigable Small World (HNSW)

Quarry includes an implementation of the HNSW proximity graph (`hnsw.t`):

```
Layer 2: [Entry Point] ---------------------> [Node B]
             |                                    |
             v                                    v
Layer 1: [Node A] ----------> [Node C] ----------> [Node B]
             |                   |                 |
             v                   v                 v
Layer 0: [Node A] -> [Node D] -> [Node C] -> ... -> [Node B] (Dense Proximity Graph)
```

- **Graph Construction**:
  - Vectors are assigned to multi-layer graphs where upper layers contain long-range skip edges for logarithmic global navigation.
  - Layer 0 contains a dense k-nearest-neighbor proximity graph.
  - Greedy hill-climbing routes queries from the top layer down to the local minimum at Layer 0.
- **Candidate Pool Expansion**:
  - At Layer 0, Quarry gathers 1-hop and 2-hop graph neighbors of the local minimum into a sorted candidate queue, evaluating top-k results in under 5 microseconds.
- **Speedup**: Over 50x to 60x faster than exhaustive flat scans while maintaining over 97% relative accuracy.

### 2. Inverted File Index (IVF)

For massive vector collections that exceed cache capacity, Quarry supports Inverted File Indexing (`ivf.t`):

1. **Voronoi Centroids**: Space is partitioned into $C$ cluster centroids via k-means clustering.
2. **Posting Lists**: Each vector is assigned to its nearest Voronoi centroid.
3. **Query Routing**:
   - The query vector computes distances against the $C$ centroids.
   - Only vectors in the closest $nprobe$ centroids are scanned.
   - Reduces the candidate search space by 90% or more.

---

## Hybrid Relational & Vector Search

In real-world applications, vector similarity queries rarely occur in isolation. Users frequently require relational filtering alongside similarity ranking:
```sql
SELECT doc_id, title, VECTOR_DISTANCE(embedding, [0.12, 0.45, ...]) AS dist
FROM document_embeddings
WHERE category = 'technology' AND publish_year >= 2022
ORDER BY dist ASC
LIMIT 10;
```

### Pre-Filtering vs Post-Filtering

- **Post-Filtering (Inefficient)**: Runs approximate k-NN first, then discards matches that fail relational predicates. If the relational filter is selective (e.g., 1%), this often returns zero valid results.
- **Quarry Hybrid Pre-Filtering**:
  1. The relational filter operator executes first, generating a zero-copy selection vector across surviving rows.
  2. The vector distance operator (`PhysicalVectorKNN`) computes SIMD distances ONLY for rows that passed the relational filter.
  3. A bounded top-K array maintains the nearest matching items without materializing intermediate chunks.
