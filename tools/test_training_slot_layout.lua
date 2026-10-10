package.path = "autorun/?.lua;" .. package.path
local Layout = require("SF6CCTrainingLibrary/TrainingSlotLayout")
local passed = 0
local function test(name, run)
    local ok, err = pcall(run)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
end
local function config(n)
    local data = { slots = {}, reversals = { down = {}, guard = {}, damage = {} } }
    for i = 1, n do data.slots[i] = { slot = i, is_valid = true, is_active = i % 2 == 0 } end
    return data
end
test("large file counts are complete but do not unlock native capacity", function()
    for _, n in ipairs({ 9, 50, 100, 200 }) do
        local data = config(n)
        local layout = assert(Layout.inspect(data))
        assert(layout.records.valid == n and layout.records.active == math.floor(n / 2))
        assert(layout.records.span == n and not Layout.check_native(data))
    end
    assert(Layout.check_native(config(8)))
end)
test("sparse arrays fractional IDs duplicate IDs and overflows fail closed", function()
    local cases = {
        { [2] = {} }, { { slot = 1.5 } }, { { slot = 1 }, { slot = 1 } },
        { { slot = 201 } }, { bogus = {} }, { false },
    }
    for _, slots in ipairs(cases) do
        assert(not Layout.inspect({ slots = slots }))
        assert(not Layout.check_native({ slots = slots }))
    end
    assert(not Layout.inspect(config(201)))
end)
test("explicit native indices cannot bypass limits through short arrays", function()
    -- An empty ninth entry is an expansion export; it folds to eight empty slots.
    local short = { slots = { { id = 9 } } }
    assert(Layout.check_native(short) and #short.slots == 8 and short.slots[1].is_valid == false)
    local data = config(8)
    data.reversals.guard = { { index = 11, active = true } }
    local layout = assert(Layout.inspect(data))
    assert(layout.reversal_span == 31 and layout.active_reversals == 1)
    assert(not Layout.check_native(data))
end)
test("legacy missing metadata stays unknown not zero", function()
    local layout = assert(Layout.inspect({}))
    assert(layout.records.valid == nil and layout.active_reversals == nil)
    assert(layout.records.span == 8 and layout.reversal_span == 30)
end)
test("capacity assertions cannot unlock ninth slot", function()
    assert(not Layout.check_native(config(9),9))
    assert(not Layout.check_native(config(9),8))
    assert(not Layout.check_native(config(10),9))
    assert(not Layout.check_native(config(10),200))
    local data=config(9); data.reversals.down={{slot=11}}
    assert(not Layout.check_native(data,9))
end)
test("explicit mounted eighty-slot bank cannot unlock old files",function()
    assert(not Layout.check_native(config(80),80))
    assert(not Layout.check_native(config(81),80))
    assert(not Layout.check_native(config(80),8))
end)
local function expansion(valid)
    local data = { record_slots = 80, slots = {}, annotations = { record_slots = {}, reversals = { down = {}, guard = {}, damage = {} } },
        reversals = { down = {}, guard = {}, damage = {} } }
    for i = 1, 80 do
        data.slots[i] = { slot = i, name = "slot" .. i, is_valid = valid[i] == true, frame = valid[i] and i or 0, input_buff = valid[i] and { i } or nil }
        data.annotations.record_slots[i] = { slot = i, text = valid[i] and ("note" .. i) or "" }
    end
    for _, group in ipairs({ "down", "guard", "damage" }) do
        for i = 1, 10 do
            data.reversals[group][i] = { slot = i, active = false, type = 0, skill_index = 0, fields = { Type = 0, SkillIndex = 0 } }
            data.annotations.reversals[group][i] = { slot = i, text = "" }
        end
    end
    return data
end
test("eighty-slot exports with recordings in slots 1-8 drop only empty tail",function()
    local data = expansion({ [1] = true, [2] = true, [5] = true })
    assert(Layout.check_native(data))
    assert(#data.slots == 8 and data.record_slots == 8)
    for i = 1, 8 do assert(data.slots[i].slot == i and data.annotations.record_slots[i].slot == i) end
    assert(data.slots[5].is_valid and data.slots[5].frame == 5 and data.annotations.record_slots[5].text == "note5")
    assert(not data.slots[3].is_valid)
    local meta = assert(Layout.inspect(data))
    assert(meta.records.span == 8 and meta.records.valid == 3)
end)
test("later recordings fill free native slots and recording reversals follow",function()
    local data = expansion({ [1] = true, [9] = true, [21] = true })
    data.reversals.down[2] = { slot = 2, active = true, type = 4, skill_index = 8, fields = { Type = 4, SkillIndex = 8, Level = 0 } }
    data.annotations.reversals.down[2] = { slot = 2, text = "反击9", binding = { type = 4, skill_index = 8, level = 0, signature = "reversal-v1:4:8:0" } }
    data.reversals.guard[1] = { slot = 1, active = true, type = 4, skill_index = 30, fields = { Type = 4, SkillIndex = 30 } }
    data.annotations.reversals.guard[1] = { slot = 1, text = "空槽反击", binding = { type = 4, skill_index = 30, level = 0 } }
    data.reversals.damage[3] = { slot = 3, active = true, type = 5, skill_index = 8, fields = { Type = 5, SkillIndex = 8 } }
    assert(Layout.check_native(data))
    assert(data.slots[1].frame == 1 and data.slots[2].frame == 9 and data.slots[3].frame == 21)
    assert(data.slots[2].slot == 2 and data.slots[2].name == "slot2" and data.slots[4].is_valid == false)
    assert(data.annotations.record_slots[2].text == "note9" and data.annotations.record_slots[3].text == "note21")
    local down = data.reversals.down[2]
    assert(down.active and down.skill_index == 1 and down.fields.SkillIndex == 1)
    local note = data.annotations.reversals.down[2]
    assert(note.text == "反击9" and note.binding.skill_index == 1 and note.binding.signature == "reversal-v1:4:1:0")
    local guard = data.reversals.guard[1]
    assert(not guard.active and guard.type == -1 and guard.skill_index == -1 and guard.fields.SkillIndex == -1)
    assert(data.annotations.reversals.guard[1].text == "" and data.annotations.reversals.guard[1].binding == nil)
    -- Non-recording reversals index moves, not recording slots.
    assert(data.reversals.damage[3].skill_index == 8 and data.reversals.damage[3].type == 5)
end)
test("more than eight recordings fail closed and leave the file untouched",function()
    local valid = {}
    for i = 1, 12 do valid[i] = true end
    local data = expansion(valid)
    local ok, err = Layout.check_native(data)
    assert(not ok and err:find("12 段录像", 1, true))
    assert(#data.slots == 80 and data.record_slots == 80 and data.slots[9].slot == 9)
    assert(not Layout.fold_native(data) and #data.slots == 80)
end)
print(passed .. " slot layout tests passed")
