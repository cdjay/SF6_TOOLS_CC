-- Central safety gate for SF6CC runtime features.
-- Default-deny: features are considered inactive unless Training_ScriptManager
-- explicitly publishes an allowed training context this frame.

local M = {}
local sdk = sdk
local DIAGNOSTIC_BUILD = "0.97a-network-rule-1"

local state = {
    build = DIAGNOSTIC_BUILD,
    allowed = false,
    input_allowed = false,
    reason = "init",
    flow_id = nil,
    in_training = false,
    in_replay = false,
    in_battle_hub = false,
    battle_input_type = nil,
    network_game_mode = nil,
    in_online_battle = false,
    native_context = false,
    native_context_frame = nil,
    frame = 0,
}

local native_context_cache = { frame = -1, value = false }
local TRAINING_MANAGER_ALLOW_METHODS = {
    "get_IsTrainingMode",
    "get_IsTraining",
    "get_IsActive",
    "get_IsEnable",
}

-- app.training.TrainingManager.GameMode
-- Only the offline Fighting Ground training mode may run SF6CC training
-- features. In particular, TrainingManager and its UI dictionary can survive
-- the transition from training matchmaking into a ranked/casual battle.
local TRAINING_GAME_MODE = 1
local BATTLE_INPUT_ONLINE = 1
local BATTLE_INPUT_ONLINE_CPU = 4
local ONLINE_GAME_MODES = {
    [14] = true, -- Ranked Match
    [15] = true, -- Player Match
    [16] = true, -- Cabinet Match
    [17] = true, -- Custom Room Match
    [18] = true, -- Online Training
}

local function trace(message, component)
    local line = "[SF6CC." .. tostring(component or "RuntimeSafety") .. "] " .. tostring(message)
    if log and log.info then
        local ok = pcall(log.info, line)
        if ok then return end
    end
    pcall(print, line)
end

local function publish()
    _G.SF6CC_RuntimeSafety = state
    _G.SF6CC_RuntimeAllowed = state.allowed == true
    _G.SF6CC_InputInjectionAllowed = state.input_allowed == true
    _G.IsInOnlineBattle = state.in_online_battle == true
end

local function clear_runtime_flags()
    _G.TrainingModeActive = false
    _G.TrainingScriptManagerActiveThisFrame = false
    _G.TrainingGamePaused = true
    _G.TrainingFloatingBar = nil
    _G.TrainingFloatingBarTop = nil
    _G.ComboTrialsD2DEnabled = false
    _G.ComboTrials_HideNativeHUD = false
    _G._ct_bar_geometry = nil
    _G.TrainingBarsDrawn = false
    _G._dv_aa_p2_mask = 0
end

local function read_managed_field(obj, field_name)
    if not obj then return nil end
    local ok, value = pcall(function() return obj:get_field(field_name) end)
    if ok then return value end
    return nil
end

-- Mirrors REFramework's own SF6 online-match lookup. This value can switch to
-- an online GameMode while FlowMap and TrainingManager still report training.
local function read_network_game_mode()
    if not (sdk and sdk.get_managed_singleton) then return nil end

    local network = sdk.get_managed_singleton("app.network.NetworkManager")
    local session = read_managed_field(network, "<Session>k__BackingField")
    local fg_battle = read_managed_field(session, "<FGBattle>k__BackingField")
    local battle_rule = read_managed_field(fg_battle, "<BattleRule>k__BackingField")
    local game_mode = read_managed_field(battle_rule, "GameMode")
    return tonumber(tostring(game_mode))
end

