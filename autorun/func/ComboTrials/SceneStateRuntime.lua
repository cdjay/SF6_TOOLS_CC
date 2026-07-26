local SceneState = require("func/ComboTrials/SceneState")
local GS = require("func/GameState")

local SceneStateRuntime = {
    name = "ComboTrials.SceneStateRuntime",
}

local battle_type = sdk.find_type_definition("gBattle")

local function normalized_point(value, maximum)
    local number = tonumber(value)
    if number == nil then return nil end
    number = math.floor(number + 0.5)
    if number < 0 then number = 0 end
    if maximum and number > maximum then number = maximum end
    return number
end

local function player_object(player_index)
    return player_index == 1 and GS.p2 or GS.p1
end

local function battle_team(player_index)
    local team = nil
    pcall(function()
        local battle = battle_type and battle_type:get_field("Team"):get_data(nil)
        team = battle and battle.mcTeam and battle.mcTeam[player_index] or nil
    end)
    return team
end

local function copy_fields(object, field_names)
    local result = {}
    if not object then return result end
    for _, field_name in ipairs(field_names or {}) do
        local ok, value = pcall(function() return object[field_name] end)
        if ok and value ~= nil then result[field_name] = value end
    end
    return result
end

local function save_parameter_fields_once(trial_state, storage_name, player_index, params, field_names)
    if not params then return end
    if type(trial_state[storage_name]) ~= "table" then trial_state[storage_name] = {} end
    if trial_state[storage_name][player_index] ~= nil then return end
    local saved = copy_fields(params, field_names)
    if next(saved) ~= nil then trial_state[storage_name][player_index] = saved end
end

local function read_live_hp(player)
    if type(read_player_hp_snapshot) == "function" then
        return read_player_hp_snapshot(player)
    end
    if not player then return nil end
    local snapshot = {}
    pcall(function() snapshot.current_hp = tonumber(player.vital_new) end)
    pcall(function() snapshot.max_hp = tonumber(player.vital_max) end)
    pcall(function() snapshot.heal_hp = tonumber(player.heal_new) end)
    return snapshot.current_hp ~= nil and snapshot or nil
end

local function save_live_resources_once(trial_state, player_index)
    if type(trial_state._scene_live_resource_backup) ~= "table" then
        trial_state._scene_live_resource_backup = {}
    end
    if trial_state._scene_live_resource_backup[player_index] ~= nil then return end

    local player = player_object(player_index)
    local team = battle_team(player_index)
    local backup = {
        hp = read_live_hp(player),
    }
    pcall(function() backup.drive = tonumber(player and player.focus_new) end)
    pcall(function() backup.super = tonumber(team and team.mSuperGauge) end)
    trial_state._scene_live_resource_backup[player_index] = backup
end

local function resource_values(role)
    local resources = SceneState.resources(role)
    return {
        hp = normalized_point(type(resources) == "table" and resources.hp),
        drive = normalized_point(
            type(resources) == "table" and resources.drive,
            60000
        ),
        super = normalized_point(
            type(resources) == "table" and resources.super,
            30000
        ),
    }
end

local function status_values(role)
    local status = SceneState.status(role)
    local burnout = type(status) == "table" and status.burnout or nil
    return {
        burnout = burnout,
        stunned = type(status) == "table" and status.stunned or nil,
        stance = type(status) == "table" and status.stance or nil,
    }
end

local function write_live_resources(player_index, values)
    local player = player_object(player_index)
    local team = battle_team(player_index)

    if player and values.hp ~= nil then
        pcall(function() player.vital_new = values.hp end)
        pcall(function() player.vital_old = values.hp end)
        pcall(function() player.heal_new = values.hp end)
        pcall(function() player.heal_old = values.hp end)
    end
    if player and values.drive ~= nil then
        pcall(function() player.focus_new = values.drive end)
        pcall(function() player.focus_old = values.drive end)
    end
    if team and values.super ~= nil then
        pcall(function() team.mSuperGauge = values.super end)
    end
end

local function write_live_status(player_index, status)
    if type(status) ~= "table" or status.burnout ~= false then return end
    local player = player_object(player_index)
    if not player then return end

    -- Is_DG_Break controls the next training refresh, but it does not always
    -- cancel an already-running burnout state on the live battle object.
    -- Recover first, then write the exact scene drive value afterwards.
    pcall(function()
        local type_definition = player:get_type_definition()
        if type_definition and type_definition:get_method("focus_full_recover") then
            player:call("focus_full_recover")
        end
    end)
    pcall(function() player.focus_wait = 0 end)
end

