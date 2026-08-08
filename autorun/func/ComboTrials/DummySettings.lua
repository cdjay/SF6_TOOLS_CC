local TrainingEnvironment = require("func/ComboTrials/TrainingEnvironment")

local DummySettings = {
    name = "ComboTrials.DummySettings",
}

local trial_state = nil

function DummySettings.init(state)
    trial_state = state
end

-- Sets the Dummy Counter state (0=Normal, 1=Counter, 2=Punish Counter)
-- Cache tf_CounterSetting from _tfFuncs
local _tf_counter_cache = nil
local function get_tf_counter()
    if _tf_counter_cache then return _tf_counter_cache end
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local dict = tm:get_field("_tfFuncs")
        if not dict then return end
        local entries = dict:get_field("_entries")
        if not entries then return end
        local count = entries:call("get_Count")
        for i = 0, count - 1 do
            local entry = entries:call("get_Item", i)
            if entry then
                local val = entry:get_field("value")
                if val then
                    local td = val:get_type_definition()
                    if td:get_full_name():find("tf_CounterSetting") then
                        _tf_counter_cache = val
                        return
                    end
                end
            end
        end
    end)
    return _tf_counter_cache
end

-- 0=Normal, 1=CH, 2=PC, 3=Random (via DummyData + bApply).
-- Weight fields are raw values from the native T/detail menu.
DummySettings.COUNTER_RUNTIME_FIELDS = {
    "NC_TYPE",
    "PC_TYPE",
    "NC_Weight",
    "NH_Weight",
    "PC_Weight",
    "StyleNo"
}

function DummySettings.set_counter_type(counter_val, raw_settings)
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        if not tData then return end
        local cs = tData:get_field("CounterSetting")
        if not cs then return end
        local dd = cs:get_field("DummyData")
        if not dd then return end
        if counter_val == 3 then
            dd.NC_TYPE = 2; dd.PC_TYPE = 2
        elseif counter_val == 2 then
            dd.NC_TYPE = 0; dd.PC_TYPE = 1
        elseif counter_val == 1 then
            dd.NC_TYPE = 1; dd.PC_TYPE = 0
        else
            dd.NC_TYPE = 0; dd.PC_TYPE = 0
        end
        if type(raw_settings) == "table" then
            for _, field_name in ipairs(DummySettings.COUNTER_RUNTIME_FIELDS) do
                if raw_settings[field_name] ~= nil then dd[field_name] = raw_settings[field_name] end
            end
        end
    end)
    local tc = get_tf_counter()
    if tc then pcall(function() tc:call("bApply") end) end
end

function DummySettings.read_counter_settings()
    local result = { counter_type = 0 }
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        if not tData then return end
        local cs = tData:get_field("CounterSetting")
        if not cs then return end
        local dd = cs:get_field("DummyData")
        if not dd then return end
        for _, field_name in ipairs(DummySettings.COUNTER_RUNTIME_FIELDS) do
            result[field_name] = dd[field_name]
        end
        result.counter_type =
            TrainingEnvironment.counter_type_from_runtime(
                result.NC_TYPE,
                result.PC_TYPE
            )
    end)
    return result
end

-- Read the current counter state.
function DummySettings.read_counter_type()
    return DummySettings.read_counter_settings().counter_type
end

function DummySettings.save_counter_type()
    if trial_state._saved_counter_settings == nil then
        trial_state._saved_counter_settings = DummySettings.read_counter_settings()
    end
end

function DummySettings.restore_counter_type()
    local saved = trial_state._saved_counter_settings
    if type(saved) == "table" then
        DummySettings.set_counter_type(saved.counter_type, saved)
        trial_state._saved_counter_settings = nil
    end
end

