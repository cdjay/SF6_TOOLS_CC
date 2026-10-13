package.path = "autorun/?.lua;autorun/?/init.lua;" .. package.path

local Json = require("tools/training_record_bank/vendor/dkjson")

local function read_roster_file()
    local file = assert(io.open("data/SF6CC/fighters.json", "rb"))
    local text = file:read("*a")
    file:close()
    return assert(Json.decode(text))
end

local previous_json = json
local previous_safe_loader = safe_load_json
local previous_roster = package.loaded["func/FighterRoster"]
local previous_catalog = package.loaded["func/HitConfirm/MoveCatalog"]
safe_load_json = nil
local reads = 0
json = {
    load_file = function(path)
        assert(path == "SF6CC/fighters.json", "roster must use the canonical runtime path: " .. tostring(path))
        reads = reads + 1
        return read_roster_file()
    end,
}

package.loaded["func/FighterRoster"] = nil
local FighterRoster = require("func/FighterRoster")

local status = FighterRoster.status()
assert(status.loaded == true, "shipped roster must load: " .. tostring(status.error))
assert(status.count == 32, "roster fighter count changed: " .. tostring(status.count))

-- Data keys: known fighters keep their key, a fighter missing from the roster
-- keeps a distinct ESF key, and an empty slot stays Unknown.
assert(FighterRoster.profile_key({ id = 1, key = "ESF_001" }) == "Ryu")
assert(FighterRoster.profile_key({ id = 33, key = "ESF_033" }) == "Yasmine")
assert(FighterRoster.profile_key({ id = 34, key = "ESF_034" }) == "Arjun")
assert(FighterRoster.profile_key({ id = 35, key = "ESF_035" }) == "ESF_035")
assert(FighterRoster.profile_key({ id = -1, key = "ESF_000" }) == "Unknown")
assert(FighterRoster.profile_key({ key = "ESF_026" }) == "MBison")
assert(FighterRoster.profile_key(62) == "Unknown", "World Tour gimmick IDs are not fighters")
assert(FighterRoster.profile_key(23) == "ESF_023" and FighterRoster.profile_key(24) == "ESF_024",
    "unreleased IDs 23/24 must not be labeled as M. Bison or Terry")
assert(FighterRoster.is_known(34) and not FighterRoster.is_known(35))
assert(FighterRoster.name_zh(34) == "阿俊")

-- Display names, including spellings stored in older training-library files.
assert(FighterRoster.name_en(13) == "A.K.I.")
assert(FighterRoster.name_en(31) == "Alex" and FighterRoster.name_en(33) == "Yasmine")
assert(FighterRoster.name_zh("CViper") == "毒蛇")
assert(FighterRoster.zh_for_display_name("Viper") == "毒蛇")
assert(FighterRoster.zh_for_display_name("A.K.I") == "阿鬼")
assert(FighterRoster.zh_for_display_name("Mai Shiranui") == "不知火舞")
assert(FighterRoster.zh_for_display_name("Future Fighter") == nil)

-- The standalone training library may only load SF6CCTrainingLibrary/*
-- modules, so it keeps its own name tables. They must agree with the roster.
local function library_name_table(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local block = assert(source:match("local CHARACTER_NAMES = (%b{})"), path)
    return assert(load("return " .. block, "=" .. path, "t", {}))()
end
local CharacterNames = dofile("autorun/SF6CCTrainingLibrary/CharacterNames.lua")
for _, path in ipairs({ "autorun/SF6CCTrainingLibrary/Records.lua", "autorun/func/DynamicRecords.lua" }) do
    local names = library_name_table(path)
    for id, name in pairs(names) do
        local fighter = FighterRoster.fighter_by_id(id)
        assert(fighter, path .. " names fighter " .. id .. " that the roster does not know")
        local accepted = { [fighter.name_en] = true }
        for _, alias in ipairs(fighter.aliases) do accepted[alias] = true end
        assert(accepted[name], path .. " fighter " .. id .. " is '" .. name .. "', roster says " .. fighter.name_en)
        local label = CharacterNames(name)
        assert(fighter.name_zh == name or label == fighter.name_zh .. " " .. name,
            "library Chinese name for " .. name .. " differs from the roster: " .. label)
    end
    for _, fighter in ipairs(FighterRoster.all()) do
        assert(names[fighter.id], path .. " is missing rostered fighter " .. fighter.key)
    end
end

package.loaded["func/HitConfirm/MoveCatalog"] = nil
local MoveCatalog = require("func/HitConfirm/MoveCatalog")
assert(MoveCatalog.resolve_character({ id = 1, key = "ESF_001" }).name == "Ryu")
assert(MoveCatalog.resolve_character({ id = 34, key = "ESF_034" }).name == "Arjun")
local future = MoveCatalog.resolve_character({ id = 35, key = "ESF_035" })
assert(future and future.name == "ESF_035" and future.key == "ESF_035" and future.id == 35)
assert(MoveCatalog.resolve_character({ id = -1, key = "ESF_000" }) == nil)

-- Every rostered fighter must ship a generated command table.
for _, fighter in ipairs(FighterRoster.all()) do
    local file = io.open("data/TrainingComboTrials_data/command_display/" .. fighter.key .. ".json", "rb")
    assert(file, "missing command_display for rostered fighter " .. fighter.key)
    file:close()
end

-- A failed read is cached (no per-frame disk IO) until reload().
local reads_before = reads
FighterRoster.load()
FighterRoster.profile_key(1)
assert(reads == reads_before, "a loaded roster must not be read again")

-- Validation rejects ambiguous rosters instead of guessing.
local function rejects(document, message)
    FighterRoster.use_document(document)
    local loaded, err = FighterRoster.load()
    assert(loaded == nil and err, message)
end
rejects({ schema = "other", fighters = {} }, "schema must be checked")
rejects({ schema = FighterRoster.SCHEMA, fighters = {
    { id = 1, key = "Ryu", name_en = "Ryu", name_zh = "隆" },
    { id = 1, key = "Ken", name_en = "Ken", name_zh = "肯" },
} }, "duplicate ids must be rejected")
rejects({ schema = FighterRoster.SCHEMA, fighters = {
    { id = 1, key = "Chun Li", name_en = "Chun-Li", name_zh = "春丽" },
} }, "keys must be file-name safe")
rejects({ schema = FighterRoster.SCHEMA, fighters = {
    { id = 1, key = "Ryu", name_en = "Ryu", name_zh = "隆" },
    { id = 2, key = "Ken", name_en = "Ryu", name_zh = "肯" },
} }, "two fighters cannot share a display name")
assert(FighterRoster.profile_key(1) == "ESF_001", "an invalid roster falls back to ESF keys")

-- Without any JSON loader nothing is cached, so a later loader still works.
FighterRoster.use_document(nil)
json = nil
assert(FighterRoster.load() == nil)
json = { load_file = function() return read_roster_file() end }
assert(FighterRoster.profile_key(2) == "Luke", "missing loader must not poison the cache")

json = previous_json
safe_load_json = previous_safe_loader
package.loaded["func/FighterRoster"] = previous_roster
package.loaded["func/HitConfirm/MoveCatalog"] = previous_catalog
print("fighter roster tests passed")