local function refresh_online_battle_context()
    local game_mode = read_network_game_mode()
    local network_online = game_mode ~= nil and ONLINE_GAME_MODES[game_mode] == true
    local input_online = state.battle_input_type == BATTLE_INPUT_ONLINE
        or state.battle_input_type == BATTLE_INPUT_ONLINE_CPU
    local online = network_online or input_online
    local changed = game_mode ~= state.network_game_mode or online ~= state.in_online_battle

    state.network_game_mode = game_mode
    state.in_online_battle = online
    if online then
        native_context_cache.frame = -1
        native_context_cache.value = false
        state.native_context = false
        state.native_context_frame = nil
        state.allowed = false
        state.input_allowed = false
        state.reason = "online_game_mode"
        clear_runtime_flags()
    end

    if changed then
        publish()
        trace("network_game_mode=" .. tostring(game_mode)
            .. " online=" .. tostring(online)
            .. " flow=" .. tostring(state.flow_id)
            .. " trainer_mode=" .. tostring(_G.CurrentTrainerMode)
            .. " reason=" .. tostring(state.reason)
            .. " d2d=" .. tostring(_G.ComboTrialsD2DEnabled))
    end
    return online
end

local function read_flow_id()
    local bfm = sdk and sdk.get_managed_singleton and sdk.get_managed_singleton("app.bFlowManager")
    if not bfm then return nil end
    local work = bfm:get_field("m_flow_work")
    if work and work._FlowMap then return work._FlowMap._ID end
    return nil
end

local function current_flow_id()
    if state.flow_id ~= nil then return state.flow_id end
    return read_flow_id()
end

local function get_training_manager()
    return sdk and sdk.get_managed_singleton and sdk.get_managed_singleton("app.training.TrainingManager")
end

local function has_training_manager_data(tm)
    tm = tm or get_training_manager()
    local t_data = tm and tm:get_field("_tData")
    if not t_data then return false end

    local ok, has_core_settings = pcall(function()
        return t_data:get_field("SelectMenu") ~= nil
            and t_data:get_field("ParameterSetting") ~= nil
            and t_data:get_field("GuardSetting") ~= nil
    end)
    return ok and has_core_settings == true
end

local function has_training_ui_widgets(tm)
    tm = tm or get_training_manager()
    if not tm then return false end

    local ok, result = pcall(function()
        local dict = tm:get_field("_ViewUIWigetDict")
        local entries = dict and dict:get_field("_entries")
        if not entries then return false end
        local count = entries:call("get_Count")
        if not count or count <= 0 then return false end

        for i = 0, count - 1 do
            local entry = entries:call("get_Item", i)
            local widgets = entry and entry:get_field("value")
            local w_count = widgets and widgets:call("get_Count")
            if w_count and w_count > 0 then
                for j = 0, w_count - 1 do
                    local widget = widgets:call("get_Item", j)
                    local td = widget and widget:get_type_definition()
                    local name = td and td:get_full_name()
                    if name and (name:find("Training") or name:find("TM") or name:find("TMAttackInfo")) then
                        return true
                    end
                end
            end
        end
        return false
    end)
    return ok and result == true
end

local function training_manager_allows(tm)
    tm = tm or get_training_manager()
    if not tm then return false end

    for _, method in ipairs(TRAINING_MANAGER_ALLOW_METHODS) do
        local ok, value = pcall(function() return tm:call(method) end)
        if ok and value == false then return false end
    end
    return true
end

local function has_offline_training_game_mode(tm)
    tm = tm or get_training_manager()
    if not tm then return false end

    local ok, game_mode = pcall(function() return tm:get_field("_GameMode") end)
    if not ok or game_mode == nil then return false end
    return tonumber(tostring(game_mode)) == TRAINING_GAME_MODE
end

local function has_training_context()
    local tm = sdk and sdk.get_managed_singleton and sdk.get_managed_singleton("app.training.TrainingManager")
    return has_offline_training_game_mode(tm)
        and has_training_manager_data(tm)
        and has_training_ui_widgets(tm)
        and training_manager_allows(tm)
end

