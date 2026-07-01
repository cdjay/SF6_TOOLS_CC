local json = json

local DebugTrace = {
    name = "ComboTrials.DebugTrace"
}

local HONDA_NORMAL_DUMP_PATH = "TrainingComboTrials_data/Debug_HondaNormalDump.json"
local HONDA_NORMAL_DUMP_MAX_EVENTS = 240

local function honda_normal_dump_enabled()
    local flag = rawget(_G, "CT_HONDA_NORMAL_DUMP")
    return flag ~= false
end

function DebugTrace.record_validation_debug(state, data)
    if state then
        state._validation_debug = data
    end
    return data
end

function DebugTrace.record_auto_advance(state, data)
    if state then
        state._auto_advance_debug = data
    end
    return data
end

function DebugTrace.build_fail_dump(state, players)
    local dump = {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        fail_reason_ui = state.fail_reason,
        failed_at_step = state.current_step,
        validation_debug = state._validation_debug,
        auto_advance_debug = state._auto_advance_debug,
        expected_sequence = {},
        player_recent_inputs = {}
    }

    for i, step in ipairs(state.sequence) do
        local s = {
            step = i,
            id = step.id,
            motion = step.motion,
            expected_combo = step.expected_combo,
            is_holdable = step.is_holdable,
            delay_from_prev = step.delay_from_prev
        }
        if i == state.current_step then
            s.STATUS = "<-- 失败位置"
            if state.active_universal_hold then
                s.hold_error_details = {
                    expected_status = state.active_universal_hold.expected_status,
                    expected_frames = state.active_universal_hold.expected_frames,
                    actual_frames = state.active_universal_hold.frames,
                    charge_min = state.active_universal_hold.charge_min,
                    charge_max = state.active_universal_hold.charge_max
                }
            end
        end
        table.insert(dump.expected_sequence, s)
    end

    local p_state = players[state.playing_player]
    if p_state and p_state.log then
        for i = 1, math.min(15, #p_state.log) do
            local l = p_state.log[i]
            table.insert(dump.player_recent_inputs, {
                log_index = i,
                id = l.id,
                name = l.name,
                motion = l.motion,
                real_input = l.real_input,
                frame_diff = l.frame_diff,
                intentional = l.intentional,
                hold_frames = l.hold_frames,
                charge_status = l.charge_status,
                combo_count = l.combo_count,
                is_ignored = l.is_ignored,
                ignore_reason = l.ignore_reason
            })
        end
    end

    return dump
end

function DebugTrace.write_json(path, data)
    return json.dump_file(path, data)
end

function DebugTrace.record_honda_normal_input(state, event)
    if not honda_normal_dump_enabled() then return nil end
    if not state or type(event) ~= "table" then return nil end

    if not state._honda_normal_dump then
        state._honda_normal_dump = {
            timestamp = os.date("%Y-%m-%d %H:%M:%S"),
            note = "Temporary EHonda recording-only action dump. Disable with _G.CT_HONDA_NORMAL_DUMP=false.",
            events = {}
        }
    end

    local dump = state._honda_normal_dump
    dump.updated_at = os.date("%Y-%m-%d %H:%M:%S")
    dump.enabled = true
    dump.path = HONDA_NORMAL_DUMP_PATH

    table.insert(dump.events, event)
    while #dump.events > HONDA_NORMAL_DUMP_MAX_EVENTS do
        table.remove(dump.events, 1)
    end

    pcall(function()
        DebugTrace.write_json(HONDA_NORMAL_DUMP_PATH, dump)
    end)
    return event
end

function DebugTrace.record_last_fail(state, dump, path)
    if state then
        state.last_fail_dump = dump
    end
    if path then
        pcall(function()
            DebugTrace.write_json(path, dump)
        end)
    end
    return dump
end

function DebugTrace.get_last_fail(state)
    return state and state.last_fail_dump or nil
end

function DebugTrace.log_trial_failure(file_system, state, frame_count, process_frame, source, fields)
    if not (file_system and file_system.diag_log) then return end
    fields = fields or {}
    local expected = state.sequence and state.sequence[state.current_step] or nil
    file_system.diag_log(string.format(
        "[Fail] frame=%s trial_type=combo current_step=%s expected_motion=%s player_action_id=%s player_action_name=%s timeline_frame=%s timeline_total_frames=%s wakeup_validator_active=false reversal_validator_active=false fail_reason=%s failure_source=%s playback_state=%s",
        tostring(frame_count),
        tostring(state.current_step),
        tostring(fields.expected_motion or (expected and expected.motion) or ""),
        tostring(fields.player_action_id or (process_frame and process_frame.act_id) or ""),
        tostring(fields.player_action_name or ""),
        tostring(fields.timeline_frame or ""),
        tostring(fields.timeline_total_frames or (state.sequence and #state.sequence) or ""),
        tostring(state.fail_reason or ""),
        tostring(source or ""),
        tostring(fields.playback_state or (state.is_playing and "playing" or "idle"))
    ))
end

return DebugTrace
