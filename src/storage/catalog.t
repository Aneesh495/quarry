-- Quarry database catalog subsystem
-- Manages schema metadata, registered tables, and relational table lookup.

local C = require("src.common.c").C
local types = require("src.types.type")
local tbl = require("src.storage/table")

local cat = {}

cat.MAX_TABLES = 256

struct Catalog {
    num_tables: uint32,
    tables: tbl.Table[256]
}

terra Catalog:init()
    self.num_tables = 0
end

terra Catalog:destroy()
    for i = 0, self.num_tables do
        self.tables[i]:destroy()
    end
    self.num_tables = 0
end

terra Catalog:get_table(name: &int8) : &tbl.Table
    if name == nil then return nil end
    for i = 0, self.num_tables do
        if C.strcmp(&(self.tables[i].name[0]), name) == 0 then
            return &(self.tables[i])
        end
    end
    return nil
end

terra Catalog:has_table(name: &int8) : bool
    return self:get_table(name) ~= nil
end

terra Catalog:create_table(name: &int8, num_cols: uint32, col_names: &(&int8), col_types: &types.DataType) : &tbl.Table
    if self:has_table(name) then
        return nil -- already exists
    end
    if self.num_tables >= cat.MAX_TABLES then
        return nil
    end

    var t_idx = self.num_tables
    self.tables[t_idx]:init(name, num_cols, col_names, col_types)
    self.num_tables = self.num_tables + 1
    return &(self.tables[t_idx])
end

terra Catalog:drop_table(name: &int8) : bool
    for i = 0, self.num_tables do
        if C.strcmp(&(self.tables[i].name[0]), name) == 0 then
            self.tables[i]:destroy()
            -- Shift remaining tables left
            for j = i, self.num_tables - 1 do
                self.tables[j] = self.tables[j + 1]
            end
            self.num_tables = self.num_tables - 1
            return true
        end
    end
    return false
end

cat.Catalog = Catalog
return cat