-- Cache tf_GuardSetting from _tfFuncs
local _tf_guard_cache = nil
local function get_tf_guard()
    if _tf_guard_cache then return _tf_guard_cache end
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local dict = tm:get_field("_tfFuncs")
        if not dict then return end
        local entries = dict:get_field("_entries")
        if not entries then return end
        local count = entries:call("get_Count")
        for i = 0, count - 1 do
            local entry = entries:call("get_Item", i)
            if entry then
                local val = entry:get_field("value")
                if val and val:get_type_definition():get_full_name():find("tf_GuardSetting") then
                    _tf_guard_cache = val
                    return
                end
            end
        end
    end)
    return _tf_guard_cache
end

DummySettings.GUARD_RUNTIME_FIELDS = {
    "GuardType",
    "GuardWeight",
    "GuardCount",
    "IsGuardSwitching",
    "GuardOnlyType"
}

function DummySettings.set_guard_type(guard_val, guard_count, raw_settings)
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        local gs = tData:get_field("GuardSetting")
        local dd = gs:get_field("DummyData")
        dd.GuardType = guard_val
        local runtime_guard_count =
            TrainingEnvironment.guard_count_to_runtime(guard_count)
        if runtime_guard_count ~= nil then dd.GuardCount = runtime_guard_count end
        if type(raw_settings) == "table" then
            for _, field_name in ipairs(DummySettings.GUARD_RUNTIME_FIELDS) do
                if field_name ~= "GuardType"
                    and field_name ~= "GuardCount"
                    and raw_settings[field_name] ~= nil then
                    dd[field_name] = raw_settings[field_name]
                end
            end
        end
    end)
    local tg = get_tf_guard()
    if tg then pcall(function() tg:call("bApply") end) end
end

function DummySettings.read_guard_settings()
    local result = { guard_type = 0, guard_count = nil }
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        local gs = tData:get_field("GuardSetting")
        local dd = gs:get_field("DummyData")
        for _, field_name in ipairs(DummySettings.GUARD_RUNTIME_FIELDS) do
            result[field_name] = dd[field_name]
        end
        result.guard_type = result.GuardType or 0
        result.guard_count =
            TrainingEnvironment.guard_count_from_runtime(dd.GuardCount)
    end)
    return result
end

function DummySettings.read_guard_type()
    local result = DummySettings.read_guard_settings()
    return result.guard_type, result.guard_count
end

function DummySettings.save_guard_type()
    if trial_state._saved_guard_settings == nil then
        trial_state._saved_guard_settings = DummySettings.read_guard_settings()
    end
end

function DummySettings.restore_guard_type()
    local saved = trial_state._saved_guard_settings
    if type(saved) == "table" then
        DummySettings.set_guard_type(saved.guard_type, saved.guard_count, saved)
        trial_state._saved_guard_settings = nil
    end
end

-- Game enums:
-- DummyActionType: 0=stand, 1=crouch, 2=jump.
-- JumpType: 0=vertical, 1=front, 2=back, 3=random.
local DUMMY_ACTION_STAND = TrainingEnvironment.DUMMY_ACTION.STAND
local DUMMY_ACTION_CROUCH = TrainingEnvironment.DUMMY_ACTION.CROUCH
DummySettings.DUMMY_ACTION_STAND = DUMMY_ACTION_STAND
DummySettings.DUMMY_ACTION_CROUCH = DUMMY_ACTION_CROUCH
DummySettings.DUMMY_ACTION_RUNTIME_FIELDS = {
    "DummyActionType",
    "JumpType",
    "JumpWeight_Front",
    "JumpWeight_Virtical",
    "JumpWeight_Back",
    "CpuLevel"
}

local _tf_dummy_status_cache = nil
local function get_tf_dummy_status()
    if _tf_dummy_status_cache then return _tf_dummy_status_cache end
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local dict = tm:get_field("_tfFuncs")
        if not dict then return end
        local entries = dict:get_field("_entries")
        if not entries then return end
        local count = entries:call("get_Count")
        for i = 0, count - 1 do
            local entry = entries:call("get_Item", i)
            if entry then
                local val = entry:get_field("value")
                if val and val:get_type_definition():get_full_name():find("tf_DummyStatus") then
                    _tf_dummy_status_cache = val
                    return
                end
            end
        end
    end)
    return _tf_dummy_status_cache
