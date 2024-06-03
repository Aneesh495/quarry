# Columnar Storage & Compression Architecture

Quarry stores tabular data in a block-oriented, columnar memory layout designed for maximal memory bandwidth efficiency, SIMD vectorization, and minimal memory footprint.

## Memory Architecture

### 1. DataChunk Layout

A `Table` in Quarry consists of a sequence of `DataChunk` structures. Each `DataChunk` represents a horizontal slice of up to 2,048 rows across all table columns:

```
+---------------------------------------------------------------------------------+
|                                   DataChunk                                     |
|  num_rows: 2048 | num_columns: 4 | capacity: 2048 | selection_vector: [uint32]  |
+---------------------------------------------------------------------------------+
| Column 0 (INT64):                                                               |
|   Validity: [11111111...11110111] (64-bit words)                                |
|   Data:     [ 100, 200, 300, 400, ... ] (64-byte aligned int64 buffer)          |
+---------------------------------------------------------------------------------+
| Column 1 (DOUBLE):                                                              |
|   Validity: [11111111...11111111]                                               |
|   Data:     [ 12.50, 45.20, 99.00, ... ] (64-byte aligned double buffer)        |
+---------------------------------------------------------------------------------+
| Column 2 (VARCHAR):                                                             |
|   Validity: [11111111...11111111]                                               |
|   Views:    [ {len: 4, prefix: 'ABCD', ptr: nil}, ... ] (16-byte StringViews)   |
+---------------------------------------------------------------------------------+
| Column 3 (VECTOR_F32):                                                          |
|   Validity: [11111111...11111111]                                               |
|   Data:     [ float[384], float[384], ... ] (64-byte aligned contiguous floats)|
+---------------------------------------------------------------------------------+
```

### 2. 64-Byte Cache Line Alignment

Every column buffer is allocated via POSIX aligned memory primitives:
```c
posix_memalign(&ptr, 64, nbytes);
```
Aligning all buffer pointers to 64-byte boundaries guarantees that:
- SIMD load instructions (`vmovaps`, `vld1q_f32`) never cross hardware cache-line boundaries.
- Memory access avoids unaligned load penalties.
- Hardware prefetchers operate at peak throughput.

### 3. Selection Vector Zero-Copy Masking

When filtering operations evaluate a predicate, copying matched rows into a new memory buffer wastes CPU cycles and pollutes L2/L3 caches. Quarry uses a zero-copy Selection Vector:
- A flat array of 32-bit row indices pointing to surviving rows in the current chunk.
- Operators downstream consume tuples indirectly:
  ```terra
  var phys_idx = chunk:get_row_index(i)
  var val = col:get_i64(phys_idx)
  ```
- If no filter has been applied, `sel_vector` is `nil`, allowing direct array indexing with zero pointer indirection.

### 4. German / Umbra Style String Views

Variable-length text columns frequently cause memory fragmentation and cache misses in analytical systems. Quarry adopts the 16-byte StringView layout pioneered by Cedar and Umbra:

```
+---------------------------------------------------------------------+
|                          StringView (16 Bytes)                      |
|  +--------------------+---------------------+--------------------+  |
|  | Length (4 Bytes)   | Prefix (4 Bytes)    | Pointer (8 Bytes)  |  |
|  +--------------------+---------------------+--------------------+  |
+---------------------------------------------------------------------+
```

- **Short Strings (<= 4 bytes)**: Inlined directly into the `prefix` buffer. Pointer is set to `nil`. Requires zero external memory allocations.
- **Long Strings (> 4 bytes)**: First 4 bytes copied to `prefix`. Remaining bytes allocated sequentially in query-scoped memory bump arenas.
- **Equality Short-Circuit**: Comparing two strings first checks `len` and a single 32-bit integer comparison on `prefix`. Only if both match is the 8-byte pointer dereferenced for full `strcmp`. Over 95% of string comparisons reject immediately in registers.

---

## Columnar Compression Codecs

Quarry includes four specialized compression codecs designed for in-register decompression and direct predicate evaluation.

### 1. Integer Bit-Packing (`bitpack.t`)
- Analyzes column bounds to calculate minimum required bit-width:
  $$\text{bit\_width} = 64 - \text{clz64}(\text{max\_val})$$
- Packs variable-width unsigned integers (1 to 32 bits) into contiguous 64-bit words.
- Employs bitwise shifts and masks to unpack values with zero branching.

### 2. Frame-of-Reference / Delta-FOR (`delta_for.t`)
- Ideal for clustered or sorted numeric columns (timestamps, IDs, order keys).
- Computes base reference value: $base = \min_{i} (v_i)$.
- Stores base value once per chunk, then bit-packs relative deltas: $\Delta_i = v_i - base$.
- Enables decompression directly into vector registers:
  $$v_i = base + \text{unpack}(\Delta_i)$$

### 3. Run-Length Encoding (`rle.t`)
- Encodes sequences of identical repeated values into `(value, count)` pairs.
- Achieves extreme compression ratios (over 600x) on low-cardinality sorted columns.
- **Direct Predicate Pushdown**: Filters against RLE blocks evaluate equality once per run rather than once per tuple:
  ```terra
  if run_val == target then
      // Emits entire run of indices in a single operation
      emit_consecutive_indices(start_idx, count)
  end
  ```

### 4. Dictionary Encoding (`dict.t`)
- Maps repetitive string categories (e.g., country codes, market segments, order statuses) into 8-bit integer codes.
- Supports up to 256 unique symbols per block.
- **Code Filtering Pushdown**: Equality queries first look up the target string once in the 256-entry dictionary table to find its 8-bit code, then scan the 8-bit code vector with 16-wide or 32-wide SIMD byte comparisons.
