local GS = require("func/GameState")
local SceneState = require("func/ComboTrials/SceneState")
local SceneStateRuntime = require("func/ComboTrials/SceneStateRuntime")

local HpVital = {
    name = "ComboTrials.HpVital",
}

local trial_state = nil
local file_system = nil
local json_api = nil
local dev_test_state = nil
local debug_path = nil
local get_engine_frame_count = nil
local is_dev_test_enabled = nil

local function current_engine_frame_count()
    return get_engine_frame_count and get_engine_frame_count() or 0
end

function HpVital.init(deps)
    deps = deps or {}
    trial_state = deps.trial_state
    file_system = deps.file_system
    json_api = deps.json
    dev_test_state = deps.dev_test_state
    debug_path = deps.debug_path
    get_engine_frame_count = deps.get_engine_frame_count
    is_dev_test_enabled = deps.is_dev_test_enabled or function() return false end
end

function HpVital.normalize_hp_value(value)
    local n = tonumber(value)
    if n == nil then return nil end
    return math.floor(n + 0.5)
end

function HpVital.read_player_hp_snapshot(player)
    if not player then return nil end
    local current_hp, max_hp, heal_hp = nil, nil, nil
    pcall(function() current_hp = HpVital.normalize_hp_value(player.vital_new) end)
    pcall(function() max_hp = HpVital.normalize_hp_value(player.vital_max) end)
    pcall(function() heal_hp = HpVital.normalize_hp_value(player.heal_new) end)
    if current_hp == nil then return nil end
    if max_hp == nil or max_hp <= 0 then max_hp = current_hp end

    local snapshot = {
        current_hp = current_hp,
        max_hp = max_hp
    }
    if heal_hp ~= nil then snapshot.heal_hp = heal_hp end
    return snapshot
end

function HpVital.clear_trial_vital_state()
    trial_state._pending_victim_hp = nil
    trial_state._pending_attacker_hp = nil
    trial_state._hp_inject_frames = 0
    trial_state._saved_vital_p1 = nil
    trial_state._saved_vital_p2 = nil
end

-- Combo playback must use the training room's current health settings.
function HpVital.apply_trial_vital()
    HpVital.clear_trial_vital_state()
end

function HpVital.reinject_trial_vital()
    HpVital.clear_trial_vital_state()
end

HpVital.DRIVE_SETTING_FIELDS = {
    "DG_Type",
    "DG_Stock",
    "DG_Point",
    "Is_DG_Point_Lock",
    "Is_DG_Break",
    "Is_DG_Recovery_Timer",
    "DG_Timer"
}

HpVital.SUPER_SETTING_FIELDS = {
    "SA_Type",
    "SA_Stock",
    "SA_Point",
    "Is_SA_Point_Lock",
    "Is_SA_No_Recovery",
    "Is_SA_Recovery_Timer",
    "SA_Timer"
}

function HpVital.restore_trial_vital(skip_hp_setting_restore)
    HpVital.clear_trial_vital_state()
    if skip_hp_setting_restore ~= true and type(HpVital.restore_hp_training_setting_if_needed) == "function" then
        HpVital.restore_hp_training_setting_if_needed("HpVital.restore_trial_vital", trial_state.playing_player)
    end

    local saved_drive_settings = trial_state._saved_drive_settings
    local saved_super_settings = trial_state._saved_super_settings
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    local changed = false
    local t_data = tm and tm:get_field("_tData")
    local parameter_setting = t_data and t_data:get_field("ParameterSetting")
    local player_datas = parameter_setting and parameter_setting.PlayerDatas

    if player_datas then
        for idx, settings in pairs(type(saved_drive_settings) == "table" and saved_drive_settings or {}) do
            local params = player_datas[idx]
            if params and type(settings) == "table" then
                for _, field_name in ipairs(HpVital.DRIVE_SETTING_FIELDS) do
                    if settings[field_name] ~= nil then
                        params[field_name] = settings[field_name]
                        changed = true
                    end
                end
            end
        end

        for idx, settings in pairs(type(saved_super_settings) == "table" and saved_super_settings or {}) do
            local params = player_datas[idx]
            if params and type(settings) == "table" then
                for _, field_name in ipairs(HpVital.SUPER_SETTING_FIELDS) do
                    if settings[field_name] ~= nil then
                        params[field_name] = settings[field_name]
                        changed = true
                    end
                end
            end
        end
    end

    trial_state._saved_drive_settings = nil
    trial_state._saved_super_settings = nil
    if changed then tm._IsReqRefresh = true end
    SceneStateRuntime.restore_live_resources(trial_state)
