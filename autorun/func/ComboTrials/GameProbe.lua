local GS = require("func/GameState")

local GameProbe = {
    name = "ComboTrials.GameProbe",
    act_id_reverse_enum = {},
}

local g_battle_type = nil
local players = nil

local function rebuild_act_id_reverse_enum()
    GameProbe.act_id_reverse_enum = {}
    do
        local td = sdk.find_type_definition("nBattle.ACT_ID")
        if td then
            for _, field in ipairs(td:get_fields()) do
                if field:is_static() and field:get_data() ~= nil then
                    GameProbe.act_id_reverse_enum[field:get_data()] = field:get_name()
                end
            end
        end
    end
end

function GameProbe.init(deps)
    deps = deps or {}
    g_battle_type = deps.g_battle_type
    players = deps.players
    rebuild_act_id_reverse_enum()
end

function GameProbe.decode_button_mask(mask)
    local parts = {}
    if (mask & 16) ~= 0 then table.insert(parts, "LP") end
    if (mask & 32) ~= 0 then table.insert(parts, "MP") end
    if (mask & 64) ~= 0 then table.insert(parts, "HP") end
    if (mask & 128) ~= 0 then table.insert(parts, "LK") end
    if (mask & 256) ~= 0 then table.insert(parts, "MK") end
    if (mask & 512) ~= 0 then table.insert(parts, "HK") end
    return table.concat(parts, "+")
end

