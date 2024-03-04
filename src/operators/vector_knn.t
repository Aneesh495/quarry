-- Quarry physical vector k-NN operator
-- Pipeline breaker operator maintaining top-K nearest neighbors across chunks
-- with SIMD distance acceleration and score projection.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local dist = require("src.vector/distance")

local DataChunk = chunk.DataChunk

local vknn = {}

vknn.MAX_TOP_K = 1024

struct KNNEntry {
    row_id: int64,
    distance: float
}

struct PhysicalVectorKNN {
    vector_col_idx: uint32,
    id_col_idx: uint32,
    dim: uint32,
    metric: int32,
    k: uint32,
    query_vector: &float,
    current_count: uint32,
    top_entries: KNNEntry[1024]
}

terra PhysicalVectorKNN:init(
    vec_col: uint32,
    id_col: uint32,
    dim: uint32,
    metric: int32,
    k: uint32,
    query_vec: &float
)
    self.vector_col_idx = vec_col
    self.id_col_idx = id_col
    self.dim = dim
    self.metric = metric
    if k > vknn.MAX_TOP_K then
        self.k = vknn.MAX_TOP_K
    else
        self.k = k
    end
    self.query_vector = query_vec
    self.current_count = 0
end

terra PhysicalVectorKNN:destroy()
    self.current_count = 0
end

-- Insert entry maintaining sorted order by distance ascending
terra PhysicalVectorKNN:insert_candidate(row_id: int64, d: float)
    if self.current_count < self.k then
        var insert_pos = self.current_count
        while insert_pos > 0 and self.top_entries[insert_pos - 1].distance > d do
            self.top_entries[insert_pos] = self.top_entries[insert_pos - 1]
            insert_pos = insert_pos - 1
        end
        self.top_entries[insert_pos].row_id = row_id
        self.top_entries[insert_pos].distance = d
        self.current_count = self.current_count + 1
    else
        if d >= self.top_entries[self.k - 1].distance then
            return -- Farther than our current kth neighbor
        end
        var insert_pos = self.k - 1
        while insert_pos > 0 and self.top_entries[insert_pos - 1].distance > d do
            self.top_entries[insert_pos] = self.top_entries[insert_pos - 1]
            insert_pos = insert_pos - 1
        end
        self.top_entries[insert_pos].row_id = row_id
        self.top_entries[insert_pos].distance = d
    end
end

-- Consume an incoming morsel / chunk
terra PhysicalVectorKNN:sink_chunk(c: &DataChunk)
    if c == nil or c.num_rows == 0 then return end

    var vcol = c:get_column(self.vector_col_idx)
    var idcol = c:get_column(self.id_col_idx)
    if vcol == nil then return end

    var n = c.num_rows
    for i = 0, n do
        var phys_idx = c:get_row_index(i)
        if not vcol:is_null(phys_idx) then
            var v_ptr = vcol:get_vector(phys_idx)
            var d : float = 0.0f
            if self.metric == dist.METRIC_COSINE then
                d = dist.cosine_dist(v_ptr, self.query_vector, self.dim)
            else
                d = dist.l2(v_ptr, self.query_vector, self.dim)
            end

            var rid : int64 = [int64](phys_idx)
            if idcol ~= nil and not idcol:is_null(phys_idx) then
                rid = idcol:get_i64(phys_idx)
            end

            self:insert_candidate(rid, d)
        end
    end
end

-- Emit top-K results into an output chunk
terra PhysicalVectorKNN:emit_results(out_chunk: &DataChunk) : uint32
    if out_chunk == nil then return 0 end

    var n = self.current_count
    out_chunk:reset()

    for i = 0, n do
        if out_chunk.num_columns >= 1 then
            out_chunk.columns[0]:set_i64(i, self.top_entries[i].row_id)
        end
        if out_chunk.num_columns >= 2 then
            out_chunk.columns[1]:set_f64(i, [double](self.top_entries[i].distance))
        end
    end

    out_chunk.num_rows = n
    return n
end

vknn.PhysicalVectorKNN = PhysicalVectorKNN
vknn.KNNEntry = KNNEntry

return vknn