end

function HpVital.read_player_hp_fields_for_debug(player)
    if not player then return { missing_player = true } end
    local out = {}
    local ok
    ok, out.vital_new = pcall(function() return player.vital_new end)
    out.vital_new_ok = ok == true
    ok, out.vital_old = pcall(function() return player.vital_old end)
    out.vital_old_ok = ok == true
    ok, out.heal_new = pcall(function() return player.heal_new end)
    out.heal_new_ok = ok == true
    ok, out.vital_max = pcall(function() return player.vital_max end)
    out.vital_max_ok = ok == true
    return out
end

HpVital.VITAL_PARAM_FIELDS = {
    "Vital_Type",
    "Vital_Point",
    "Vital_Point_Type",
    "Vital_Timer",
    "Is_Vital_Infinity",
    "Is_Vital_No_Recovery",
    "Is_Vital_Recovery_Timer",
    "Is_KO",
    "Is_Point_Lock"
}

function HpVital.read_player_vital_params_for_debug(player_params)
    if not player_params then return { missing_player_params = true } end
    local out = {}
    for _, field_name in ipairs(HpVital.VITAL_PARAM_FIELDS) do
        local ok, value = pcall(function() return player_params[field_name] end)
        out[field_name] = ok and value or nil
        out[field_name .. "_ok"] = ok == true
    end
    return out
end

function HpVital.hp_snapshot_to_vital_point(snapshot)
    if type(snapshot) ~= "table" then return nil end
    local current_hp = tonumber(snapshot.current_hp)
    if current_hp == nil then return nil end
    local max_hp = tonumber(snapshot.max_hp)
    local point = nil
    if max_hp ~= nil and max_hp > 0 then
        point = math.floor((current_hp * 100 / max_hp) + 0.5)
    elseif current_hp >= 0 and current_hp <= 100 then
        point = math.floor(current_hp + 0.5)
    end
    if point == nil then return nil end
    if point < 0 then point = 0 end
    if point > 100 then point = 100 end
    return point
end

local tf_parameter_setting_cache = nil
function HpVital.get_tf_parameter_setting()
    if tf_parameter_setting_cache then return tf_parameter_setting_cache end
    local fallback = nil
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local dict = tm:get_field("_tfFuncs")
        if not dict then return end
        local entries = dict:get_field("_entries")
        if not entries then return end
        pcall(function()
            local entry = entries:call("get_Item", 6)
            fallback = entry and entry:get_field("value") or nil
        end)
        local count = entries:call("get_Count")
        for i = 0, count - 1 do
            local entry = entries:call("get_Item", i)
            local val = entry and entry:get_field("value") or nil
            if val then
                local td = val:get_type_definition()
                local full_name = td and td:get_full_name() or ""
                if full_name:find("tf_ParameterSetting") or full_name:find("ParameterSetting") then
                    tf_parameter_setting_cache = val
                    return
                end
            end
        end
    end)
    tf_parameter_setting_cache = tf_parameter_setting_cache or fallback
    return tf_parameter_setting_cache
end

function HpVital.describe_re_object_for_debug(obj)
    if not obj then return nil end
    local ok, name = pcall(function()
        local td = obj:get_type_definition()
        return td and td:get_full_name() or nil
    end)
    return ok and name or nil
end

function HpVital.get_training_parameter_probe_objects(attacker_idx)
    local out = {
        attacker_idx = attacker_idx,
        attacker_label = attacker_idx == 1 and "p2" or "p1"
    }
    pcall(function()
        out.tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not out.tm then return end
        out.training_data = out.tm:get_field("_tData")
        if not out.training_data then return end
        out.parameter_setting = out.training_data:get_field("ParameterSetting")
        if out.parameter_setting then
            pcall(function() out.param_func = out.parameter_setting:get_field("ParamFunc") end)
            if not out.param_func then pcall(function() out.param_func = out.parameter_setting.ParamFunc end) end
            local player_datas = out.parameter_setting.PlayerDatas
            out.player_params = player_datas and player_datas[attacker_idx] or nil
        end
        if not out.param_func then
            pcall(function() out.param_func = out.training_data:get_field("ParamFunc") end)
            if not out.param_func then pcall(function() out.param_func = out.training_data.ParamFunc end) end
        end
        out.tf_ps = HpVital.get_tf_parameter_setting()
    end)
    return out