local function native_training_context()
    local fid = current_flow_id()
    if fid == 9 or fid == 10 then return false end
    if _G.IsInBattleHub == true or _G.IsInReplay == true then return false end
    if refresh_online_battle_context() then return false end
    if state.in_online_battle == true or _G.IsInOnlineBattle == true then return false end
    return has_training_context()
end

local function cached_native_training_context()
    local frame = state.frame or 0
    if native_context_cache.frame == frame then
        return native_context_cache.value
    end

    local ok, value = pcall(native_training_context)
    native_context_cache.frame = frame
    native_context_cache.value = ok and value == true
    state.native_context = native_context_cache.value
    state.native_context_frame = frame
    return native_context_cache.value
end

function M.begin_frame(flow_id, in_training, in_replay, in_battle_hub)
    state.allowed = false
    state.input_allowed = false
    state.reason = "pending"
    state.flow_id = flow_id
    state.in_training = in_training == true
    state.in_replay = in_replay == true
    state.in_battle_hub = in_battle_hub == true
    state.native_context = false
    state.native_context_frame = nil
    state.frame = (state.frame or 0) + 1
    publish()
end

function M.disable(reason)
    state.allowed = false
    state.input_allowed = false
    state.reason = reason or "disabled"
    clear_runtime_flags()
    publish()
end

function M.allow_training()
    local allowed = cached_native_training_context()
    state.allowed = allowed
    state.input_allowed = allowed
    state.reason = allowed and "training" or "unsafe_training_context"
    publish()
end

function M.set_battle_input_type(input_type)
    local value = tonumber(tostring(input_type))
    if value == nil then return false end

    state.battle_input_type = value
    state.in_online_battle = value == BATTLE_INPUT_ONLINE or value == BATTLE_INPUT_ONLINE_CPU
    native_context_cache.frame = -1
    native_context_cache.value = false
    state.native_context = false
    state.native_context_frame = nil

    if state.in_online_battle then
        state.allowed = false
        state.input_allowed = false
        state.reason = "online_battle"
        clear_runtime_flags()
    end
    publish()
    trace("battle_input_type=" .. tostring(value)
        .. " online=" .. tostring(state.in_online_battle)
        .. " flow=" .. tostring(state.flow_id)
        .. " trainer_mode=" .. tostring(_G.CurrentTrainerMode)
        .. " reason=" .. tostring(state.reason)
        .. " d2d=" .. tostring(_G.ComboTrialsD2DEnabled))
    return true
end

function M.trace(message, component)
    trace(message, component)
end

function M.allow_replay()
    state.allowed = true
    state.input_allowed = false
    state.reason = "replay"
    publish()
end

function M.is_allowed()
    if refresh_online_battle_context() then return false end
    if _G.SF6CC_RuntimeAllowed ~= true then return false end
    if M.is_replay_allowed() then
        local fid = current_flow_id()
        return fid == 10 or _G.IsInReplay == true
    end
    return cached_native_training_context()
end

function M.can_inject_input()
    if refresh_online_battle_context() then return false end
    return _G.SF6CC_InputInjectionAllowed == true and cached_native_training_context()
end

function M.is_training_allowed()
    -- Do not cache this online check by state.frame. REFramework intentionally
    -- stops normal Lua frame callbacks during online matches, so state.frame
    -- freezes precisely when this safety gate matters most. D2D callbacks keep
    -- polling the network battle rule and get one chance to clear their target.
    if refresh_online_battle_context() then return false end
    local s = _G.SF6CC_RuntimeSafety
    return s and s.allowed == true and s.reason == "training" and cached_native_training_context()
end

function M.is_replay_allowed()
    local s = _G.SF6CC_RuntimeSafety
    if not (s and s.allowed == true and s.reason == "replay") then return false end
    local fid = current_flow_id()
    return fid == 10 or _G.IsInReplay == true
end

function M.clear_runtime_flags()
    clear_runtime_flags()
end

publish()
trace("loaded build=" .. DIAGNOSTIC_BUILD)

return M
