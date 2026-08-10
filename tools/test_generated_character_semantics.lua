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

print("generated character semantics tests passed")
