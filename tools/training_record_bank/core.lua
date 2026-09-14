-- Offline draft only. No native handles, hooks, file access or automatic saving.
local M = { SCHEMA = "sf6cc.training_record_bank.draft2", LEGACY_SCHEMA = "sf6cc.training_record_bank.draft1",
    MAX_RECORDS = 200, MAX_FRAMES = 3600 }
local MAX_ID = 2147483647
local GROUPS = { down = 1, guard = 2, damage = 3 }

local function integer(value, low, high)
    return type(value) == "number" and value % 1 == 0 and value >= low and value <= high
end
local function array(value, maximum)
    if type(value) ~= "table" then return nil end
    local count = 0
    for key in pairs(value) do
        count = count + 1
        if count > maximum or not integer(key, 1, maximum) then return nil end
    end
    for i = 1, count do if value[i] == nil then return nil end end
    return count
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function name_valid(value)
    if type(value) ~= "string" or #value > 512 or value:find("[%c<>]") then return false end
    local ok, count = pcall(utf8.len, value)
    return ok and count ~= nil and count <= 128
end
local function scalars(value)
    if value == nil then return {} end
    if type(value) ~= "table" then return nil end
    local out, count = {}, 0
    for key, field in pairs(value) do
        count = count + 1
        if count > 64 or type(key) ~= "string" or #key > 128 then return nil end
        local kind = type(field)
        if kind == "number" then
            if field ~= field or math.abs(field) > 9007199254740991 then return nil end
        elseif kind == "string" then
            if #field > 256 then return nil end
        elseif kind ~= "boolean" then return nil end
        out[key] = field
    end
    return out
end

local function recording(value)
    if type(value) ~= "table" or not integer(value.frame, 1, M.MAX_FRAMES)
        or array(value.input_buff, M.MAX_FRAMES) ~= value.frame then return nil end
    local fields, input_fields = scalars(value.fields), scalars(value.input_fields)
    if not fields or not input_fields then return nil end
    -- Only known presentation/selection and duplicate length fields are excluded.
    -- Retain other native scalars: missing evidence must not merge distinct recordings.
    fields.IsValid, fields.IsActive, fields.Weight, fields.Frame = nil, nil, nil, nil
    input_fields.Num = nil
    local inputs = {}
    for i, input in ipairs(value.input_buff) do
        if not integer(input, 0, 4294967295) then return nil end
        inputs[i] = input
    end
    return { frame = value.frame, input_buff = inputs, fields = fields, input_fields = input_fields }
end

local function sort_references(references)
    table.sort(references, function(a, b)
        if a.group ~= b.group then return GROUPS[a.group] < GROUPS[b.group] end
        return a.slot < b.slot
    end)
end

local function reference_key(group, slot)
    if not GROUPS[group] or not integer(slot, 1, M.MAX_RECORDS) then return nil end
    return group .. ":" .. string.format("%.0f", slot)
end