end

function HpVital.ct_hp_copy_vital_setting_fields(player_params)
    local fields = {}
    if not player_params then return fields end
    for _, field_name in ipairs(HpVital.VITAL_PARAM_FIELDS) do
        local ok, value = pcall(function() return player_params[field_name] end)
        if ok and value ~= nil then fields[field_name] = value end
    end
    return fields
end

function HpVital.ct_hp_backup_training_setting_once(player_idx, phase)
    player_idx = tonumber(player_idx or 0) or 0
    if player_idx ~= 1 then player_idx = 0 end

    if type(trial_state._hp_training_setting_backup) ~= "table" then
        trial_state._hp_training_setting_backup = {
            has_backup = false,
            players = {}
        }
    end

    local backup = trial_state._hp_training_setting_backup
    backup.players = backup.players or {}
    if type(backup.players[player_idx]) == "table" then
        return backup.players[player_idx]
    end

    local objects = HpVital.get_training_parameter_probe_objects(player_idx)
    local fields = HpVital.ct_hp_copy_vital_setting_fields(objects.player_params)
    local item = {
        player_index = player_idx,
        player_side = player_idx == 1 and "p2" or "p1",
        fields = fields,
        has_backup = next(fields) ~= nil,
        backup_source_phase = phase,
        before = HpVital.read_player_vital_params_for_debug(objects.player_params)
    }
    backup.players[player_idx] = item
    backup.has_backup = backup.has_backup or item.has_backup
    backup.player_index = backup.player_index or player_idx
    backup.player_side = backup.player_side or item.player_side
    backup.fields = backup.fields or fields
    backup.backup_source_phase = backup.backup_source_phase or phase
    return item
end

function HpVital.ct_hp_write_vital_setting_fields(player_params, fields)
    local result = { ok = true, errors = {} }
    if not player_params then
        result.ok = false
        result.errors.missing_player_params = true
        return result
    end
    for field_name, value in pairs(fields or {}) do
        local ok, err = pcall(function() player_params[field_name] = value end)
        if not ok then
            result.ok = false
            result.errors[field_name] = tostring(err)
        end
    end
    return result
end

function HpVital.ct_hp_default_full_vital_fields()
    return {
        Vital_Point = 100,
        Is_Vital_Infinity = false,
        Is_Vital_No_Recovery = false,
        Is_Vital_Recovery_Timer = false,
        Is_KO = false,
        Is_Point_Lock = false
    }
end

