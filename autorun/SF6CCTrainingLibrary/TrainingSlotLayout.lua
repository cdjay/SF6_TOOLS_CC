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

local RECORDING_REVERSAL = 4

local function cleared_reversal(item)
    item.active, item.type, item.skill_index = false, -1, -1
    if type(item.fields) == "table" then
        for name, value in pairs({ IsActive = false, IsValid = false, IsFrame = false, Type = -1,
            Delay = 0, Count = 1, SkillIndex = -1, Level = 0, Frame = 0 }) do item.fields[name] = value end
    end
end

-- Exports from the retired expansion build list every slot of an 80-slot bank,
-- even when only a few hold recordings. Up to eight recordings fold into native
-- slots 1-8: slots 1-8 keep their place, later recordings fill the free slots in
-- order, and recording reversals and slot notes follow them. Mutates data only
-- when folding succeeds; more than eight recordings fail closed.
function M.fold_native(data)
    local layout, err = M.inspect(data)
    if not layout then return false, err end
    if layout.records.span <= M.NATIVE_RECORDS then return true end
    local valid, used = {}, {}
    for index, item in ipairs(data.slots) do
        local id = item.slot
        if id == nil then id = item.id end
        if id == nil then id = index end
        if item.is_valid == true then
            valid[#valid + 1] = { id = id, item = item }
            if id <= M.NATIVE_RECORDS then used[id] = true end
        end
    end
    if #valid > M.NATIVE_RECORDS then
        return false, "此配置有 " .. #valid .. " 段录像，超过 " .. M.NATIVE_RECORDS .. " 栏位；文件未修改"
    end
    table.sort(valid, function(a, b) return a.id < b.id end)
    local map, slots, free = {}, {}, 1
    for _, entry in ipairs(valid) do
        local target = entry.id
        if target > M.NATIVE_RECORDS then
            while used[free] do free = free + 1 end
            target, used[free] = free, true
        end
        map[entry.id] = target
        entry.item.slot, entry.item.id = target, nil
        if type(entry.item.name) == "string" and entry.item.name:match("^slot%d+$") then
            entry.item.name = "slot" .. target
        end
        slots[target] = entry.item
    end
    for slot = 1, M.NATIVE_RECORDS do
        slots[slot] = slots[slot] or { slot = slot, name = "slot" .. slot, is_valid = false, is_active = false,
            frame = 0, input_num = 0, weight = 1, fields = { Frame = 0, IsValid = false, IsActive = false, Weight = 1 } }
    end
    data.slots = slots
    if type(data.record_slots) == "number" then data.record_slots = M.NATIVE_RECORDS end
    local notes = type(data.annotations) == "table" and data.annotations or nil
    if notes and type(notes.record_slots) == "table" then
        local moved = {}
        for index, note in ipairs(notes.record_slots) do
            local id = type(note) == "table" and note.slot or index
            if map[id] then
                if type(note) == "table" then note.slot = map[id] else note = { slot = map[id], text = note } end
                moved[map[id]] = note
            end
        end
        for slot = 1, M.NATIVE_RECORDS do moved[slot] = moved[slot] or { slot = slot, text = "" } end
        notes.record_slots = moved
    end
    for _, group in ipairs(groups) do
        local items = type(data.reversals) == "table" and data.reversals[group]
        local group_notes = notes and type(notes.reversals) == "table" and notes.reversals[group]
        for index, item in ipairs(type(items) == "table" and items or {}) do
            local skill = item.skill_index
            if item.type == RECORDING_REVERSAL and type(skill) == "number" and skill >= 0 then
                local target = map[skill + 1]
                local cleared = not target and skill >= M.NATIVE_RECORDS
                if target then
                    item.skill_index = target - 1
                    if type(item.fields) == "table" then item.fields.SkillIndex = target - 1 end
                elseif cleared then
                    cleared_reversal(item)
                end
                local slot = item.slot or item.index or index
                for _, note in ipairs(type(group_notes) == "table" and group_notes or {}) do
                    local binding = type(note) == "table" and note.slot == slot and note.binding
                    if type(binding) == "table" and binding.type == RECORDING_REVERSAL
                        and binding.skill_index == skill then
                        if cleared then
                            note.text, note.binding = "", nil
                        else
                            binding.skill_index = item.skill_index
                            binding.signature = "reversal-v1:" .. RECORDING_REVERSAL .. ":"
                                .. tostring(item.skill_index) .. ":" .. tostring(binding.level or 0)
                        end
                    end
                end
            end
        end
    end
    return true
end

-- Folds a foldable expansion export in place before checking native bounds.
function M.check_native(data)
    local folded, fold_err = M.fold_native(data)
    if not folded then return false, fold_err end
    local layout, err = M.inspect(data)
    if not layout then return false, err end
    local record_capacity = M.NATIVE_RECORDS
    if type(data.record_slots) == "number" and data.record_slots > record_capacity then
        return false, "录像配置超过当前已挂载的 " .. record_capacity .. " 栏位；文件未修改"
    end
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
