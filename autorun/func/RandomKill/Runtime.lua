local M = {}

local PARAMETER_FIELDS = {
    "Vital_Type",
    "Vital_Point",
    "Vital_Point_Type",
    "Vital_Timer",
    "Is_Vital_Infinity",
    "Is_Vital_No_Recovery",
    "Is_Vital_Recovery_Timer",
    "Is_KO",
    "Is_Point_Lock",
    "DG_Type",
    "DG_Stock",
    "DG_Point",
    "Is_DG_Point_Lock",
    "Is_DG_Break",
    "Is_DG_Recovery_Timer",
    "DG_Timer",
    "SA_Type",
    "SA_Stock",
    "SA_Point",
    "Is_SA_Point_Lock",
    "Is_SA_No_Recovery",
    "Is_SA_Recovery_Timer",
    "SA_Timer",
}

local LIVE_FIELDS = {
    "vital_new",
    "vital_old",
    "heal_new",
    "heal_old",
    "focus_new",
    "focus_old",
}

local GUARD_FIELDS = {
    "GuardType",
    "GuardWeight",
    "GuardCount",
    "IsGuardSwitching",
    "GuardOnlyType",
}

local DEFENSE_FIELDS = {
    "DP_Type",
}

local pending = nil
local tf_parameter_setting = nil
local tf_guard_setting = nil
local tf_defense_system = nil
local battle_team_field = nil

local function read_value(object, field_name)
    if not object then return nil end
    local ok, value = pcall(function() return object[field_name] end)
    if ok and value ~= nil then return value end
    ok, value = pcall(function() return object:get_field(field_name) end)
    return ok and value or nil
end

local function write_value(object, field_name, value)
    if not object or value == nil then return false end
    local ok = pcall(function() object[field_name] = value end)
    if ok then return true end
    ok = pcall(function() object:set_field(field_name, value) end)
    return ok
end

local function copy_fields(object, field_names)
    local out = {}
    for _, field_name in ipairs(field_names) do
        local value = read_value(object, field_name)
        if value ~= nil then out[field_name] = value end
    end
    return out
end

local function write_fields(object, fields)
    local wrote = false
    for field_name, value in pairs(fields or {}) do
        wrote = write_value(object, field_name, value) or wrote
    end
    return wrote
end

local function training_context()
    if not sdk or not sdk.get_managed_singleton then
        return nil, "sdk unavailable"
    end
    local manager = sdk.get_managed_singleton("app.training.TrainingManager")
    if not manager then return nil, "TrainingManager unavailable" end
    local training_data = read_value(manager, "_tData")
    if not training_data then return nil, "TrainingManager._tData unavailable" end
    local select_menu = read_value(training_data, "SelectMenu")
    local parameter_setting = read_value(training_data, "ParameterSetting")
    local guard_setting = read_value(training_data, "GuardSetting")
    local defense_system = read_value(training_data, "DefenseSystem")
    local select_players = select_menu and read_value(select_menu, "PlayerDatas") or nil
    local parameter_players = parameter_setting and read_value(parameter_setting, "PlayerDatas") or nil
    local defense_players = defense_system and read_value(defense_system, "PlayerDatas") or nil
    local p1_select = select_players and select_players[0] or nil
    local p2_select = select_players and select_players[1] or nil
    local p1_params = parameter_players and parameter_players[0] or nil
    local guard_dummy = guard_setting and read_value(guard_setting, "DummyData") or nil
    local defense_dummy = defense_system and read_value(defense_system, "DummyData") or nil
    local p2_defense = defense_players and defense_players[1] or nil
    if not select_menu or not p1_select or not p2_select or not p1_params
        or not guard_dummy or not defense_dummy then
        return nil, "training player settings unavailable"
    end
    return {
        manager = manager,
        training_data = training_data,
        select_menu = select_menu,
        parameter_setting = parameter_setting,
        guard_setting = guard_setting,
        guard_dummy = guard_dummy,
        defense_system = defense_system,
        defense_dummy = defense_dummy,
        p2_defense = p2_defense,
        p1_select = p1_select,
        p2_select = p2_select,
        p1_params = p1_params,
        param_func = parameter_setting and read_value(parameter_setting, "ParamFunc") or nil,
    }, nil
end

local function game_state()
    return rawget(_G, "GameState")
end

local function p1_team()
    if not sdk or not sdk.find_type_definition then return nil end
    if not battle_team_field then
        local battle_type = sdk.find_type_definition("gBattle")
        battle_team_field = battle_type and battle_type:get_field("Team") or nil
    end
    local battle = battle_team_field and battle_team_field:get_data(nil) or nil
    return battle and battle.mcTeam and battle.mcTeam[0] or nil
end

