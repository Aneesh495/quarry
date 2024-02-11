-- Compiles Quarry C API functions into a shared dynamic library (libquarry.dylib / libquarry.so)

local c_api = require("src.c_api/quarry_c")

local exports = {
    quarry_open = c_api.quarry_open,
    quarry_close = c_api.quarry_close,
    quarry_exec = c_api.quarry_exec,
    quarry_prepare = c_api.quarry_prepare,
    quarry_step = c_api.quarry_step,
    quarry_column_count = c_api.quarry_column_count,
    quarry_column_int64 = c_api.quarry_column_int64,
    quarry_column_double = c_api.quarry_column_double,
    quarry_column_text = c_api.quarry_column_text,
    quarry_column_is_null = c_api.quarry_column_is_null,
    quarry_finalize = c_api.quarry_finalize,
    quarry_vector_knn = c_api.quarry_vector_knn
}

print("Compiling lib/libquarry.dylib via terralib.saveobj...")
terralib.saveobj("lib/libquarry.dylib", exports)
print("lib/libquarry.dylib successfully generated!")