function HpVital.restore_hp_training_setting_if_needed(reason, preferred_player_idx)
    local backup = trial_state._hp_training_setting_backup
    local had_backup = type(backup) == "table" and backup.has_backup == true and type(backup.players) == "table"
    local applied = trial_state._hp_snapshot_applied_current_session == true
    local debug = {
        called = false,
        reason = reason,
        had_backup = had_backup,
        hp_snapshot_applied_current_session = applied,
        switching_from_hp_snapshot_to_plain_trial = (reason or ""):find("plain_trial", 1, true) ~= nil and (had_backup or applied),
        restores = {}
    }

    if not had_backup and not applied then
        debug.skip_reason = "no_hp_snapshot_state"
        trial_state._hp_setting_restore_debug = debug
        if type(HpVital.write_hp_restore_debug_dump) == "function" then
            pcall(HpVital.write_hp_restore_debug_dump, "hp_setting_restore_skipped", { hp_setting_restore = debug })
        end
        return debug
    end

    debug.called = true
    local restored_any = false
    local bapply_target = nil

    if had_backup then
        for player_idx, item in pairs(backup.players) do
            local idx = tonumber(player_idx) or tonumber(item.player_index or 0) or 0
            if idx ~= 1 then idx = 0 end
            local objects = HpVital.get_training_parameter_probe_objects(idx)
            local restore_item = {
                player_index = idx,
                player_side = idx == 1 and "p2" or "p1",
                fields = item.fields or {},
                before = HpVital.read_player_vital_params_for_debug(objects.player_params)
            }
            local write_result = HpVital.ct_hp_write_vital_setting_fields(objects.player_params, item.fields or {})
            restore_item.write_ok = write_result.ok == true
            restore_item.write_errors = write_result.errors
            restore_item.after = HpVital.read_player_vital_params_for_debug(objects.player_params)
            table.insert(debug.restores, restore_item)
            debug.player_index = debug.player_index or idx
            debug.player_side = debug.player_side or restore_item.player_side
            debug.fields = debug.fields or restore_item.fields
            debug.before = debug.before or restore_item.before
            debug.after = debug.after or restore_item.after
            restored_any = true
            bapply_target = bapply_target or objects.tf_ps
        end
    else
        local idx = tonumber(preferred_player_idx or trial_state.playing_player or 0) or 0
        if idx ~= 1 then idx = 0 end
        local objects = HpVital.get_training_parameter_probe_objects(idx)
        local fallback_fields = HpVital.ct_hp_default_full_vital_fields()
        local restore_item = {
            player_index = idx,
            player_side = idx == 1 and "p2" or "p1",
            fallback_full_hp = true,
            fields = fallback_fields,
            before = HpVital.read_player_vital_params_for_debug(objects.player_params)
        }
        local write_result = HpVital.ct_hp_write_vital_setting_fields(objects.player_params, fallback_fields)
        restore_item.write_ok = write_result.ok == true
        restore_item.write_errors = write_result.errors
        restore_item.after = HpVital.read_player_vital_params_for_debug(objects.player_params)
        table.insert(debug.restores, restore_item)
        debug.player_index = idx
        debug.player_side = restore_item.player_side
        debug.fields = fallback_fields
        debug.before = restore_item.before
        debug.after = restore_item.after
        restored_any = true
        bapply_target = objects.tf_ps
    end

    if bapply_target then
        local bapply_ok, bapply_err = pcall(function()
            bapply_target:call("bApply")
        end)
        debug.bapply_called = true
        debug.bapply_ok = bapply_ok == true
        if not bapply_ok then debug.bapply_error = tostring(bapply_err) end
    else
        debug.bapply_called = false
        debug.bapply_ok = false
        debug.bapply_error = "missing_tf_parameter_setting"
    end

    debug.restored_any = restored_any
    if debug.bapply_ok == true then
        trial_state._hp_snapshot_applied_current_session = false
        trial_state._hp_training_setting_backup = nil
        debug.backup_cleared = true
    else
        debug.backup_cleared = false
    end
    trial_state._hp_setting_restore_debug = debug
    if type(HpVital.write_hp_restore_debug_dump) == "function" then
        pcall(HpVital.write_hp_restore_debug_dump, "hp_setting_restore", { hp_setting_restore = debug })
    end
    return debug
end

function HpVital.current_trial_title()
    local first = trial_state.sequence and trial_state.sequence[1]
    if type(first) ~= "table" then return nil end
    local xt_meta = type(first._xt_meta) == "table" and first._xt_meta or nil
    if xt_meta and xt_meta.title then return xt_meta.title end
    local wtt_meta = type(first._wtt_cn_meta) == "table" and first._wtt_cn_meta or nil
    if wtt_meta and wtt_meta.title then return wtt_meta.title end
    return nil
end