local function find_tf_parameter_setting(context)
    if tf_parameter_setting then return tf_parameter_setting end
    local funcs = context and read_value(context.manager, "_tfFuncs") or nil
    local entries = funcs and read_value(funcs, "_entries") or nil
    if not entries then return nil end

    local fallback = nil
    pcall(function()
        local entry = entries:call("get_Item", 6)
        fallback = entry and read_value(entry, "value") or nil
    end)
    local count = 0
    pcall(function() count = tonumber(entries:call("get_Count")) or 0 end)
    for index = 0, count - 1 do
        local value = nil
        pcall(function()
            local entry = entries:call("get_Item", index)
            value = entry and read_value(entry, "value") or nil
        end)
        if value then
            local full_name = ""
            pcall(function()
                local definition = value:get_type_definition()
                full_name = definition and definition:get_full_name() or ""
            end)
            if full_name:find("tf_ParameterSetting", 1, true)
                or full_name:find("ParameterSetting", 1, true) then
                tf_parameter_setting = value
                return value
            end
        end
    end
    tf_parameter_setting = fallback
    return fallback
end

local function find_tf_guard_setting(context)
    if tf_guard_setting then return tf_guard_setting end
    local funcs = context and read_value(context.manager, "_tfFuncs") or nil
    local entries = funcs and read_value(funcs, "_entries") or nil
    if not entries then return nil end
    local count = 0
    pcall(function() count = tonumber(entries:call("get_Count")) or 0 end)
    for index = 0, count - 1 do
        local value = nil
        pcall(function()
            local entry = entries:call("get_Item", index)
            value = entry and read_value(entry, "value") or nil
        end)
        if value then
            local full_name = ""
            pcall(function()
                local definition = value:get_type_definition()
                full_name = definition and definition:get_full_name() or ""
            end)
            if full_name:find("tf_GuardSetting", 1, true) then
                tf_guard_setting = value
                return value
            end
        end
    end
    return nil
end

local function find_tf_defense_system(context)
    if tf_defense_system then return tf_defense_system end
    local funcs = context and read_value(context.manager, "_tfFuncs") or nil
    local entries = funcs and read_value(funcs, "_entries") or nil
    if not entries then return nil end
    local count = 0
    pcall(function() count = tonumber(entries:call("get_Count")) or 0 end)
    for index = 0, count - 1 do
        local value = nil
        pcall(function()
            local entry = entries:call("get_Item", index)
            value = entry and read_value(entry, "value") or nil
        end)
        if value then
            local full_name = ""
            pcall(function()
                local definition = value:get_type_definition()
                full_name = definition and definition:get_full_name() or ""
            end)
            if full_name:find("tf_DefenseSystem", 1, true) then
                tf_defense_system = value
                return value
            end
        end
    end
    return nil
end

local function apply_parameter_changes(context)
    local tf_setting = find_tf_parameter_setting(context)
    if tf_setting then pcall(function() tf_setting:call("bApply") end) end
    write_value(context.manager, "_IsReqRefresh", true)
end

local function apply_guard_changes(context)
    local tf_guard = find_tf_guard_setting(context)
    if tf_guard then pcall(function() tf_guard:call("bApply") end) end
end

local function apply_defense_changes(context)
    local tf_defense = find_tf_defense_system(context)
    if tf_defense then pcall(function() tf_defense:call("bApply") end) end
end

local function call_param(context, method_name, ...)
    if not context.param_func then return false end
    local args = { ... }
    local ok = pcall(function()
        context.param_func:call(method_name, table.unpack(args))
    end)
    return ok
end

local function scenario_parameter_fields(scenario)
    return {
        Vital_Point = scenario.hp_pct,
        Is_Vital_Infinity = false,
        Is_Vital_No_Recovery = true,
        Is_Vital_Recovery_Timer = false,
        Is_KO = false,
        Is_Point_Lock = false,
        DG_Stock = scenario.drive_bars,
        DG_Point = scenario.drive_points,
        Is_DG_Point_Lock = false,
        Is_DG_Break = false,
        Is_DG_Recovery_Timer = false,
        DG_Timer = 0,
        SA_Stock = scenario.super_bars,
        SA_Point = scenario.super_points,
        Is_SA_Point_Lock = false,
        Is_SA_No_Recovery = false,
        Is_SA_Recovery_Timer = false,
        SA_Timer = 0,
    }
end

local function apply_live_scenario(scenario)
    local state = game_state()
    local p1 = state and state.p1 or nil
    local p2 = state and state.p2 or nil
    if not p1 or not p2 then return false, "player objects unavailable" end

    local max_hp = tonumber(read_value(p1, "vital_max"))
    if not max_hp or max_hp <= 0 then return false, "P1 vital_max unavailable" end
    local hp = math.floor(max_hp * scenario.hp_pct / 100 + 0.5)
    local resources_ok = true
    for _, field_name in ipairs({ "vital_new", "vital_old", "heal_new", "heal_old" }) do
        resources_ok = write_value(p1, field_name, hp) and resources_ok
    end
    resources_ok = write_value(p1, "focus_new", scenario.drive_points) and resources_ok
    resources_ok = write_value(p1, "focus_old", scenario.drive_points) and resources_ok
    local team = p1_team()
    if not team then return false, "P1 battle team unavailable" end
    resources_ok = write_value(team, "mSuperGauge", scenario.super_points) and resources_ok
    if not resources_ok then return false, "exact P1 resource write failed" end
    return true, nil