end

function DummySettings.set_action_type(action_type, jump_type, resolve_random, raw_settings)
    local applied_jump_type = jump_type
    local was_random = false
    if resolve_random == true then
        applied_jump_type, was_random =
            TrainingEnvironment.resolve_runtime_jump_type(jump_type)
    end
    trial_state._resolved_dummy_jump_type = was_random and applied_jump_type or nil

    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        if not tData then return end
        local ds = tData:get_field("DummyStatus")
        if not ds then return end
        local dd = ds:get_field("DummyData")
        if not dd then return end
        dd.DummyActionType = action_type
        if applied_jump_type ~= nil then
            dd.JumpType = applied_jump_type
        elseif action_type ~= DUMMY_ACTION_STAND then
            dd.JumpType = 0
        end
        if type(raw_settings) == "table" then
            for _, field_name in ipairs(DummySettings.DUMMY_ACTION_RUNTIME_FIELDS) do
                if field_name ~= "DummyActionType"
                    and field_name ~= "JumpType"
                    and raw_settings[field_name] ~= nil then
                    dd[field_name] = raw_settings[field_name]
                end
            end
        end
    end)

    local td = get_tf_dummy_status()
    if td then
        pcall(function() td:call("bApply") end)
    end
end

function DummySettings.read_action_settings()
    local result = {
        action_type = DUMMY_ACTION_STAND,
        jump_type = TrainingEnvironment.DUMMY_JUMP.VERTICAL
    }
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        if not tData then return end
        local ds = tData:get_field("DummyStatus")
        if not ds then return end
        local dd = ds:get_field("DummyData")
        if not dd then return end
        for _, field_name in ipairs(DummySettings.DUMMY_ACTION_RUNTIME_FIELDS) do
            result[field_name] = dd[field_name]
        end
        result.action_type = result.DummyActionType or DUMMY_ACTION_STAND
        result.jump_type = result.JumpType
            or TrainingEnvironment.DUMMY_JUMP.VERTICAL
    end)
    return result
end

function DummySettings.read_action_state()
    local result = DummySettings.read_action_settings()
    return result.action_type, result.jump_type
end

function DummySettings.save_action_type()
    if trial_state._saved_dummy_action_settings == nil then
        trial_state._saved_dummy_action_settings = DummySettings.read_action_settings()
    end
end

function DummySettings.restore_action_type()
    local saved = trial_state._saved_dummy_action_settings
    if type(saved) == "table" then
        DummySettings.set_action_type(saved.action_type, saved.jump_type, false, saved)
        trial_state._saved_dummy_action_settings = nil
    end
end

DummySettings.TRIAL_DEFENSE_FIELDS = {
    "QS_Type",
    "GD_Type",
    "DR_Type",
    "DP_Type",
    "QS_Weight",
    "GD_Weight",
    "DR_Guard_Weight",
    "DR_Getup_Weight",
    "DR_No_Weight",
    "DR_DelayFrame",
    "DR_DelayCount"
}

local tf_defense_system_cache = nil
function DummySettings.get_tf_defense_system()
    if tf_defense_system_cache then return tf_defense_system_cache end
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local dict = tm:get_field("_tfFuncs")
        if not dict then return end
        local entries = dict:get_field("_entries")
        if not entries then return end
        local count = entries:call("get_Count")
        for i = 0, count - 1 do
            local entry = entries:call("get_Item", i)
            local val = entry and entry:get_field("value") or nil
            if val then
                local td = val:get_type_definition()
                local full_name = td and td:get_full_name() or ""
                if full_name:find("tf_DefenseSystem") then
                    tf_defense_system_cache = val
                    return
                end
            end
        end
    end)
    return tf_defense_system_cache
