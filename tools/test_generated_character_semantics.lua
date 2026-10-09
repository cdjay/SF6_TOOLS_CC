package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local legacy_981 = {
    absorb_ids = "982,983,984",
}
local legacy_989 = {
    absorb_ids = "990,991,992",
}

local handwritten = {
    ["982"] = { force = true, action_alias_ids = "983" },
    ["983"] = { force = true, action_alias_ids = "982" },
    ["984"] = { force = true, action_alias_ids = "981,983" },
    ["990"] = { force = true },
    ["991"] = { force = true },
    ["992"] = { force = true },
}
local generated = {
    ["981"] = { absorb_ids = "982,983,984" },
    ["989"] = { absorb_ids = "990,991,992" },
}

json = {
    load_file = function(path)
        if path == "TrainingComboTrials_data/exceptions/Jamie.json" then
            return handwritten
        end
        if path == "TrainingComboTrials_data/generated_semantics/Jamie.json" then
            return generated
        end
        return nil
    end,
}

package.loaded["func/ComboTrials/CharacterRules"] = nil
local CharacterRules = require("func/ComboTrials/CharacterRules")
local rules = CharacterRules.load_for_character("Jamie")

assert(rules["981"] ~= nil
        and rules["981"].absorb_ids == legacy_981.absorb_ids,
    "generated Jamie 981 must reproduce the removed Legacy absorb relation")
assert(rules["982"] == handwritten["982"]
        and rules["983"] == handwritten["983"]
        and rules["984"] == handwritten["984"]
        and rules["990"] == handwritten["990"]
        and rules["991"] == handwritten["991"]
        and rules["992"] == handwritten["992"],
    "loading generated semantics must preserve unrelated handwritten rules")

local exception = CharacterRules.get_exception(rules, {}, 981)
assert(exception.absorb_ids == legacy_981.absorb_ids,
    "ActionMatcher-facing lookup must remain Legacy-equivalent")
local exception_989 = CharacterRules.get_exception(rules, {}, 989)
assert(exception_989.absorb_ids == legacy_989.absorb_ids,
    "generated Jamie 989 must preserve the Legacy ActionMatcher result")

local projection = CharacterRules.build_action_event_projection_rules(rules, {})
assert(next(projection) == nil,
    "generated absorb_ids must not invent ActionEventCompiler projection behavior")

local source = assert(io.open(
    "data/TrainingComboTrials_data/exceptions/Jamie.json",
    "rb"
)):read("*a")
assert(not source:find('"981"%s*:%s*{%s*"absorb_ids"'),
    "the Jamie 981 hand-written semantic exception must be absent")
assert(not source:find('"989"%s*:%s*{%s*"absorb_ids"'),
    "the Jamie 989 hand-written semantic exception must be absent")

local generated_source = assert(io.open(
    "data/TrainingComboTrials_data/generated_semantics/Jamie.json",
    "rb"
)):read("*a")
assert(generated_source:find('"981"', 1, true)
        and generated_source:find('"absorb_ids": "982,983,984"', 1, true)
        and generated_source:find('"989"', 1, true)
        and generated_source:find('"absorb_ids": "990,991,992"', 1, true),
    "the generated artifact must contain both equivalent Jamie rules")

-- Generated v2 documents carry _meta; curation may withhold generated rules.
-- Neither key is a runtime rule, and saving from the in-game editor writes
-- back only the curated layer.
local curated_test = {
    ["10"] = { force = true },
    _character = { allow_pending_absorb = true },
    _generated_semantics = { withhold = { { action = 22, reason = "test" } } },
}
local generated_test = {
    ["20"] = { absorb_ids = "21" },
    ["21"] = { force = true },
    _meta = { schema = "sf6cc.generated-character-semantics.v2" },
}
json = {
    load_file = function(path)
        if path == "TrainingComboTrials_data/exceptions/Test.json" then return curated_test end
        if path == "TrainingComboTrials_data/generated_semantics/Test.json" then return generated_test end
        return nil
    end,
}
-- CharacterRules captures the json global when it is loaded.
package.loaded["func/ComboTrials/CharacterRules"] = nil
CharacterRules = require("func/ComboTrials/CharacterRules")
local test_rules = CharacterRules.load_for_character("Test")
assert(test_rules._meta == nil and test_rules._generated_semantics == nil,
    "generated metadata and generator curation are not runtime rules")
assert(test_rules["20"].absorb_ids == "21" and test_rules["21"].force == true
    and test_rules["10"].force == true and test_rules._character.allow_pending_absorb == true)

test_rules["10"] = { force = true, ignore_prev_id = 5 }
test_rules["30"] = { ignore = true }
local saved = CharacterRules.serialize_for_save(test_rules)
assert(saved["20"] == nil and saved["21"] == nil,
    "unchanged generated rules must not be written into the curated file")
assert(saved["10"].ignore_prev_id == 5 and saved["30"].ignore == true)
assert(saved._generated_semantics == curated_test._generated_semantics
    and saved._character == curated_test._character,
    "saving keeps curation-only keys")
test_rules["21"] = { force = true, is_holdable = true }
assert(CharacterRules.serialize_for_save(test_rules)["21"].is_holdable == true,
    "an edited generated rule becomes curated")
local plain = { ["5"] = { ignore = true } }
assert(CharacterRules.serialize_for_save(plain)["5"].ignore == true)

print("generated character semantics tests passed")
