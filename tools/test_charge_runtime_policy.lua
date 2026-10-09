package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

-- Hold judgement comes from data: the shipped exception files carry each
-- fighter's "_charge_policy", read through CharacterRules.
local Json = require("tools/training_record_bank/vendor/dkjson")
json = {
    load_file = function(path)
        local file = io.open("data/" .. path, "rb")
        if not file then return nil end
        local text = file:read("*a")
        file:close()
        return Json.decode(text)
    end,
}

package.loaded["func/ComboTrials/CharacterRules"] = nil
package.loaded["func/ComboTrials/ChargeRuntimePolicy"] = nil
local CharacterRules = require("func/ComboTrials/CharacterRules")
local Policy = require("func/ComboTrials/ChargeRuntimePolicy")

-- Without a registered policy every fighter uses Instant / Partial / Maxed.
assert(Policy.evaluate_status("Lily", 6, 2, 6) == "Maxed")
assert(Policy.should_track_physical_hold("Lily") == false)

for _, name in ipairs({ "Ingrid", "JP", "Lily", "Luke", "Ryu" }) do
    local rules = CharacterRules.load_for_character(name)
    assert(rules._charge_policy == nil, "the policy is not an Action rule: " .. name)
    assert(Policy.register(name, CharacterRules.charge_policy(rules)), name)
end

assert(Policy.is_charge_stock_action("Ingrid", 969) == true)
assert(Policy.is_charge_stock_action("Ingrid", "969") == true)
assert(Policy.is_charge_stock_action("Ingrid", 970) == false)
assert(Policy.is_charge_stock_action("Ryu", 969) == false)
assert(Policy.should_track_physical_hold("Lily") == true)
assert(Policy.should_track_physical_hold("JP") == false)
assert(Policy.should_autodetect_charge_max("JP") == true)
assert(Policy.should_autodetect_charge_max("Lily") == true)
assert(Policy.should_autodetect_charge_max("Luke") == false)
assert(Policy.uses_perfect_window("Luke") == true and Policy.uses_perfect_window("JP") == false)
assert(Policy.level_labels("Lily")[3] == "Lv3" and Policy.level_labels("Ryu") == nil)

assert(Policy.evaluate_status("Luke", 2, 2, nil, 5, 7) == "Instant")
assert(Policy.evaluate_status("Luke", 6, 2, nil, 5, 7) == "PERFECT!")
assert(Policy.evaluate_status("Luke", 4, 2, nil, 5, 7) == "Partial")
assert(Policy.evaluate_status("Luke", 8, 2, nil, 5, 7) == "LATE")
assert(Policy.evaluate_status("Luke", 4, 2, 6, nil, nil) == "Partial")
assert(Policy.evaluate_status("JP", 2, 2, 6) == "Instant")
assert(Policy.evaluate_status("JP", 6, 2, 6) == "FAKE")
assert(Policy.evaluate_status("JP", 4, 2, 6) == "Partial")
assert(Policy.evaluate_status("JP", 0, nil, nil) == "Partial")
assert(Policy.evaluate_status("Lily", 2, 2, 6) == "Lv1")
assert(Policy.evaluate_status("Lily", 6, 2, 6) == "Lv3")
assert(Policy.evaluate_status("Lily", 4, 2, 6) == "Lv2")
assert(Policy.evaluate_status("Ryu", 0, 2, 6) == "Instant")
assert(Policy.evaluate_status("Ryu", 2, 2, 6) == "Instant")
assert(Policy.evaluate_status("Ryu", 4, 2, 6) == "Partial")
assert(Policy.evaluate_status("Ryu", 6, 2, 6) == "Maxed")
assert(Policy.evaluate_status("Ryu", 0, nil, nil) == "Instant")

-- The in-game editor keeps the section when it saves the fighter's file.
local saved = CharacterRules.serialize_for_save(CharacterRules.load_for_character("JP"))
assert(saved._charge_policy and saved._charge_policy.evaluation == "levels")

-- A new fighter needs data only.
assert(Policy.register("Arjun", { evaluation = "perfect_window", charge_stock_actions = { 950 } }))
assert(Policy.evaluate_status("Arjun", 6, 2, nil, 5, 7) == "PERFECT!")
assert(Policy.is_charge_stock_action("Arjun", 950))

-- Invalid documents fall back to the default and report why.
local ok, reason = Policy.register("Arjun", { evaluation = "levels", labels = { "a" } })
assert(ok == false and reason:find("three labels", 1, true))
assert(Policy.evaluate_status("Arjun", 6, 2, 6) == "Maxed")
assert(Policy.register("Arjun", { evaluation = "nope" }) == false)
assert(Policy.register("Arjun", { charge_stock_actions = { "x" } }) == false)
assert(Policy.register("Arjun", "levels") == false)

-- Registering nil (a fighter without a section) restores the default.
assert(Policy.register("Lily", nil))
assert(Policy.evaluate_status("Lily", 6, 2, 6) == "Maxed")

print("Charge runtime policy tests passed")