end

function DummySettings.get_trial_defense_objects(player_idx)
    local out = { player_idx = tonumber(player_idx or 1) or 1 }
    if out.player_idx ~= 1 then out.player_idx = 0 end
    pcall(function()
        out.tm = sdk.get_managed_singleton("app.training.TrainingManager")
        out.defense_func = out.tm and out.tm:call("get_DefenseFunc") or nil
        local t_data = out.tm and out.tm:get_field("_tData") or nil
        out.defense_system = t_data and t_data:get_field("DefenseSystem") or nil
        if out.defense_system then
            out.dummy_data = out.defense_system.DummyData
            out.player_data = out.defense_system.PlayerDatas and out.defense_system.PlayerDatas[out.player_idx] or nil
        end
        out.tf_defense = DummySettings.get_tf_defense_system()
    end)
    return out
end

function DummySettings.copy_trial_defense_fields(obj)
    local fields = {}
    if not obj then return fields end
    for _, field_name in ipairs(DummySettings.TRIAL_DEFENSE_FIELDS) do
        local ok, value = pcall(function() return obj[field_name] end)
        if ok and value ~= nil then fields[field_name] = value end
    end
    return fields
end

function DummySettings.capture_training_defense_environment(env)
    if type(env) ~= "table" then return env end
    local objects = DummySettings.get_trial_defense_objects(1)
    local fields = DummySettings.copy_trial_defense_fields(objects.dummy_data)
    env.dummy_drive_parry_type = fields.DP_Type
    env.dummy_drive_reversal_type = fields.DR_Type
    env.dummy_drive_reversal_delay = fields.DR_DelayFrame
    env.dummy_drive_reversal_count =
        TrainingEnvironment.drive_reversal_count_from_runtime(
            fields.DR_DelayCount
        )
    env.dummy_drive_reversal_weight_none = fields.DR_No_Weight
    env.dummy_drive_reversal_weight_guard = fields.DR_Guard_Weight
    env.dummy_drive_reversal_weight_wakeup = fields.DR_Getup_Weight
    env.dummy_throw_escape_type = fields.GD_Type
    env.dummy_throw_escape_weight = fields.GD_Weight
    env.dummy_wakeup_type = fields.QS_Type
    env.dummy_wakeup_weight = fields.QS_Weight
    return env
end

function DummySettings.write_trial_defense_fields(obj, fields)
    if not obj then return end
    for field_name, value in pairs(fields or {}) do
        pcall(function() obj[field_name] = value end)
    end
end

function DummySettings.backup_trial_defense_settings(defender_idx)
    defender_idx = tonumber(defender_idx or 1) or 1
    if defender_idx ~= 1 then defender_idx = 0 end
    if type(trial_state._trial_defense_backup) == "table" then return end
    local objects = DummySettings.get_trial_defense_objects(defender_idx)
    trial_state._trial_defense_backup = {
        player_idx = defender_idx,
        dummy = DummySettings.copy_trial_defense_fields(objects.dummy_data),
        player = DummySettings.copy_trial_defense_fields(objects.player_data)
    }
end

function DummySettings.restore_trial_defense_settings()
    local backup = trial_state._trial_defense_backup
    if type(backup) ~= "table" then return false end
    local objects = DummySettings.get_trial_defense_objects(backup.player_idx)
    DummySettings.write_trial_defense_fields(objects.dummy_data, backup.dummy)
    DummySettings.write_trial_defense_fields(objects.player_data, backup.player)
    if objects.tf_defense then pcall(function() objects.tf_defense:call("bApply") end) end
    trial_state._trial_defense_backup = nil
    return true
end