end

local function apply_live_backup(backup)
    local state = game_state()
    local p1 = state and state.p1 or nil
    if not p1 then return false, "P1 unavailable while restoring" end
    write_fields(p1, backup.live_fields)
    local team = p1_team()
    if team and backup.super_gauge ~= nil then
        write_value(team, "mSuperGauge", backup.super_gauge)
    end
    return true, nil
end

function M.capture()
    local context, err = training_context()
    if not context then return nil, err end
    local state = game_state()
    local p1 = state and state.p1 or nil
    if not p1 then return nil, "P1 unavailable" end
    local team = p1_team()
    return {
        start_location = read_value(context.select_menu, "StartLocation"),
        p1_manual_x = read_value(context.p1_select, "ManualPosX"),
        p2_manual_x = read_value(context.p2_select, "ManualPosX"),
        parameter_fields = copy_fields(context.p1_params, PARAMETER_FIELDS),
        guard_fields = copy_fields(context.guard_dummy, GUARD_FIELDS),
        defense_dummy_fields = copy_fields(context.defense_dummy, DEFENSE_FIELDS),
        p2_defense_fields = copy_fields(context.p2_defense, DEFENSE_FIELDS),
        live_fields = copy_fields(p1, LIVE_FIELDS),
        super_gauge = team and read_value(team, "mSuperGauge") or nil,
    }, nil
end

function M.apply_scenario(scenario)
    if type(scenario) ~= "table" then return false, "scenario missing" end
    local context, err = training_context()
    if not context then return false, err end

    write_value(context.select_menu, "StartLocation", 3)
    write_value(context.p1_select, "ManualPosX", scenario.p1_x)
    write_value(context.p2_select, "ManualPosX", scenario.p2_x)
    write_fields(context.p1_params, scenario_parameter_fields(scenario))
    write_value(context.guard_dummy, "GuardType", 3)
    write_value(context.guard_dummy, "IsGuardSwitching", true)
    write_value(context.guard_dummy, "GuardOnlyType", 0)
    write_value(context.defense_dummy, "DP_Type", 0)
    write_value(context.p2_defense, "DP_Type", 0)
    call_param(context, "SetVitalPoint", 0, scenario.hp_pct)
    call_param(context, "SetVitalInfinity", 0, false)
    call_param(context, "SetVitalNoRecovery", 0, true)
    call_param(context, "SetDGDetailPoint", 0, scenario.drive_points)
    call_param(context, "SetDGStock", 0, scenario.drive_bars)
    apply_defense_changes(context)
    apply_parameter_changes(context)
    apply_guard_changes(context)
    pending = {
        kind = "scenario",
        scenario = scenario,
        settle_frames = 10,
        timeout_frames = 90,
    }
    return true, nil
end

function M.restore(backup)
    if type(backup) ~= "table" then return false, "runtime backup missing" end
    local context, err = training_context()
    if not context then return false, err end

    write_value(context.select_menu, "StartLocation", backup.start_location)
    write_value(context.p1_select, "ManualPosX", backup.p1_manual_x)
    write_value(context.p2_select, "ManualPosX", backup.p2_manual_x)
    write_fields(context.p1_params, backup.parameter_fields)
    write_fields(context.guard_dummy, backup.guard_fields)
    write_fields(context.defense_dummy, backup.defense_dummy_fields)
    write_fields(context.p2_defense, backup.p2_defense_fields)
    apply_defense_changes(context)
    apply_parameter_changes(context)
    apply_guard_changes(context)
    pending = {
        kind = "restore",
        backup = backup,
        settle_frames = 10,
        timeout_frames = 90,
    }
    return true, nil
end

function M.update()
    if not pending then return "idle", nil end
    local context, err = training_context()
    if not context then return "waiting", err end
    local refreshing = read_value(context.manager, "_IsReqRefresh") == true
    if refreshing then
        pending.timeout_frames = pending.timeout_frames - 1
        if pending.timeout_frames <= 0 then
            local kind = pending.kind
            pending = nil
            return "error", kind .. " refresh timed out"
        end
        return "waiting", nil
    end

    pending.settle_frames = pending.settle_frames - 1
    if pending.settle_frames > 0 then return "settling", nil end
    local current = pending
    pending = nil
    if current.kind == "scenario" then
        local ok, apply_err = apply_live_scenario(current.scenario)
        return ok and "ready" or "error", apply_err
    end
    local ok, restore_err = apply_live_backup(current.backup)
    return ok and "restored" or "error", restore_err
end

function M.cancel_pending()
    pending = nil
end

function M.read_p2_vital()
    local state = game_state()
    local p2 = state and state.p2 or nil
    if not p2 then return nil end
    return tonumber(read_value(p2, "vital_new") or read_value(p2, "vital_old"))
end

return M
