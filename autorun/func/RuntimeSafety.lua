-- Central safety gate for SF6CC runtime features.
-- Default-deny: features are considered inactive unless Training_ScriptManager
-- explicitly publishes an allowed training context this frame.

local M = {}
local sdk = sdk

local state = {
    allowed = false,
    input_allowed = false,
    reason = "init",
    flow_id = nil,
    in_training = false,
    in_replay = false,
    in_battle_hub = false,
    frame = 0,
}

local function publish()
    _G.SF6CC_RuntimeSafety = state
    _G.SF6CC_RuntimeAllowed = state.allowed == true
    _G.SF6CC_InputInjectionAllowed = state.input_allowed == true
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
    _G._dv_aa_p2_mask = 0
end

local function read_flow_id()
    local bfm = sdk and sdk.get_managed_singleton and sdk.get_managed_singleton("app.bFlowManager")
    if not bfm then return nil end
    local work = bfm:get_field("m_flow_work")
    if work and work._FlowMap then return work._FlowMap._ID end
    return nil
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

    local candidates = {
        "get_IsTrainingMode",
        "get_IsTraining",
        "get_IsActive",
        "get_IsEnable",
    }
    for _, method in ipairs(candidates) do
        local ok, value = pcall(function() return tm:call(method) end)
        if ok and value == false then return false end
    end
    return true
end

local function has_training_context()
    local tm = sdk and sdk.get_managed_singleton and sdk.get_managed_singleton("app.training.TrainingManager")
    return has_training_manager_data(tm)
        and has_training_ui_widgets(tm)
        and training_manager_allows(tm)
end

local function native_training_context()
    local fid = read_flow_id()
    if fid == 9 or fid == 10 then return false end
    if _G.IsInBattleHub == true or _G.IsInReplay == true then return false end
    return has_training_context()
end

function M.begin_frame(flow_id, in_training, in_replay, in_battle_hub)
    state.allowed = false
    state.input_allowed = false
    state.reason = "pending"
    state.flow_id = flow_id
    state.in_training = in_training == true
    state.in_replay = in_replay == true
    state.in_battle_hub = in_battle_hub == true
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
    state.allowed = true
    state.input_allowed = true
    state.reason = "training"
    publish()
end

function M.allow_replay()
    state.allowed = true
    state.input_allowed = false
    state.reason = "replay"
    publish()
end

function M.is_allowed()
    if _G.SF6CC_RuntimeAllowed ~= true then return false end
    if M.is_replay_allowed() then
        local fid = read_flow_id()
        return fid == 10 or _G.IsInReplay == true
    end
    return native_training_context()
end

function M.can_inject_input()
    return _G.SF6CC_InputInjectionAllowed == true and native_training_context()
end

function M.is_training_allowed()
    local s = _G.SF6CC_RuntimeSafety
    return s and s.allowed == true and s.reason == "training" and native_training_context()
end

function M.is_replay_allowed()
    local s = _G.SF6CC_RuntimeSafety
    if not (s and s.allowed == true and s.reason == "replay") then return false end
    local fid = read_flow_id()
    return fid == 10 or _G.IsInReplay == true
end

function M.clear_runtime_flags()
    clear_runtime_flags()
end

publish()

return M
