-- File layout bounds are not permission to allocate additional native slots.
local M = { MAX_FILE_SLOTS = 200, NATIVE_RECORDS = 8, NATIVE_REVERSALS = 10, EXPANDED_RECORDS = 80 }
local groups = { "down", "guard", "damage" }

local function integer(n, max)
    return type(n) == "number" and n >= 1 and n <= max and n % 1 == 0
end

local function inspect(items, minimum, label, reversal)
    if items == nil then return { span = minimum } end
    if type(items) ~= "table" then return nil, label .. ": expected array" end
    local count = 0
    for key in pairs(items) do
        count = count + 1
        if count > M.MAX_FILE_SLOTS or not integer(key, M.MAX_FILE_SLOTS) then
            return nil, label .. ": invalid array or exceeds 200 slots"
        end
    end
    local out, seen = { span = minimum, valid = 0, active = 0 }, {}
    for index = 1, count do
        local item = items[index]
        if type(item) ~= "table" then return nil, label .. ": missing or invalid entry" end
        local id = item.slot
        if id == nil then id = reversal and item.index or item.id end
        if id == nil then id = index end
        if not integer(id, M.MAX_FILE_SLOTS) or seen[id] then
            return nil, label .. ": invalid or duplicate slot"
        end
        seen[id], out.span = true, math.max(out.span, id, index)
        if reversal then
            if item.active == true then out.active = out.active + 1 end
        elseif item.is_valid == true then
            out.valid = out.valid + 1
            if item.is_active == true then out.active = out.active + 1 end
        end
    end
    return out
end

function M.inspect(data)
    if type(data) ~= "table" then return nil, "expected configuration object" end
    local records, err = inspect(data.slots, M.NATIVE_RECORDS, "slots", false)
    if not records then return nil, err end
    if data.reversals ~= nil and type(data.reversals) ~= "table" then
        return nil, "reversals: expected object"
    end
    local out = { records = records, reversals = {}, reversal_span = 0,
        active_reversals = data.reversals ~= nil and 0 or nil }
    for _, group in ipairs(groups) do
        local result
        result, err = inspect(data.reversals and data.reversals[group], M.NATIVE_REVERSALS, group, true)
        if not result then return nil, err end
        out.reversals[group] = result
        out.reversal_span = out.reversal_span + result.span
        if out.active_reversals then out.active_reversals = out.active_reversals + (result.active or 0) end
    end
    return out
end

function M.check_native(data, record_capacity)
    local layout, err = M.inspect(data)
    if not layout then return false, err end
    record_capacity = (record_capacity == 9 or record_capacity == M.EXPANDED_RECORDS) and record_capacity or M.NATIVE_RECORDS
    if layout.records.span > record_capacity then
        return false, "录像配置超过当前已挂载的 " .. record_capacity .. " 栏位；文件未修改"
    end
    for _, group in ipairs(groups) do
        if layout.reversals[group].span > M.NATIVE_REVERSALS then
            return false, "当前未启用原生反击扩容，每组最多 10 栏位；文件未修改"
        end
    end
    return true
end

return M