function GameProbe.build_bcm_trigger_cache(player_idx)
    local gBattle = g_battle_type
    if not gBattle then return false end
    local cmd_obj = gBattle:get_field("Command"):get_data(nil)
    if not cmd_obj then return false end

    local player = players[player_idx]
    local build = player._trigger_cache_build
    if not build then
        local ok, trigs = pcall(function()
            return cmd_obj:call("get_mUserEngine")[player_idx]:call("GetTrigger()"):get_elements()
        end)
        if not ok or type(trigs) ~= "table" then return false end
        build = {
            triggers = trigs,
            index = 1,
            mask_cache = {},
            trigger_count = 0,
        }
        player._trigger_cache_build = build
    end

    -- Managed trigger inspection is expensive. Process a bounded slice per
    -- frame so entering Combo Trials never stalls on a full character scan.
    local slice_end = math.min(#build.triggers, build.index + 63)
    while build.index <= slice_end do
        local t = build.triggers[build.index]
        pcall(function()
            if t then
                local aid = t.action_id
                if aid > 0 then
                    local norm_ng = false
                    pcall(function() norm_ng = t:get_field("norm_NG") == true end)

                    local cmd_src = nil
                    if not norm_ng then
                        pcall(function() cmd_src = t:get_field("norm") end)
                    else
                        local use_sprt, sprt_ng = false, true
                        pcall(function() use_sprt = t:get_field("use_sprt") == true end)
                        pcall(function() sprt_ng = t:get_field("sprt_NG") == true end)
                        if use_sprt and not sprt_ng then pcall(function() cmd_src = t:get_field("sprt") end) end
                    end

                    if cmd_src then
                        local ok_key = cmd_src:get_field("ok_key_flags") or 0
                        build.mask_cache[aid] = (build.mask_cache[aid] or 0) | ok_key
                        build.trigger_count = build.trigger_count + 1
                    end
                end
            end
        end)
        build.index = build.index + 1
    end

    if build.index <= #build.triggers then return false end
    player._trigger_cache_build = nil
    if build.trigger_count < 10 then return false end
    player.trigger_mask_cache = build.mask_cache
    player.trigger_cache_built = true
    return true
end

local skip_fields = {
    ["Owner"] = true,
    ["OwnerAdrs"] = true,
    ["mpOwner"] = true,
    ["ActionPart"] = true,
    ["_Engine"] = true,
    ["_EngineAdrs"] = true,
    ["pPlayer"] = true,
    ["Battle"] = true,
    ["Collision"] = true,
    ["Place"] = true,
    ["PartsParam"] = true,
    ["VFXSpawnID"] = true
}

function GameProbe.dump_object(obj, depth, max_depth, visited)
    if not obj then return "null" end
    if type(obj) ~= "userdata" then return tostring(obj) end
    if depth > max_depth then return "<Max Depth Reached>" end

    pcall(function() obj = sdk.to_managed_object(obj) or obj end)

    local ptr_str = tostring(obj)
    if visited[ptr_str] then return "<Already explored>" end
    visited[ptr_str] = true

    local tdef = obj:get_type_definition()
    if not tdef then return tostring(obj) end

    local tname = tdef:get_name()
    if tname == "sfix" or tname == "Sfix" then
        local val = "unknown"
        pcall(function() val = tostring(tdef:get_field("v"):get_data(obj)) end)
        return "sfix(" .. val .. ")"
    end

    local data = {}
    data["_type"] = tname

    local is_array = false
    pcall(function() if obj.get_elements then is_array = true end end)

    if is_array then
        local s, elements = pcall(function() return obj:get_elements() end)
        if s and elements then
            local arr = {}
            for i = 1, math.min(#elements, 25) do
                if elements[i] ~= nil then
                    table.insert(arr, GameProbe.dump_object(elements[i], depth + 1, max_depth, visited))
                end
            end
            if #elements > 25 then table.insert(arr, "<... and " .. tostring(#elements - 25) .. " more>") end
            data["_elements"] = arr
            return data
        end
    end

    while tdef do
        for _, f in ipairs(tdef:get_fields()) do
            local fname = f:get_name()
            if not skip_fields[fname] and not data[fname] then
                local s, v = pcall(function() return f:get_data(obj) end)
                if s and v ~= nil then
                    data[fname] = GameProbe.dump_object(v, depth + 1, max_depth, visited)
                end
            end
        end
        tdef = tdef:get_parent_type()
    end

    return data
end

function GameProbe.capture_deep_action_data(p_char)
    local dump = {}
    pcall(function()
        local visited = {}
        local act_param = p_char:get_field("mpActParam")
        if act_param then
            local branch = act_param:get_field("Branch")
            if branch then dump.ActParam_Branch = GameProbe.dump_object(branch, 0, 5, visited) end

            local trigger = act_param:get_field("Trigger")
            if trigger then dump.ActParam_Trigger = GameProbe.dump_object(trigger, 0, 5, visited) end

            local action_part = act_param:get_field("ActionPart")
            if action_part then
                local engine = action_part:get_field("_Engine")
                if engine then
                    local mParam = engine:get_field("mParam")
                    if mParam then
                        local action_obj = mParam:get_field("action")
                        if action_obj then
                            local keys = action_obj:get_field("Keys")
                            if keys then dump.Engine_Keys = GameProbe.dump_object(keys, 0, 5, visited) end
                        end
                    end
                end
            end
        end
    end)
    return dump
end

function GameProbe.get_elements_safe(obj)
    if not obj then return nil end
    local s, arr = pcall(function() return obj:get_elements() end)
    if s and arr then return arr end
    pcall(function()
        local items = obj:get_field("_items")
        if items then arr = items:get_elements() end
    end)
    return arr
end

-- Hoisted hot-path helper (no per-call closure). Scratch table preserves
-- partial-write semantics if an SDK call errors mid-body.
local _ct_action_scratch = {
    act_id = -1, frame = 0, state_flags = -1, action_code = 0,
    direct_input = 0, direction_input = 0, branch_type = 0, facing_right = true
}

local function _ct_read_runtime_action_data(p_obj)
    local act_param = p_obj and p_obj:get_field("mpActParam") or nil
    local action_part = act_param and act_param:get_field("ActionPart") or nil
    local engine = action_part and action_part:get_field("_Engine") or nil
    if not engine then return -1, 0 end

    local action_id = tonumber(engine:call("get_ActionID")) or -1
    local action_frame = 0
    local sf = engine:call("get_ActionFrame")
    if sf then
        local value = tonumber(sf:call("ToString()"))
        if value ~= nil and value == value
            and value ~= math.huge and value ~= -math.huge then
            action_frame = math.floor(value)
        end
    end
    return action_id, action_frame
end

local function _ct_read_action_data(p_obj, runtime_action_id, runtime_action_frame)
    local r = _ct_action_scratch
    if runtime_action_id == nil or runtime_action_frame == nil then
        r.act_id, r.frame = _ct_read_runtime_action_data(p_obj)
    else
        r.act_id = tonumber(runtime_action_id) or -1
        r.frame = tonumber(runtime_action_frame) or 0
    end

    local p_def = p_obj:get_type_definition()
    local d = (p_def:get_field("pl_input_new"):get_data(p_obj)) or 0
    local b = (p_def:get_field("pl_sw_new"):get_data(p_obj)) or 0
    r.direct_input = d | b
    r.direction_input = d
    r.facing_right = p_obj:get_field("rl_dir") ~= false

    local act_param = p_obj:get_field("mpActParam")
    if not act_param then return end
    local action_part = act_param:get_field("ActionPart")
    if action_part then
        local engine = action_part:get_field("_Engine")
        if engine then
            local m_param = engine:get_field("mParam")
            if m_param then
                local sf_field = m_param:get_type_definition():get_field("state_flags")
                if sf_field then r.state_flags = tonumber(sf_field:get_data(m_param)) or -1 end
            end
        end
    end
    local ki_field = act_param:get_type_definition():get_field("KeyInput")
    if ki_field then
        local ki_data = ki_field:get_data(act_param)
        if ki_data then
            local a_field = ki_data:get_type_definition():get_field("Action")
            if a_field then r.action_code = tonumber(a_field:get_data(ki_data)) or 0 end
        end
    end
    local branch = act_param:get_field("Branch")
    if branch then
        local bt_field = branch:get_type_definition():get_field("BranchType")
        if bt_field then r.branch_type = tonumber(bt_field:get_data(branch)) or 0 end
    end
end

function GameProbe.get_runtime_action_data(p_obj)
    if not p_obj then return -1, 0 end
    local ok, action_id, action_frame = pcall(_ct_read_runtime_action_data, p_obj)
    if not ok then return -1, 0 end
    return action_id, action_frame
end

function GameProbe.get_action_data(p_obj, runtime_action_id, runtime_action_frame)
    if not p_obj then return -1, 0, -1, 0, 0, 0, 0, true end
    local r = _ct_action_scratch
    r.act_id, r.frame, r.state_flags, r.action_code = -1, 0, -1, 0
    r.direct_input, r.direction_input, r.branch_type, r.facing_right = 0, 0, 0, true
    pcall(_ct_read_action_data, p_obj, runtime_action_id, runtime_action_frame)
    return r.act_id, r.frame, r.state_flags, r.action_code, r.direct_input,
        r.branch_type, r.direction_input, r.facing_right
end

function GameProbe.get_damage_type_safe(p_char)
    if not p_char then return 0 end

    local result = 0
    pcall(function()
        -- Direct syntax via REFramework's syntactic sugar
        local act_val = tonumber(p_char.act_st)

        if act_val == 27 or act_val == 32 or act_val == 35 or act_val == 38 then
            result = 1
        end
    end)

    return result
end

function GameProbe.check_is_projectile(attacker_idx, attacker_obj, gBattle)
    local attacker_hs = 0
    pcall(function()
        local f_hs = attacker_obj:get_type_definition():get_field("hit_stop")
        if f_hs then attacker_hs = f_hs:get_data(attacker_obj) or 0 end
    end)
    return (attacker_hs == 0)
end

local function _ct_read_combo_cnt(p_obj)
    return p_obj:get_type_definition():get_field("combo_cnt"):get_data(p_obj) or 0
end
function GameProbe.get_combo_count(p_obj)
    if not p_obj then return 0 end
    local s, res = pcall(_ct_read_combo_cnt, p_obj)
    return s and res or 0
end

-- Internal recording sample used only to calculate combo result statistics.
function GameProbe.capture_recording_gauges(attacker_idx)
    local result = nil
    pcall(function()
        local victim = (attacker_idx == 0) and GS.p2 or GS.p1
        local attacker = (attacker_idx == 0) and GS.p1 or GS.p2
        if not victim or not attacker then return end
        local gB = g_battle_type
        if not gB then return end
        local BT = gB:get_field("Team"):get_data(nil)
        if not BT or not BT.mcTeam then return end

        local atk_team = BT.mcTeam[attacker_idx]

        if not victim or not attacker or not atk_team then return end

        local v_hp = victim.vital_new
        local a_dr = attacker.focus_new
        local a_sa = atk_team.mSuperGauge

        if v_hp == nil or a_dr == nil or a_sa == nil then return end

        result = {
            victim_hp = v_hp,
            attacker_drive = a_dr,
            attacker_super = a_sa,
            -- Min trackers (updated each frame in on_frame)
            min_victim_hp = v_hp,
            min_atk_drive = a_dr,
            min_atk_super = a_sa
        }
    end)
    return result
end

return GameProbe
