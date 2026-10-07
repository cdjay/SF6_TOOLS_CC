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
    assert(not Layout.check_native({ slots = { { id = 9 } } }))
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
print(passed .. " slot layout tests passed")
test("explicit mounted eighty-slot bank cannot unlock old files",function()
    assert(not Layout.check_native(config(80),80))
    assert(not Layout.check_native(config(81),80))
    assert(not Layout.check_native(config(80),8))
end)