local function apply_training_settings(role, values, status, trial_state)
    local get_objects = rawget(_G, "get_training_parameter_probe_objects")
    if type(get_objects) ~= "function" then return false, nil end
    local objects = get_objects(role.player_index)
    local params = type(objects) == "table" and objects.player_params or nil
    if not params then return false, objects end

    local changed = false
    local player = player_object(role.player_index)

    if values.hp ~= nil then
        local max_hp = nil
        pcall(function() max_hp = tonumber(player and player.vital_max) end)
        local vital_point = max_hp and max_hp > 0
            and math.max(0, math.min(100, math.floor(values.hp * 100 / max_hp + 0.5)))
            or nil
        if vital_point ~= nil then
            if type(ct_hp_backup_training_setting_once) == "function" then
                ct_hp_backup_training_setting_once(role.player_index, "scene_state")
            end
            pcall(function() params.Vital_Point = vital_point end)
            if objects.param_func then
                pcall(function() objects.param_func:call("SetVitalPoint", role.player_index, vital_point) end)
            end
            changed = true
        end
    end

    if values.drive ~= nil or type(status.burnout) == "boolean" then
        save_parameter_fields_once(
            trial_state,
            "_saved_drive_settings",
            role.player_index,
            params,
            DRIVE_SETTING_FIELDS
        )
        if values.drive ~= nil then
            local stock = math.floor((values.drive + 5000) / 10000)
            pcall(function() params.DG_Point = values.drive end)
            pcall(function() params.DG_Stock = stock end)
            if objects.param_func then
                pcall(function() objects.param_func:call("SetDGDetailPoint", role.player_index, values.drive) end)
                pcall(function() objects.param_func:call("SetDGStock", role.player_index, stock) end)
            end
        end
        if type(status.burnout) == "boolean" then
            pcall(function() params.Is_DG_Break = status.burnout end)
            if status.burnout == false then
                pcall(function() params.Is_DG_Recovery_Timer = false end)
                pcall(function() params.DG_Timer = 0 end)
            end
        end
        changed = true
    end

    if values.super ~= nil then
        save_parameter_fields_once(
            trial_state,
            "_saved_super_settings",
            role.player_index,
            params,
            SUPER_SETTING_FIELDS
        )
        pcall(function() params.SA_Point = values.super end)
        pcall(function() params.SA_Stock = math.floor((values.super + 5000) / 10000) end)
        changed = true
    end

    return changed, objects
end

function SceneStateRuntime.apply(first_step, playing_player, trial_state, apply_refresh_settings)
    if type(first_step) ~= "table" or type(trial_state) ~= "table" then return false end
    local roles = SceneState.resolve_roles(first_step, playing_player)
    if not roles then return false end
    local changed = false
    local prepared = {}
    for _, entry in ipairs({
        { role = roles.actor },
        { role = roles.defender },
    }) do
        local values = resource_values(entry.role)
        local status = status_values(entry.role)
        local has_resources = values.hp ~= nil or values.drive ~= nil or values.super ~= nil
        local has_drive_status = type(status.burnout) == "boolean"
        if has_resources or has_drive_status then
            save_live_resources_once(trial_state, entry.role.player_index)
        end
        prepared[#prepared + 1] = {
            role = entry.role,
            values = values,
            status = status,
            has_resources = has_resources,
            has_drive_status = has_drive_status,
        }
    end

    -- Populate both players' parameter records before applying them. Calling
    -- bApply once per player can latch the first refresh and discard P2.
    local settings_changed = false
    local refresh_objects = nil
    if apply_refresh_settings == true then
        for _, entry in ipairs(prepared) do
            if entry.has_resources or entry.has_drive_status then
                local entry_changed, objects = apply_training_settings(
                    entry.role,
                    entry.values,
                    entry.status,
                    trial_state
                )
                settings_changed = settings_changed or entry_changed
                refresh_objects = objects or refresh_objects
            end
        end
        if settings_changed then
            if refresh_objects and refresh_objects.tf_ps then
                pcall(function() refresh_objects.tf_ps:call("bApply") end)
            end
            local tm = refresh_objects and refresh_objects.tm
                or sdk.get_managed_singleton("app.training.TrainingManager")
            if tm then pcall(function() tm._IsReqRefresh = true end) end
        end
    end

    for _, entry in ipairs(prepared) do
        if entry.has_resources or entry.has_drive_status then
            write_live_status(entry.role.player_index, entry.status)
            write_live_resources(entry.role.player_index, entry.values)
            changed = true
        end

        if entry.status.stunned == true then
            trial_state._scene_status_unapplied = trial_state._scene_status_unapplied or {}
            trial_state._scene_status_unapplied[entry.role.player_index] = {
                stunned = true,
                reason = "portable_scene_cannot_force_action_state",
            }
        end
    end

    return changed
end

function SceneStateRuntime.restore_live_resources(trial_state)
    if type(trial_state) ~= "table" then return false end
    local backups = trial_state._scene_live_resource_backup
    if type(backups) ~= "table" then
        trial_state._scene_status_unapplied = nil
        return false
    end

    for player_index, backup in pairs(backups) do
        local index = tonumber(player_index) == 1 and 1 or 0
        local player = player_object(index)
        local team = battle_team(index)
        local hp = type(backup) == "table" and backup.hp or nil
        if player and type(hp) == "table" and hp.current_hp ~= nil then
            pcall(function() player.vital_new = hp.current_hp end)
            pcall(function() player.vital_old = hp.current_hp end)
            pcall(function() player.heal_new = hp.heal_hp or hp.current_hp end)
            pcall(function() player.heal_old = hp.heal_hp or hp.current_hp end)
        end
        if player and backup.drive ~= nil then
            pcall(function() player.focus_new = backup.drive end)
            pcall(function() player.focus_old = backup.drive end)
        end
        if team and backup.super ~= nil then
            pcall(function() team.mSuperGauge = backup.super end)
        end
    end

    trial_state._scene_live_resource_backup = nil
    trial_state._scene_status_unapplied = nil
    return true
end

return SceneStateRuntime
