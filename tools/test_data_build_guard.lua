package.path = "autorun/?.lua;autorun/?/init.lua;" .. package.path

local Guard = require("func/ComboTrials/DataBuildGuard")

-- FNV-1a reference vectors and the vector shared with
-- tools/action_runtime_compiler/bcm_fingerprint.js.
assert(Guard.fnv1a32("") == "811c9dc5")
assert(Guard.fnv1a32("a") == "e40c292c")
local shared = Guard.fingerprint({ 18, 17, 0, -1, "600", 17 })
assert(shared.algorithm == "bcm-trigger-action-multiset.fnv1a32.v1")
assert(shared.count == 4 and shared.hash == "8eb684e6", shared.count .. ":" .. shared.hash)
local reordered = Guard.fingerprint({ 600, 17, 17, 18 })
assert(reordered.count == shared.count and reordered.hash == shared.hash, "order must not matter")

local live = Guard.fingerprint({ 17, 18, 600 })
local expected = { algorithm = Guard.ALGORITHM, count = live.count, hash = live.hash }
assert(Guard.evaluate(expected, "loaded", nil) == "pending")
assert(Guard.evaluate(expected, "loaded", live) == "match")
assert(Guard.evaluate({ algorithm = Guard.ALGORITHM, count = 3, hash = "00000000" }, "loaded", live) == "mismatch")
assert(Guard.evaluate(nil, "loaded", live) == "unverified", "tables without a fingerprint are not blocked")
assert(Guard.evaluate(nil, "map_load_failed", live) == "missing_table")
assert(Guard.evaluate(nil, "invalid_schema_or_policy", live) == "invalid_table")

local reports = {}
local report = Guard.new_reporter(function(message, status, character)
    reports[#reports + 1] = { message = message, status = status, character = character }
end)
assert(report("ESF_034", "missing_table"):find("ESF_034", 1, true))
assert(report("ESF_034", "missing_table") == nil, "one warning per fighter and status")
assert(report("Ryu", "match") == nil and report("Ryu", "unverified") == nil)
assert(report("Ryu", "mismatch"):find("数据版本不一致", 1, true))
assert(#reports == 2 and reports[2].character == "Ryu")

-- Recordings carry the fingerprint they were made with.
local stamped = Guard.stamp(live)
assert(stamped ~= live and stamped.count == live.count and stamped.hash == live.hash)
assert(Guard.stamp(nil) == nil and Guard.stamp({ algorithm = "other" }) == nil)
assert(Guard.compare_recording(stamped, nil) == "pending")
assert(Guard.compare_recording(stamped, live) == "match")
assert(Guard.compare_recording(nil, live) == "unverified", "older recordings are not flagged")
assert(Guard.compare_recording({ algorithm = Guard.ALGORITHM, count = live.count, hash = "00000000" }, live)
    == "mismatch")
assert(report("Ryu", "recording_mismatch", "CustomCombos/Ryu/a.json"):find("游戏数据已变化", 1, true))
assert(report("Ryu", "recording_mismatch", "CustomCombos/Ryu/a.json") == nil, "one warning per file")
assert(report("Ryu", "recording_mismatch", "CustomCombos/Ryu/b.json") ~= nil)
assert(#reports == 4 and reports[4].status == "recording_mismatch")

-- GameProbe computes the live fingerprint while building its trigger cache,
-- including triggers after an empty slot that ends the length operator early.
local function trigger(action_id)
    return setmetatable({ action_id = action_id }, { __index = {
        get_field = function(_, name)
            if name == "norm" then return { get_field = function() return 16 end } end
            return nil
        end,
    } })
end
local elements = {}
for index = 1, 12 do elements[index] = trigger(600 + index) end
elements[13] = nil
elements[14] = trigger(900)
local trigger_array = { get_elements = function() return elements end }
function trigger_array:call(name) assert(name == "GetTrigger()"); return self end
local engines = { [0] = trigger_array }
local command = { call = function(_, name) assert(name == "get_mUserEngine"); return engines end }
local g_battle = { get_field = function(_, name)
    assert(name == "Command")
    return { get_data = function() return command end }
end }

package.loaded["func/GameState"] = package.loaded["func/GameState"] or {}
local previous_sdk = sdk
sdk = { find_type_definition = function() return nil end }
local GameProbe = require("func/ComboTrials/GameProbe")
local players = { [0] = {} }
GameProbe.init({ g_battle_type = g_battle, players = players })
assert(GameProbe.build_bcm_trigger_cache(0) == true)
local ids = { 900 }
for index = 1, 12 do ids[#ids + 1] = 600 + index end
local want = Guard.fingerprint(ids)
assert(players[0].bcm_fingerprint and players[0].bcm_fingerprint.count == want.count
    and players[0].bcm_fingerprint.hash == want.hash, "live fingerprint must cover every trigger")
assert(players[0].trigger_cache_built == true and players[0].trigger_mask_cache[601] == 16)
sdk = previous_sdk

-- Shipped tables carry the generator fingerprint.
local Json = require("tools/training_record_bank/vendor/dkjson")
local file = assert(io.open("data/TrainingComboTrials_data/command_display/Ryu.json", "rb"))
local ryu = assert(Json.decode(file:read("*a")))
file:close()
local meta = ryu._meta.bcm_trigger_fingerprint
assert(meta and meta.algorithm == Guard.ALGORITHM and meta.count > 0 and #meta.hash == 8)

print("data build guard tests passed")
