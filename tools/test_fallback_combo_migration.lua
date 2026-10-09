package.path = "autorun/?.lua;autorun/?/init.lua;" .. package.path

local Migration = require("func/ComboTrials/FallbackComboMigration")

-- In-memory CustomCombos tree: folder -> { file name -> sequence }.
local tree = {
    ESF_034 = {
        ["ESF_034_COMBO_2MK_D1.json"] = { { _xt_meta = { character = "ESF_034", title = "a" }, id = 600 } },
        ["ESF_034_COMBO_SA3.json"] = { { _xt_meta = { character = "ESF_034", title = "b" }, id = 601 } },
        ["community.json"] = { { _xt_meta = { title = "c" }, id = 602 } },
        ["broken.json"] = "not a combo",
    },
    Arjun = {
        ["Arjun_COMBO_SA3.json"] = { { _xt_meta = { character = "Arjun", title = "kept" }, id = 700 } },
    },
}
local globs, dumps = 0, {}
local deps = {
    glob = function(pattern)
        globs = globs + 1
        local folder = pattern:match("CustomCombos\\\\([^\\]+)\\\\")
        local result = {}
        for name in pairs(tree[folder] or {}) do
            result[#result + 1] = "TrainingComboTrials_data\\CustomCombos\\" .. folder .. "\\" .. name
        end
        table.sort(result)
        return result
    end,
    load = function(path)
        local folder, name = path:match("CustomCombos[/\\]([^/\\]+)[/\\]([^/\\]+)$")
        local value = tree[folder] and tree[folder][name]
        if type(value) ~= "table" then return value end
        local copy = {}
        for index, step in ipairs(value) do
            local meta = step._xt_meta and { character = step._xt_meta.character, title = step._xt_meta.title } or nil
            copy[index] = { _xt_meta = meta, id = step.id }
        end
        return copy
    end,
    dump = function(path, value)
        local folder, name = path:match("^TrainingComboTrials_data/CustomCombos/([^/]+)/([^/]+)$")
        assert(folder and name, path)
        tree[folder] = tree[folder] or {}
        tree[folder][name] = value
        dumps[#dumps + 1] = path
        return true
    end,
    create_dir = function() end,
    fallback_key = function(character)
        if character == "Arjun" then return "ESF_034" end
        return nil
    end,
}

local migrate = Migration.new(deps)
assert(migrate("Arjun") == 2, "two ESF_034 combos and the community file, minus the existing SA3")
assert(tree.Arjun["Arjun_COMBO_2MK_D1.json"][1]._xt_meta.character == "Arjun",
    "the fallback key in _xt_meta.character becomes the roster key")
assert(tree.Arjun["Arjun_COMBO_SA3.json"][1]._xt_meta.title == "kept", "existing files are never overwritten")
assert(tree.Arjun["community.json"][1]._xt_meta.title == "c" and tree.Arjun["community.json"][1]._xt_meta.character == nil)
assert(tree.Arjun["broken.json"] == nil, "files that are not combo sequences are skipped")
assert(tree.ESF_034["ESF_034_COMBO_2MK_D1.json"][1]._xt_meta.character == "ESF_034", "originals stay unchanged")
assert(#dumps == 2)

local before = globs
assert(migrate("Arjun") == 0 and globs == before, "once per session")
assert(migrate("Ryu") == 0 and globs == before, "fighters without a fallback folder mapping do nothing")
assert(migrate("ESF_034") == 0, "an unknown fighter has no roster key to migrate into")
assert(migrate("Unknown") == 0 and migrate("") == 0 and migrate(nil) == 0)

-- ComboTrials_Files wires the migration to the roster: a known fighter maps to
-- its ESF_<id> fallback key.
local FighterRoster = require("func/FighterRoster")
FighterRoster.use_document({
    schema = "sf6cc.fighter_roster.v1",
    fighters = { { id = 34, key = "Arjun", name_en = "Arjun", name_zh = "阿尔琼", official_slug = "arjun" } },
})
local fighter = FighterRoster.fighter_by_key("Arjun")
assert(fighter and FighterRoster.fallback_key(fighter.id) == "ESF_034")
FighterRoster.reload()

print("fallback combo migration tests passed")