local function validate(document)
    if type(document) ~= "table" or (document.schema ~= M.SCHEMA and document.schema ~= M.LEGACY_SCHEMA)
        or not integer(document.fighter_id, 0, MAX_ID) or document.source_player ~= "P2"
        or not integer(document.next_id, 1, MAX_ID)
        or not array(document.records, M.MAX_RECORDS) then return nil, "invalid bank header" end
    local legacy = document.schema == M.LEGACY_SCHEMA
    local allowed = { schema = true, fighter_id = true, source_player = true, next_id = true, records = true,
        record_refs = not legacy }
    for key in pairs(document) do if not allowed[key] then return nil, "unsupported bank field" end end
    local out = { schema = M.SCHEMA, fighter_id = document.fighter_id, source_player = "P2",
        next_id = document.next_id, records = {}, record_refs = {} }
    local ids = {}
    for _, item in ipairs(document.records) do
        if type(item) ~= "table" or not integer(item.id, 1, document.next_id - 1) or ids[item.id]
            or not name_valid(item.name) or type(item.enabled) ~= "boolean"
            or not integer(item.weight, 0, MAX_ID) then return nil, "invalid record metadata" end
        local keys = { id = true, name = true, enabled = true, weight = true, recording = true }
        for key in pairs(item) do if not keys[key] then return nil, "unsupported record field" end end
        local source = recording(item.recording)
        if not source or not equal(source, item.recording) then return nil, "noncanonical recording" end
        ids[item.id] = true
        out.records[#out.records + 1] = { id = item.id, name = item.name, enabled = item.enabled,
            weight = item.weight, recording = source }
    end
    local references = legacy and {} or document.record_refs
    if not array(references, M.MAX_RECORDS * 3) then return nil, "invalid recording references" end
    local seen = {}
    for _, ref in ipairs(references) do
        if type(ref) ~= "table" then return nil, "invalid recording reference" end
        local key = reference_key(ref.group, ref.slot)
        if not key or seen[key] or not integer(ref.record_id, 1, MAX_ID) or not ids[ref.record_id] then
            return nil, "duplicate invalid or dangling recording reference"
        end
        for name in pairs(ref) do
            if name ~= "group" and name ~= "slot" and name ~= "record_id" then return nil, "unsupported reference field" end
        end
        seen[key] = true
        out.record_refs[#out.record_refs + 1] = { group = ref.group, slot = ref.slot, record_id = ref.record_id }
    end
    sort_references(out.record_refs)
    return out
end

function M.empty(fighter_id)
    local bank = { schema = M.SCHEMA, fighter_id = fighter_id, source_player = "P2", next_id = 1, records = {}, record_refs = {} }
    return validate(bank)
end

function M.open(document)
    local current, err = validate(document)
    if not current then return nil, err end
    local saved, saving = copy(current), false
    local self = {}
    local function find(id)
        for index, item in ipairs(current.records) do if item.id == id then return item, index end end
    end
    local function append(target, source)
        for _, item in ipairs(target.records) do
            if equal(item.recording, source.recording) then return item.id, false end
        end
        if #target.records >= M.MAX_RECORDS or target.next_id >= MAX_ID then return nil, "bank capacity exhausted" end
        local item = copy(source)
        item.id, target.next_id = target.next_id, target.next_id + 1
        target.records[#target.records + 1] = item
        return item.id, true
    end
    function self.snapshot() return copy(current) end
    function self.is_dirty() return not equal(current, saved) end
    function self.stage(document)
        if saving then return false, "save in progress" end
        local candidate, reason = validate(document)
        if not candidate then return false, reason end
        if candidate.fighter_id ~= current.fighter_id then return false, "different P2 character" end
        if candidate.next_id < current.next_id then return false, "record ID counter regressed" end
        if not equal(candidate.record_refs, current.record_refs) then
            return false, "change references explicitly before capturing recordings"
        end
        for _, item in ipairs(candidate.records) do
            if not find(item.id) and item.id < current.next_id then return false, "retired record ID reused" end
        end
        -- This replaces the working capture only, never the saved baseline.
        current = candidate
        return true
    end
    function self.discard()
        if saving then return false, "save in progress" end
        current = copy(saved)
        return true
    end
    function self.add_slot(slot)
        if saving then return nil, "save in progress" end
        if type(slot) ~= "table" or slot.is_valid ~= true or not name_valid(slot.name)
            or type(slot.is_active) ~= "boolean" or not integer(slot.weight, 0, MAX_ID) then
            return nil, "invalid captured recording slot"
        end
        if slot.input_num ~= nil and slot.input_num ~= slot.frame then return nil, "inconsistent playback length" end
        local source = recording(slot)
        if not source then return nil, "invalid captured input" end
        return append(current, { name = slot.name, enabled = slot.is_active, weight = slot.weight, recording = source })
    end
    function self.edit(id, changes)
        if saving then return false, "save in progress" end
        local item = find(id)
        if not item or type(changes) ~= "table" then return false, "unknown record or invalid changes" end
        for key, value in pairs(changes) do
            if key == "name" then
                if not name_valid(value) then return false, "invalid name" end
            elseif key == "enabled" then
                if type(value) ~= "boolean" then return false, "invalid enabled flag" end
            elseif key == "weight" then
                if not integer(value, 0, MAX_ID) then return false, "invalid weight" end
            else return false, "unsupported edit" end
        end
        for key, value in pairs(changes) do item[key] = value end
        return true
    end
    function self.delete(id)
        if saving then return false, "save in progress" end
        local _, index = find(id)
        if not index then return false, "unknown record" end
        for _, ref in ipairs(current.record_refs) do
            if ref.record_id == id then return false, "recording is referenced; unlink explicitly before deleting" end
        end
        table.remove(current.records, index)
        return true
    end
    function self.set_reference(group, slot, id)
        if saving then return false, "save in progress" end
        local key = reference_key(group, slot)
        if not key or (id ~= nil and not find(id)) then return false, "invalid reference target" end
        for index, ref in ipairs(current.record_refs) do
            if reference_key(ref.group, ref.slot) == key then
                if id == nil then table.remove(current.record_refs, index) else ref.record_id = id end
                return true
            end
        end
        if id ~= nil then
            current.record_refs[#current.record_refs + 1] = { group = group, slot = slot, record_id = id }
            sort_references(current.record_refs)
        end
        return true
    end
    function self.reference_plan(record_capacity, reversal_capacity)
        if not integer(record_capacity, 1, M.MAX_RECORDS) or not integer(reversal_capacity, 1, M.MAX_RECORDS)
            or #current.records > record_capacity then return nil, "unsupported target capacity" end
        local indices, plan = {}, {}
        for index, record in ipairs(current.records) do indices[record.id] = index - 1 end
        for _, ref in ipairs(current.record_refs) do
            if ref.slot > reversal_capacity then return nil, "unsupported reversal reference capacity" end
            plan[#plan + 1] = { group = ref.group, slot = ref.slot, record_id = ref.record_id,
                record_index = indices[ref.record_id] }
        end
        return plan
    end
    function self.merge(document)
        if saving then return nil, "save in progress" end
        local source, reason = validate(document)
        if not source then return nil, reason end
        if source.fighter_id ~= current.fighter_id then return nil, "different P2 character" end
        local candidate, mapping = copy(current), {}
        for _, item in ipairs(source.records) do
            local id, result = append(candidate, item)
            if not id then return nil, result end
            mapping[item.id] = id
        end
        local keys = {}
        for _, ref in ipairs(candidate.record_refs) do keys[reference_key(ref.group, ref.slot)] = ref.record_id end
        for _, ref in ipairs(source.record_refs) do
            local key, id = reference_key(ref.group, ref.slot), mapping[ref.record_id]
            if keys[key] and keys[key] ~= id then return nil, "reference location conflict" end
            if not keys[key] then
                candidate.record_refs[#candidate.record_refs + 1] = { group = ref.group, slot = ref.slot, record_id = id }
                keys[key] = id
            end
        end
        sort_references(candidate.record_refs)
        current = candidate
        return mapping
    end
    function self.save(writer)
        if saving then return false, "save in progress" end
        if type(writer) ~= "function" then return false, "explicit durable writer required" end
        saving = true
        local expected = copy(current)
        local ok, result, reason = pcall(writer, copy(expected))
        saving = false
        if not ok or result ~= true then return false, ok and (reason or "save failed") or tostring(result) end
        saved = expected
        return true
    end
    return self
end

return M
