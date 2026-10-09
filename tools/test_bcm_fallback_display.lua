package.path = "autorun/?.lua;autorun/?/init.lua;" .. package.path

-- A fighter without a usable command table (a new fighter before its data
-- ships) shows classic notation decoded from the live BCM triggers.

-- 1. The renderer reports a missing table file as map_load_failed, which the
--    data guard turns into missing_table (the fallback's trigger), and a file
--    that fails validation as invalid_schema_or_policy.
json = {
    load_file = function(path)
        if path:find("Broken.json", 1, true) then return { _meta = { schema = "other" } } end
        return nil
    end,
}
_G.safe_load_json = function(path) return json.load_file(path) end
re = re or {}
imgui = imgui or setmetatable({}, { __index = function() return function() return nil end end })
log = log or { warn = function() end, error = function() end, info = function() end }
sdk = sdk or {}
package.loaded["func/ComboTrials_ImGui"] = nil
local renderer = require("func/ComboTrials_ImGui")
local Guard = require("func/ComboTrials/DataBuildGuard")
local live = Guard.fingerprint({ 600 })
local _, missing_status = renderer.get_command_display_fingerprint("ESF_034")
assert(missing_status == "map_load_failed", tostring(missing_status))
assert(Guard.evaluate(nil, missing_status, live) == "missing_table")
local _, broken_status = renderer.get_command_display_fingerprint("Broken")
assert(broken_status == "invalid_schema_or_policy", tostring(broken_status))
assert(Guard.evaluate(nil, broken_status, live) == "invalid_table")

-- 2. GameProbe decodes the first trigger with a classic input per Action and
--    caches the answer, including "no classic input".
local function managed(fields)
    return setmetatable({}, { __index = function(self, key)
        if key == "get_field" then return function(_, name) return fields[name] end end
        return fields[key]
    end })
end
local function array(items)
    return { get_elements = function() return items end }
end
local function input(direction_mask)
    return managed({ type = 0, normal = managed({ ok_key_flags = direction_mask }),
        charge = managed({ id = 0, is_release = false }) })
end
local quarter_circle = managed({ inputs = array({ input(2), input(10), input(8) }), input_num = 3, charge_bit = 0 })
local function trigger(action_id, fields)
    fields.action_id = action_id
    fields.cond_owner_state_flags = fields.cond_owner_state_flags or 0
    fields.category_flags = fields.category_flags or 0
    return managed(fields)
end
local triggers = {
    trigger(900, { norm_NG = true, use_sprt = false }),
    trigger(900, { norm_NG = false, norm = managed({ command_ptr = array({ quarter_circle }),
        ok_key_flags = 16, ok_key_cond_flags = 0, dc_exc_flags = 0 }) }),
    trigger(901, { norm_NG = true, use_sprt = false }),
}
triggers[5] = trigger(902, { norm_NG = false, norm = managed({ command_ptr = array({}),
    ok_key_flags = 64, ok_key_cond_flags = 0, dc_exc_flags = 0 }) })
local scans = 0
local engine = { call = function(_, name)
    assert(name == "GetTrigger()")
    scans = scans + 1
    return array(triggers)
end }
local command = { call = function(_, name) assert(name == "get_mUserEngine"); return { [0] = engine } end }
local g_battle = { get_field = function(_, name)
    assert(name == "Command")
    return { get_data = function() return command end }
end }
package.loaded["func/GameState"] = package.loaded["func/GameState"] or {}
local previous_sdk = sdk
sdk = { find_type_definition = function() return nil end }
package.loaded["func/ComboTrials/GameProbe"] = nil
local GameProbe = require("func/ComboTrials/GameProbe")
local players = { [0] = {} }
GameProbe.init({ g_battle_type = g_battle, players = players })

assert(GameProbe.bcm_classic_display(0, 900) == "236+LP", "first trigger with a classic input wins")
assert(GameProbe.bcm_classic_display(0, 900) == "236+LP" and scans == 1, "decoded once per Action")
assert(GameProbe.bcm_classic_display(0, 901) == nil and scans == 2)
assert(GameProbe.bcm_classic_display(0, 901) == nil and scans == 2, "no classic input is cached too")
assert(GameProbe.bcm_classic_display(0, 902) == "HP", "triggers after an empty slot are still searched")
assert(GameProbe.bcm_classic_display(0, 0) == nil and GameProbe.bcm_classic_display(1, 900) == nil)
players[0].bcm_classic_display_cache = nil
assert(GameProbe.bcm_classic_display(0, 900) == "236+LP" and scans == 4, "a BCM change clears the cache")
sdk = previous_sdk

-- 3. The main entry consults the fallback only for missing or invalid tables.
local entry = io.open("autorun/TrainingComboTrials_v1.0.lua", "rb")
local source = entry:read("*a")
entry:close()
assert(source:find('if status ~= "missing_table" and status ~= "invalid_table" then return nil end', 1, true))
assert(source:find("or ctx.bcm_fallback_motion(p_idx, p_state, act_id)", 1, true))

print("BCM fallback display tests passed")
