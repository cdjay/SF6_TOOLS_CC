package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local json_loads = {}
json = {
    load_file = function(path)
        json_loads[path] = (json_loads[path] or 0) + 1
        if path == "TrainingComboTrials_data/exceptions/Jamie.json" then
            return { ["981"] = { force = true } }
        end
        if path == "TrainingComboTrials_data/generated_semantics/Jamie.json" then
            return { ["989"] = { absorb_ids = "990,991,992" } }
        end
        return nil
    end,
}

package.loaded["func/ComboTrials/CharacterRules"] = nil
local CharacterRules = require("func/ComboTrials/CharacterRules")
local first_rules = CharacterRules.load_for_character_cached("Jamie")
local second_rules = CharacterRules.load_for_character_cached("Jamie")
assert(first_rules == second_rules,
    "cached character rules must reuse one immutable session result")
assert(json_loads["TrainingComboTrials_data/exceptions/Jamie.json"] == 1
        and json_loads["TrainingComboTrials_data/generated_semantics/Jamie.json"] == 1,
    "character product JSON must load only once per Lua session")

local compatibility_loads = 0
package.loaded["func/ComboTrials/ActionCompatibility"] = nil
local ActionCompatibility = require("func/ComboTrials/ActionCompatibility")
local function missing_compatibility_loader()
    compatibility_loads = compatibility_loads + 1
    return nil
end
local first_compatibility, first_count, first_status =
    ActionCompatibility.load_cached("Jamie", "1.21.0", missing_compatibility_loader)
local second_compatibility, second_count, second_status =
    ActionCompatibility.load_cached("Jamie", "1.21.0", missing_compatibility_loader)
assert(first_compatibility == nil and second_compatibility == nil
        and first_count == 0 and second_count == 0
        and first_status == "compatibility_not_found"
        and second_status == first_status,
    "missing compatibility data must preserve the original fail-closed result")
assert(compatibility_loads == 1,
    "missing compatibility JSON must be negatively cached for the session")

local relation_loads = 0
package.loaded["func/ComboTrials/GeneratedActionRelations"] = nil
local GeneratedActionRelations = require("func/ComboTrials/GeneratedActionRelations")
local function missing_relation_loader()
    relation_loads = relation_loads + 1
    return nil
end
local first_relations, first_relation_count, first_relation_status =
    GeneratedActionRelations.load_cached("Jamie", missing_relation_loader)
local second_relations, second_relation_count, second_relation_status =
    GeneratedActionRelations.load_cached("Jamie", missing_relation_loader)
assert(first_relations == nil and second_relations == nil
        and first_relation_count == 0 and second_relation_count == 0
        and first_relation_status == "generated_action_relations_not_found"
        and second_relation_status == first_relation_status,
    "missing generated relations must preserve the original fail-closed result")
assert(relation_loads == 1,
    "missing generated relation data must be negatively cached for the session")

print("static semantic cache tests passed")