function HpVital.build_hp_restore_debug_dump(phase, extra)
    local first = trial_state.sequence and trial_state.sequence[1]
    local read_snapshot, read_skip_reason = HpVital.read_actor_scene_hp()
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    local target_idx = trial_state._hp_restore and trial_state._hp_restore.target_player or trial_state.playing_player or 0
    local target_player = target_idx == 1 and GS.p2 or GS.p1
    local param_probe = HpVital.get_training_parameter_probe_objects(target_idx)
    local loaded_title = HpVital.current_trial_title()
    local runtime_inject = extra and extra.runtime_inject or nil
    local dump = {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        frame = current_engine_frame_count() or 0,
        phase = phase,
        dev_test = dev_test_state,
        trial_file = trial_state.current_file or trial_state.current_file_path,
        trial_filename = trial_state.current_file_name,
        trial_title = loaded_title,
        loaded_trial = {
            loaded_title = loaded_title,
            loaded_filename = trial_state.current_file_name,
            sequence_length = trial_state.sequence and #trial_state.sequence or 0,
            first_step_id = type(first) == "table" and first.id or nil,
            first_step_motion = type(first) == "table" and first.motion or nil,
            first_scene_state = type(first) == "table" and first.scene_state or nil
        },
        playing_player = trial_state.playing_player,
        current_step = trial_state.current_step,
        pending_reinject_settings = trial_state._pending_reinject_settings == true,
        tm_is_req_refresh = tm and tm:get_field("_IsReqRefresh") or nil,
        first_scene_state = type(first) == "table" and first.scene_state or nil,
        read_actor_scene_hp = {
            snapshot = read_snapshot,
            skip_reason = read_skip_reason
        },
        snapshot_parsing = {
            snapshot_found = type(read_snapshot) == "table",
            snapshot_current_hp = read_snapshot and read_snapshot.current_hp or nil,
            snapshot_max_hp = read_snapshot and read_snapshot.max_hp or nil,
            snapshot_heal_hp = read_snapshot and read_snapshot.heal_hp or nil,
            skip_reason = read_skip_reason
        },
        hp_restore_state = trial_state._hp_restore,
        runtime_inject = runtime_inject,
        hp_setting_backup = {
            exists = type(trial_state._hp_training_setting_backup) == "table"
                and trial_state._hp_training_setting_backup.has_backup == true,
            player_index = type(trial_state._hp_training_setting_backup) == "table"
                and trial_state._hp_training_setting_backup.player_index or nil,
            fields = type(trial_state._hp_training_setting_backup) == "table"
                and trial_state._hp_training_setting_backup.fields or nil,
            players = type(trial_state._hp_training_setting_backup) == "table"
                and trial_state._hp_training_setting_backup.players or nil
        },
        hp_setting_restore = trial_state._hp_setting_restore_debug,
        hp_snapshot_applied_current_session = trial_state._hp_snapshot_applied_current_session == true,
        switching_from_hp_snapshot_to_plain_trial = trial_state._hp_setting_restore_debug
            and trial_state._hp_setting_restore_debug.switching_from_hp_snapshot_to_plain_trial or false,
        safety = {
            did_call_reset = false,
            did_call_reload = false,
            did_call_start_trial = false,
            did_set_IsReqRefresh = false,
            no_hp_snapshot_skip_old_json = read_snapshot == nil
        },
        target_player = target_idx == 1 and "p2" or "p1",
        target_player_idx = target_idx,
        target_hp_now = HpVital.read_player_hp_fields_for_debug(target_player),
        target_vital_params_now = HpVital.read_player_vital_params_for_debug(param_probe.player_params),
        param_func_exists = param_probe.param_func ~= nil,
        param_func_type = HpVital.describe_re_object_for_debug(param_probe.param_func),
        tf_parameter_setting_exists = param_probe.tf_ps ~= nil,
        tf_parameter_setting_type = HpVital.describe_re_object_for_debug(param_probe.tf_ps)
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do dump[k] = v end
    end
    return dump
end

function HpVital.write_hp_restore_debug_dump(phase, extra)
    if rawget(_G, "CT_HP_RESTORE_TRACE") ~= true and is_dev_test_enabled() ~= true then return end
    local dump = HpVital.build_hp_restore_debug_dump(phase, extra)
    trial_state._hp_restore_debug_file = dump
    pcall(function()
        json_api.dump_file(debug_path, dump)
    end)
end

function HpVital.hp_restore_trace(event)
    if type(event) ~= "table" then return end
    event.frame = current_engine_frame_count() or 0
    trial_state._hp_restore_debug = event
    HpVital.write_hp_restore_debug_dump(event.phase or "trace", { trace_event = event })

    if rawget(_G, "CT_HP_RESTORE_TRACE") ~= true then return end
    local msg = "[HPRestore]"
        .. " phase=" .. tostring(event.phase)
        .. " token=" .. tostring(event.token)
        .. " found=" .. tostring(event.found)
        .. " restored=" .. tostring(event.restored)
        .. " retry=" .. tostring(event.retry_count)
        .. " target=" .. tostring(event.target_player)
        .. " skip=" .. tostring(event.skip_reason)
        .. " refresh_before=" .. tostring(event.refresh_before)
        .. " refresh_after=" .. tostring(event.refresh_after)
        .. " restore_count=" .. tostring(event.restore_count)
    if file_system and file_system.diag_log then
        pcall(file_system.diag_log, msg)
    else
        pcall(print, msg)
    end
end

function HpVital.record_hp_restore_state(state, phase, extra)
    if type(state) ~= "table" then return end
    local event = {
        phase = phase,
        token = state.token,
        found = state.found,
        snapshot = state.snapshot,
        restored = state.restored,
        retry_count = state.retry_count,
        target_player = state.target_player,
        skip_reason = state.skip_reason,
        restore_count = state.restore_count
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do event[k] = v end
    end
    HpVital.hp_restore_trace(event)
end

function HpVital.read_actor_scene_hp()
    local first = trial_state.sequence and trial_state.sequence[1]
    if type(first) ~= "table" then return nil, "missing_first_step" end

    local roles = SceneState.resolve_roles(first, trial_state.playing_player)
    local resources = roles and SceneState.resources(roles.actor) or nil
    local current_hp = HpVital.normalize_hp_value(resources and resources.hp)
    if current_hp == nil then return nil, "missing_actor_scene_hp" end

    local target = roles.actor.player_index == 1 and GS.p2 or GS.p1
    local max_hp = nil
    pcall(function() max_hp = HpVital.normalize_hp_value(target and target.vital_max) end)
    local snapshot = {
        current_hp = current_hp,
        heal_hp = current_hp
    }
    if max_hp and max_hp > 0 then snapshot.max_hp = max_hp end
    return snapshot, nil
end

function HpVital.init_hp_restore_attempt(phase, player_idx)
    trial_state._hp_restore_token = (trial_state._hp_restore_token or 0) + 1
    local snapshot, skip_reason = HpVital.read_actor_scene_hp()
    local found = type(snapshot) == "table"
    local state = {
        token = trial_state._hp_restore_token,
        found = found,
        snapshot = snapshot,
        target_player = tonumber(player_idx or trial_state.playing_player or 0) or 0,
        restored = false,
        finished = not found,
        retry_count = 0,
        max_retries = 5,
        restore_count = 0,
        overwrite_count = 0,
        stable_check_count = 0,
        watch_frames_remaining = 30,
        max_runtime_writes = 1,
        last_phase = phase,
        skip_reason = found and nil or skip_reason
    }
    trial_state._hp_restore = state
    if not found then
        local restore_debug = HpVital.restore_hp_training_setting_if_needed("plain_trial_" .. tostring(phase or "attempt"), state.target_player)
        state.hp_setting_restore = restore_debug
        state.switching_from_hp_snapshot_to_plain_trial = restore_debug and restore_debug.switching_from_hp_snapshot_to_plain_trial or false
    end
    HpVital.record_hp_restore_state(state, phase or "init")
end

function HpVital.is_restore_pending()
    local state = trial_state and trial_state._hp_restore or nil
    return type(state) == "table"
        and state.found == true
        and state.finished ~= true
end

function HpVital.release_restore_for_player_action(phase)
    local state = trial_state and trial_state._hp_restore or nil
    if type(state) ~= "table" or state.finished == true then return false end
    state.finished = true
    state.skip_reason = "player_action_started"
    HpVital.record_hp_restore_state(state, phase or "player_action_started", {
        player_action_started = true,
    })
    return true
end

function HpVital.apply_pending_hp_restore_once(phase)
    local state = trial_state._hp_restore
    if type(state) ~= "table" or state.finished == true then return false end
    state.last_phase = phase
    state.apply_called = true

    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    local refresh_before = tm and tm:get_field("_IsReqRefresh")
    if refresh_before == true then
        state.skip_reason = "training_refresh_active"
        HpVital.record_hp_restore_state(state, phase, { refresh_before = refresh_before })
        return false
    end

    local target = state.target_player == 1 and GS.p2 or GS.p1
    if not target then
        state.retry_count = (state.retry_count or 0) + 1
        state.skip_reason = "missing_player_object"
        if state.retry_count >= (state.max_retries or 5) then
            state.finished = true
            state.skip_reason = "retry_limit_missing_player_object"
        end
        HpVital.record_hp_restore_state(state, phase, { refresh_before = refresh_before })
        return false
    end

    local hp = HpVital.normalize_hp_value(state.snapshot and state.snapshot.current_hp)
    if hp == nil then
        state.finished = true
        state.skip_reason = "missing_current_hp"
        HpVital.record_hp_restore_state(state, phase, { refresh_before = refresh_before })
        return false
    end

    local before = HpVital.read_player_hp_snapshot(target)
    local before_fields = HpVital.read_player_hp_fields_for_debug(target)
    local heal_hp = HpVital.normalize_hp_value(state.snapshot.heal_hp) or hp
    local current_step = tonumber(trial_state.current_step) or 1
    if current_step > 1 then
        state.finished = true
        state.skip_reason = "target_hp_ownership_released"
        HpVital.record_hp_restore_state(state, phase, {
            before = before,
            before_fields = before_fields,
            target_hp_ownership_released = true,
            stable_check_count = state.stable_check_count,
        })
        return false
    end

    state.watch_frames_remaining = math.max(
        0,
        (tonumber(state.watch_frames_remaining) or 0) - 1
    )

    local live_matches = before
        and before.current_hp == hp
        and (before.heal_hp == nil or before.heal_hp == heal_hp)
    if live_matches then
        state.stable_check_count = (state.stable_check_count or 0) + 1
        state.skip_reason = "target_hp_stable"
        if state.watch_frames_remaining == 0 then
            state.finished = true
            state.skip_reason = "target_hp_stable_window_complete"
        end
        if state.stable_check_count == 1 or state.finished == true then
            HpVital.record_hp_restore_state(state, phase, {
                before = before,
                before_fields = before_fields,
                target_hp_matches = true,
                stable_check_count = state.stable_check_count,
            })
        end
        return false
    end


    -- Character initialization may overwrite the post-refresh scene write a
    -- few frames after TrainingManager reports refresh completion. Observe the
    -- full bounded window first, then perform the sole final correction. This
    -- avoids both a first-attempt full-health race and repeated HP flicker.
    if state.watch_frames_remaining > 0 then
        state.skip_reason = "waiting_for_hp_initialization_settle"
        return false
    end

    if (state.restore_count or 0) >= (state.max_runtime_writes or 1) then
        state.finished = true
        state.skip_reason = "runtime_write_limit_reached"
        HpVital.record_hp_restore_state(state, phase, {
            before = before,
            before_fields = before_fields,
            runtime_write_limit_reached = true,
        })
        return false
    end

    if (state.stable_check_count or 0) > 0 then
        state.overwrite_count = (state.overwrite_count or 0) + 1
    end
    local write_vital_new_ok, write_vital_new_err = pcall(function() target.vital_new = hp end)
    local write_vital_old_ok, write_vital_old_err = pcall(function() target.vital_old = hp end)
    local write_heal_new_ok, write_heal_new_err = pcall(function() target.heal_new = heal_hp end)
    local after = HpVital.read_player_hp_snapshot(target)
    local after_fields = HpVital.read_player_hp_fields_for_debug(target)
    local refresh_after = tm and tm:get_field("_IsReqRefresh")

    state.restored = write_vital_new_ok == true
        and write_vital_old_ok == true
        and write_heal_new_ok == true
        and after ~= nil
        and after.current_hp == hp
        and (after.heal_hp == nil or after.heal_hp == heal_hp)
    state.restore_count = (state.restore_count or 0) + 1
    state.finished = true
    state.skip_reason = state.restored and "target_hp_written_final_correction"
        or "target_hp_write_failed_closed"
    local write_errors = {
        vital_new = write_vital_new_ok and nil or tostring(write_vital_new_err),
        vital_old = write_vital_old_ok and nil or tostring(write_vital_old_err),
        heal_new = write_heal_new_ok and nil or tostring(write_heal_new_err)
    }
    local runtime_inject = {
        phase = phase,
        did_call_runtime_inject = true,
        before_fields = before_fields,
        after_fields = after_fields,
        write_vital_new_ok = write_vital_new_ok == true,
        write_vital_old_ok = write_vital_old_ok == true,
        write_heal_new_ok = write_heal_new_ok == true,
        write_errors = write_errors,
        restore_count = state.restore_count,
        overwrite_count = state.overwrite_count or 0
    }
    HpVital.record_hp_restore_state(state, phase, {
        before = before,
        before_fields = before_fields,
        after = after,
        after_fields = after_fields,
        did_call_runtime_inject = true,
        write_results = {
            vital_new = write_vital_new_ok == true,
            vital_old = write_vital_old_ok == true,
            heal_new = write_heal_new_ok == true
        },
        write_vital_new_ok = write_vital_new_ok == true,
        write_vital_old_ok = write_vital_old_ok == true,
        write_heal_new_ok = write_heal_new_ok == true,
        write_errors = write_errors,
        runtime_inject = runtime_inject,
        refresh_before = refresh_before,
        refresh_after = refresh_after
    })
    return state.restored == true
end

return HpVital
