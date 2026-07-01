local json = json

local DebugTrace = {
    name = "ComboTrials.DebugTrace"
}

local HONDA_NORMAL_DUMP_PATH = "TrainingComboTrials_data/Debug_HondaNormalDump.json"
local HONDA_NORMAL_DUMP_MAX_EVENTS = 240
local VERIFY_TRACE_PATH = "TrainingComboTrials_data/VerifyTrace.json"
local VERIFY_TRACE_MAX_EVENTS = 160
local STATE_DUMP_PATH = "TrainingComboTrials_data/StateDump.json"

local build_state_summary

local function honda_normal_dump_enabled()
    local flag = rawget(_G, "CT_HONDA_NORMAL_DUMP")
    return flag ~= false
end

local function verify_trace_enabled()
    local flag = rawget(_G, "CT_VERIFY_TRACE")
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

function DebugTrace.record_match_probe(state, data)
    if not state or type(data) ~= "table" then return data end
    state._match_probe = data
    state._match_probe_history = state._match_probe_history or {}
    table.insert(state._match_probe_history, 1, data)
    while #state._match_probe_history > 20 do
        table.remove(state._match_probe_history)
    end
    if verify_trace_enabled() then
        if not state._verify_trace_dump then
            state._verify_trace_dump = {
                timestamp = os.date("%Y-%m-%d %H:%M:%S"),
                note = "Rolling ComboTrials validation trace. Disable with _G.CT_VERIFY_TRACE=false.",
                path = VERIFY_TRACE_PATH,
                events = {}
            }
        end
        local dump = state._verify_trace_dump
        dump.updated_at = os.date("%Y-%m-%d %H:%M:%S")
        dump.enabled = true
        table.insert(dump.events, data)
        while #dump.events > VERIFY_TRACE_MAX_EVENTS do
            table.remove(dump.events, 1)
        end
        pcall(function()
            DebugTrace.write_json(VERIFY_TRACE_PATH, dump)
        end)
    end
    if build_state_summary then
        pcall(function()
            DebugTrace.write_json(STATE_DUMP_PATH, build_state_summary(state))
        end)
    end
    return data
end

local function step_summary(step, idx)
    if not step then return nil end
    return {
        step = idx,
        id = step.id,
        motion = step.motion,
        expected_combo = step.expected_combo,
        expected_hp = step.expected_hp,
        delay_from_prev = step.delay_from_prev,
        has_hit = step.has_hit,
        actual_combo = step.actual_combo,
        last_frame_diff = step.last_frame_diff,
        counter_type = step.counter_type,
        is_holdable = step.is_holdable,
        charge_status = step.charge_status,
        next_auto_id = step.next_auto_id
    }
end

local function sequence_title(sequence)
    local first = sequence and sequence[1] or nil
    if not first then return nil end
    local xt_meta = type(first._xt_meta) == "table" and first._xt_meta or nil
    if xt_meta and xt_meta.title then return xt_meta.title end
    local wtt_meta = type(first._wtt_cn_meta) == "table" and first._wtt_cn_meta or nil
    if wtt_meta and wtt_meta.title then return wtt_meta.title end
    return nil
end

build_state_summary = function(state)
    if not state then return nil end
    local current_step = state.current_step
    local sequence = state.sequence
    local expected = sequence and current_step and sequence[current_step] or nil
    local previous = sequence and current_step and current_step > 1 and sequence[current_step - 1] or nil
    return {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        trial_file = state.current_file or state.current_file_path or nil,
        trial_filename = state.current_file_name or nil,
        trial_title = sequence_title(sequence),
        trial_step = current_step,
        trial_total = sequence and #sequence or 0,
        trial_playing = state.is_playing,
        trial_demo = state.trial_demo,
        training_active = rawget(_G, "CurrentTrainerMode"),
        fail_reason_ui = state.fail_reason,
        expected_step = step_summary(expected, current_step),
        previous_verified_step = step_summary(previous, current_step and current_step - 1 or nil),
        validation_debug = state._validation_debug,
        auto_advance_debug = state._auto_advance_debug,
        pending_current_absorb = state._pending_current_absorb,
        match_probe = state._match_probe,
        match_probe_history = state._match_probe_history
    }
end

function DebugTrace.build_fail_dump(state, players)
    local player = players and state and players[state.playing_player] or nil
    local current_step = state and state.current_step or nil
    local sequence = state and state.sequence or nil
    local expected = sequence and current_step and sequence[current_step] or nil
    local previous = sequence and current_step and current_step > 1 and sequence[current_step - 1] or nil
    local dump = {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        trial_file = state.current_file or state.current_file_path or nil,
        trial_filename = state.current_file_name or nil,
        trial_title = sequence_title(sequence),
        character = player and player.profile_name or nil,
        fail_reason_ui = state.fail_reason,
        failed_at_step = state.current_step,
        trial_step = current_step,
        trial_total = sequence and #sequence or 0,
        trial_playing = state.is_playing,
        trial_demo = state.trial_demo,
        training_active = rawget(_G, "CurrentTrainerMode"),
        expected_step = step_summary(expected, current_step),
        previous_verified_step = step_summary(previous, current_step and current_step - 1 or nil),
        validation_debug = state._validation_debug,
        auto_advance_debug = state._auto_advance_debug,
        pending_current_absorb = state._pending_current_absorb,
        match_probe = state._match_probe,
        match_probe_history = state._match_probe_history,
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
