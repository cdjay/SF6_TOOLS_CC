package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local function field(value)
    return {
        get_data = function() return value end,
        is_static = function() return true end,
        get_name = function() return tostring(value) end,
    }
end

local enum_fields = {
    {
        is_static = function() return true end,
        get_data = function() return 123 end,
        get_name = function() return "ACT_TEST" end,
    },
}

sdk = {
    find_type_definition = function(name)
        if name == "nBattle.ACT_ID" then
            return { get_fields = function() return enum_fields end }
        end
        return nil
    end,
    to_managed_object = function(value) return value end,
}

local attacker = { focus_new = 8500, act_st = 27 }
local victim = { vital_new = 7600 }
package.loaded["func/GameState"] = { p1 = attacker, p2 = victim }

local command_source = {
    get_field = function(_, name)
        if name == "ok_key_flags" then return 16 end
    end,
}
local triggers = {}
for i = 1, 10 do
    triggers[i] = {
        action_id = 500,
        get_field = function(_, name)
            if name == "norm_NG" then return false end
            if name == "norm" then return command_source end
        end,
    }
end
local trigger_array = { get_elements = function() return triggers end }
local user_engine = {
    call = function(_, method)
        if method == "GetTrigger()" then return trigger_array end
    end,
}
local command = {
    call = function(_, method)
        if method == "get_mUserEngine" then return { [0] = user_engine } end
    end,
}
local battle_team = { mcTeam = { [0] = { mSuperGauge = 30000 } } }
local g_battle_type = {
    get_field = function(_, name)
        if name == "Command" then return field(command) end
        if name == "Team" then return field(battle_team) end
    end,
}

local players = {
    [0] = { trigger_mask_cache = {}, trigger_cache_built = false },
}
local GameProbe = require("func/ComboTrials/GameProbe")
GameProbe.init({ g_battle_type = g_battle_type, players = players })

assert(GameProbe.act_id_reverse_enum[123] == "ACT_TEST",
    "ACT_ID reflection must preserve the reverse enum")
assert(GameProbe.decode_button_mask(16 | 64 | 512) == "LP+HP+HK",
    "button masks must retain their existing display order")
assert(GameProbe.build_bcm_trigger_cache(0) == true
        and players[0].trigger_mask_cache[500] == 16
        and players[0].trigger_cache_built == true,
    "BCM trigger facts must retain their incremental cache result")

local action_frame = { call = function(_, method) if method == "ToString()" then return "7" end end }
local state_flags_field = { get_data = function() return 9 end }
local action_field = { get_data = function() return 456 end }
local branch_type_field = { get_data = function() return 3 end }
local m_param = {
    get_type_definition = function()
        return { get_field = function(_, name) if name == "state_flags" then return state_flags_field end end }
    end,
}
local engine = {
    call = function(_, method)
        if method == "get_ActionID" then return 123 end
        if method == "get_ActionFrame" then return action_frame end
    end,
    get_field = function(_, name)
        if name == "mParam" then return m_param end
    end,
}
local action_part = { get_field = function(_, name) if name == "_Engine" then return engine end end }
local key_input = {
    get_type_definition = function()
        return { get_field = function(_, name) if name == "Action" then return action_field end end }
    end,
}
local branch = {
    get_type_definition = function()
        return { get_field = function(_, name) if name == "BranchType" then return branch_type_field end end }
    end,
}
local act_param = {
    get_field = function(_, name)
        if name == "ActionPart" then return action_part end
        if name == "Branch" then return branch end
    end,
    get_type_definition = function()
        return {
            get_field = function(_, name)
                if name == "KeyInput" then return { get_data = function() return key_input end } end
            end,
        }
    end,
}
local player_type = {
    get_field = function(_, name)
        if name == "pl_input_new" then return { get_data = function() return 4 end } end
        if name == "pl_sw_new" then return { get_data = function() return 16 end } end
        if name == "combo_cnt" then return { get_data = function() return 6 end } end
        if name == "hit_stop" then return { get_data = function() return 0 end } end
    end,
}
function attacker:get_type_definition() return player_type end
function attacker:get_field(name)
    if name == "rl_dir" then return true end
    if name == "mpActParam" then return act_param end
end

local act_id, frame_no, flags, action_code, direct_input, branch_type,
    direction_input, facing_right = GameProbe.get_action_data(attacker)
assert(act_id == 123 and frame_no == 7 and flags == 9 and action_code == 456,
    "Action runtime fields must retain their return order and values")
assert(direct_input == (4 | 16) and branch_type == 3
        and direction_input == 4 and facing_right == true,
    "input and facing facts must remain unchanged")
local runtime_action_id, runtime_action_frame = GameProbe.get_runtime_action_data(attacker)
assert(runtime_action_id == 123 and runtime_action_frame == 7,
    "Action-only runtime facts must not depend on input field reads")
local reused_action_id, reused_action_frame =
    GameProbe.get_action_data(attacker, runtime_action_id, runtime_action_frame)
assert(reused_action_id == 123 and reused_action_frame == 7,
    "mixed probe must reuse pre-read Action facts")

local action_only_attacker = {}
function action_only_attacker:get_field(name)
    if name == "mpActParam" then return act_param end
end
function action_only_attacker:get_type_definition()
    return { get_field = function() return nil end }
end
local isolated_action_id, isolated_action_frame =
    GameProbe.get_runtime_action_data(action_only_attacker)
assert(isolated_action_id == 123 and isolated_action_frame == 7,
    "Action-only runtime probe must survive unavailable input fields")
local mixed_action_id, mixed_action_frame = GameProbe.get_action_data(action_only_attacker)
assert(mixed_action_id == 123 and mixed_action_frame == 7,
    "mixed probe must retain Action facts when optional input reads fail")
assert(GameProbe.get_combo_count(attacker) == 6,
    "combo count must remain a safe factual read")
assert(GameProbe.get_damage_type_safe(attacker) == 1,
    "damage type must retain the existing action-state classification")
assert(GameProbe.check_is_projectile(0, attacker, g_battle_type) == true,
    "projectile observation must retain the hit-stop rule")

local gauges = GameProbe.capture_recording_gauges(0)
assert(gauges.victim_hp == 7600 and gauges.attacker_drive == 8500
        and gauges.attacker_super == 30000,
    "recording gauges must retain the existing runtime snapshot")

print("combo game probe tests passed")
