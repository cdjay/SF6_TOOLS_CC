package.path = "autorun/?.lua;" .. package.path
local passed = 0
local function test(name, run) run(); passed = passed + 1; print("PASS " .. name) end
local function backend_fixture()
    local data = { schema = "sf6cc.training_setup.v2", fighter_id = 28, source_player = "P2", slots = {} }
    local ctx = { fighter_id = 28, fighter_name = "Mai" }
    local writes = 0
    local env = setmetatable({ json = { load_file = function() return data end },
        fs = { create_dir = function() writes = writes + 1 end } }, { __index = _G })
    local records = assert(loadfile("autorun/SF6CCTrainingLibrary/Records.lua", "t", env))()
    records.get_context = function() return ctx end
    records.backup_current = function() writes = writes + 1; return false, "backup sentinel" end
    return records, data, ctx, function() return writes end
end
test("stale cached P2 is rejected before backup or any writes", function()
    local records, _, ctx, writes = backend_fixture()
    ctx.error = "P2 temporarily unavailable"
    local ok, err = records.import_from_file("config.json")
    assert(not ok and not err:find("backup sentinel", 1, true), "Stale P2 reached backup")
    assert(writes() == 0)
end)
test("invalid file identity never matches by rounding or missing values", function()
    for _, id in ipairs({ false, "bad", 28.5, -1, 0, math.huge }) do
        local records, data, _, writes = backend_fixture()
        data.fighter_id = id
        assert(not records.import_from_file("config.json", { reject_fighter_mismatch = false }))
        assert(writes() == 0)
    end
    local records, data, ctx, writes = backend_fixture()
    data.fighter_id, ctx.fighter_id = nil, nil
    assert(not records.import_from_file("config.json") and writes() == 0)
end)
test("mismatch and explicit non-P2 source rejected before writes", function()
    local records, data, _, writes = backend_fixture()
    data.fighter_id = 19
    assert(not records.import_from_file("config.json") and writes() == 0)
    data.fighter_id, data.source_player = 28, "P1"
    assert(not records.import_from_file("config.json") and writes() == 0)
end)
test("matching and explicit mismatch override reach existing backup boundary", function()
    local records, data, _, writes = backend_fixture()
    local _, err = records.import_from_file("config.json")
    assert(err:find("backup sentinel", 1, true) and writes() > 0)
    data.fighter_id = 19
    _, err = records.import_from_file("config.json", { reject_fighter_mismatch = false })
    assert(err:find("backup sentinel", 1, true))
    data.schema, data.source_player, data.fighter_id = records.LEGACY_SCHEMA, nil, 28
    _, err = records.import_from_file("config.json")
    assert(err:find("backup sentinel", 1, true))
end)
print(passed .. " training configuration compatibility tests passed")