function DummySettings.apply_trial_defense_cleanup()
    local attacker_idx = tonumber(trial_state.playing_player or 0) or 0
    if attacker_idx ~= 1 then attacker_idx = 0 end
    local defender_idx = 1 - attacker_idx
    DummySettings.backup_trial_defense_settings(defender_idx)

    local objects = DummySettings.get_trial_defense_objects(defender_idx)
    if objects.defense_func then
        pcall(function() objects.defense_func:call("SetDriveParry", defender_idx, 0) end)
        pcall(function() objects.defense_func:call("ChangeDRType", defender_idx, 0) end)
        pcall(function() objects.defense_func:call("SetDR_Guard_Weight", defender_idx, 0) end)
        pcall(function() objects.defense_func:call("SetDR_Getup_Weight", defender_idx, 0) end)
        pcall(function() objects.defense_func:call("SetDR_No_Weight", defender_idx, 100) end)
    end

    local disabled = {
        DR_Type = 0,
        DP_Type = 0,
        DR_Guard_Weight = 0,
        DR_Getup_Weight = 0,
        DR_No_Weight = 100
    }
    DummySettings.write_trial_defense_fields(objects.dummy_data, disabled)
    DummySettings.write_trial_defense_fields(objects.player_data, disabled)
    if objects.tf_defense then pcall(function() objects.tf_defense:call("bApply") end) end
end

function DummySettings.apply_recorded_defense_settings(first_step)
    local attacker_idx = tonumber(trial_state.playing_player or 0) or 0
    if attacker_idx ~= 1 then attacker_idx = 0 end
    local defender_idx = 1 - attacker_idx
    if not TrainingEnvironment.has_recorded_defense_settings(first_step) then
        DummySettings.apply_trial_defense_cleanup()
        return "legacy_cleanup"
    end

    DummySettings.backup_trial_defense_settings(defender_idx)
    local settings =
        TrainingEnvironment.resolve_recorded_settings(first_step)
    local fields = {
        QS_Type = settings.dummy_wakeup_type,
        QS_Weight = settings.dummy_wakeup_weight,
        GD_Type = settings.dummy_throw_escape_type,
        GD_Weight = settings.dummy_throw_escape_weight,
        DP_Type = settings.dummy_drive_parry_type,
        DR_Type = settings.dummy_drive_reversal_type,
        DR_DelayFrame = settings.dummy_drive_reversal_delay,
        DR_DelayCount =
            TrainingEnvironment.drive_reversal_count_to_runtime(
                settings.dummy_drive_reversal_count
            ),
        DR_No_Weight = settings.dummy_drive_reversal_weight_none,
        DR_Guard_Weight = settings.dummy_drive_reversal_weight_guard,
        DR_Getup_Weight = settings.dummy_drive_reversal_weight_wakeup,
    }
    local objects = DummySettings.get_trial_defense_objects(defender_idx)
    DummySettings.write_trial_defense_fields(objects.dummy_data, fields)
    DummySettings.write_trial_defense_fields(objects.player_data, fields)
    if objects.tf_defense then pcall(function() objects.tf_defense:call("bApply") end) end
    return "recorded"
end

function DummySettings.trial_dummy_guard_type()
    local first_step = trial_state.sequence and trial_state.sequence[1]
    local fallback = type(trial_state._saved_guard_settings) == "table"
        and trial_state._saved_guard_settings.guard_type
        or nil
    if fallback == nil then fallback = DummySettings.read_guard_type() end
    local guard_type, source = TrainingEnvironment.resolve_dummy_guard_type(first_step, fallback)
    trial_state._dummy_guard_type_source = source
    return guard_type
end

function DummySettings.trial_dummy_guard_count()
    local first_step = trial_state.sequence and trial_state.sequence[1]
    local fallback = type(trial_state._saved_guard_settings) == "table"
        and trial_state._saved_guard_settings.guard_count
        or nil
    if fallback == nil then fallback = select(2, DummySettings.read_guard_type()) end
    local guard_count, source =
        TrainingEnvironment.resolve_dummy_guard_count(first_step, fallback)
    trial_state._dummy_guard_count_source = source
    return guard_count
end

return DummySettings
