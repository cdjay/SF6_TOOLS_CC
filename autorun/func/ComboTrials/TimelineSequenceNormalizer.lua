local is_drive_rush_id = function() return false end

CTTimelineSequenceNormalizer = CTTimelineSequenceNormalizer or {}

function CTTimelineSequenceNormalizer.init(deps)
    deps = deps or {}
    is_drive_rush_id = deps.is_drive_rush_id or is_drive_rush_id
end

CTTimelineSequenceNormalizer.button_order = { "LP", "MP", "HP", "LK", "MK", "HK" }
CTTimelineSequenceNormalizer.button_set = { LP = true, MP = true, HP = true, LK = true, MK = true, HK = true }

function CTTimelineSequenceNormalizer.compact_motion(value)
    return tostring(value or ""):upper():gsub("%s+", "")
end

function CTTimelineSequenceNormalizer.button_table_key(buttons)
    if type(buttons) ~= "table" then return "" end
    local out = {}
    for _, btn in ipairs(CTTimelineSequenceNormalizer.button_order) do
        if buttons[btn] then out[#out + 1] = btn end
    end
    return table.concat(out, "+")
end

function CTTimelineSequenceNormalizer.parse_input(rest)
    local dir = "5"
    local buttons = {}
    for part in tostring(rest or ""):gmatch("[^+]+") do
        local token = tostring(part:match("^%s*(.-)%s*$") or ""):upper()
        if token:match("^[1-9]$") then
            dir = token
        elseif CTTimelineSequenceNormalizer.button_set[token] then
            buttons[token] = true
        elseif token == "P" then
            buttons.LP = true; buttons.MP = true; buttons.HP = true
        elseif token == "K" then
            buttons.LK = true; buttons.MK = true; buttons.HK = true
        end
    end
    return dir, buttons
end

function CTTimelineSequenceNormalizer.build_press_events(timeline)
    local events = {}
    local frame = 0
    local prev_buttons = {}
    if type(timeline) ~= "table" then return events end

    for idx, line in ipairs(timeline) do
        local frames_str, rest = tostring(line or ""):match("^(%d+)f%s*:%s*(.*)$")
        local duration = tonumber(frames_str)
        if duration then
            local dir, buttons = CTTimelineSequenceNormalizer.parse_input(rest)
            local newly_pressed = {}
            for btn, pressed in pairs(buttons) do
                if pressed and not prev_buttons[btn] then newly_pressed[btn] = true end
            end
            local new_key = CTTimelineSequenceNormalizer.button_table_key(newly_pressed)
            if new_key ~= "" then
                events[#events + 1] = {
                    index = idx,
                    start_frame = frame,
                    duration = duration,
                    dir = dir,
                    input = tostring(rest or ""),
                    buttons = buttons,
                    button_key = CTTimelineSequenceNormalizer.button_table_key(buttons),
                    new_buttons = newly_pressed,
                    new_button_key = new_key
                }
            end
            frame = frame + duration
            prev_buttons = buttons
        end
    end

    return events
end

function CTTimelineSequenceNormalizer.direction_motion(step, resolve_classic_motion)
    if type(step) ~= "table" then return nil end

    local function extract(value)
        local motion = CTTimelineSequenceNormalizer.compact_motion(value)
        motion = motion:gsub("^>", ""):gsub("%b()", "")
        if motion:match("^[1-9][1-9]+$") then return motion end
        return nil
    end

    if type(resolve_classic_motion) == "function" then
        local ok, resolved = pcall(resolve_classic_motion, step)
        if ok then
            local motion = extract(resolved)
            if motion then return motion end
        end
    end
    return extract(step.motion)
end

function CTTimelineSequenceNormalizer.direction_step_key(step, resolve_classic_motion)
    local motion = CTTimelineSequenceNormalizer.direction_motion(step, resolve_classic_motion)
    if not motion then return nil, nil end
    local action_id = step and step.id
    local key = action_id ~= nil and ("id:" .. tostring(action_id)) or ("motion:" .. motion)
    return key, motion
end

function CTTimelineSequenceNormalizer.build_direction_states(timeline)
    local states = {}
    local frame = 0
    local prev_dir = nil
    if type(timeline) ~= "table" then return states end

    for idx, line in ipairs(timeline) do
        local frames_str, rest = tostring(line or ""):match("^(%d+)f%s*:%s*(.*)$")
        local duration = tonumber(frames_str)
        if duration then
            local dir = CTTimelineSequenceNormalizer.parse_input(rest)
            if dir ~= prev_dir then
                states[#states + 1] = {
                    index = idx,
                    start_frame = frame,
                    duration = duration,
                    dir = dir
                }
                prev_dir = dir
            end
            frame = frame + duration
        end
    end
    return states
end

function CTTimelineSequenceNormalizer.find_direction_occurrences(states, motion)
    local occurrences = {}
    motion = tostring(motion or "")
    if #motion < 2 or type(states) ~= "table" then return occurrences end

    local search_from = 1
    while search_from <= #states do
        local found = nil
        for start_idx = search_from, #states do
            local first_matches, orientation = CTTimelineSequenceNormalizer.direction_matches_orientation(
                states[start_idx].dir, motion:sub(1, 1), nil)
            if first_matches then
                local cursor = start_idx + 1
                local matched = { start_idx }
                local anchor_frame = states[start_idx].start_frame or 0
                -- A leading neutral is a state boundary, not a pressed input;
                -- long idle time before the next direction must not consume the
                -- command window. Anchor it at the neutral state's release.
                if motion:sub(1, 1) == "5" then
                    anchor_frame = anchor_frame + (tonumber(states[start_idx].duration) or 0)
                end
                local deadline = anchor_frame + 30
                local complete = true
                for digit_idx = 2, #motion do
                    local target = motion:sub(digit_idx, digit_idx)
                    local target_idx = nil
                    while cursor <= #states and (states[cursor].start_frame or 0) <= deadline do
                        local direction_matches, next_orientation =
                            CTTimelineSequenceNormalizer.direction_matches_orientation(
                                states[cursor].dir, target, orientation)
                        if direction_matches then
                            target_idx = cursor
                            orientation = next_orientation
                            break
                        end
                        cursor = cursor + 1
                    end
                    if not target_idx then complete = false; break end
                    matched[#matched + 1] = target_idx
                    cursor = target_idx + 1
                end
                if complete then
                    found = {
                        first_state = matched[1],
                        last_state = matched[#matched]
                    }
                    break
                end
            end
        end
        if not found then break end
        occurrences[#occurrences + 1] = found
        search_from = found.last_state + 1
    end
    return occurrences
end

function CTTimelineSequenceNormalizer.build_direction_events(timeline, sequence, resolve_classic_motion)
    local events = {}
    local descriptors = {}
    local order = {}
    for step_index, step in ipairs(type(sequence) == "table" and sequence or {}) do
        local key, motion = CTTimelineSequenceNormalizer.direction_step_key(step, resolve_classic_motion)
        if key and not descriptors[key] then
            descriptors[key] = { key = key, motion = motion, template_index = step_index }
            order[#order + 1] = key
        end
    end
    if #order == 0 then return events end

    local states = CTTimelineSequenceNormalizer.build_direction_states(timeline)
    for _, key in ipairs(order) do
        local descriptor = descriptors[key]
        for _, occurrence in ipairs(CTTimelineSequenceNormalizer.find_direction_occurrences(states, descriptor.motion)) do
            local completion = states[occurrence.last_state]
            events[#events + 1] = {
                kind = "direction",
                direction_step_key = key,
                direction_motion = descriptor.motion,
                template_index = descriptor.template_index,
                index = completion.index,
                start_frame = completion.start_frame,
                duration = completion.duration
            }
        end
    end
    return events
end

function CTTimelineSequenceNormalizer.build_events(timeline, sequence, resolve_classic_motion)
    local events = CTTimelineSequenceNormalizer.build_press_events(timeline)
    for _, event in ipairs(CTTimelineSequenceNormalizer.build_direction_events(
        timeline, sequence, resolve_classic_motion)) do
        events[#events + 1] = event
    end
    table.sort(events, function(a, b)
        local af, bf = tonumber(a.start_frame) or 0, tonumber(b.start_frame) or 0
        if af ~= bf then return af < bf end
        local ai, bi = tonumber(a.index) or 0, tonumber(b.index) or 0
        if ai ~= bi then return ai < bi end
        return a.kind == "direction" and b.kind ~= "direction"
    end)
    return events
end

function CTTimelineSequenceNormalizer.simple_motion_parts(step)
    local motion = CTTimelineSequenceNormalizer.compact_motion(step and step.motion or "")
        :gsub("%b()", ""):gsub("^>", ""):gsub("^J%.", "")
    local dir, btn = motion:match("^([1-9])([LMH][PK])$")
    if dir and btn then return dir, btn end
    btn = motion:match("^([LMH][PK])$")
    if btn then return "5", btn end
    return nil, nil
end

function CTTimelineSequenceNormalizer.mirror_dir(dir)
    return ({ ["1"] = "3", ["3"] = "1", ["4"] = "6", ["6"] = "4", ["7"] = "9", ["9"] = "7" })[tostring(dir or "")] or tostring(dir or "")
end

function CTTimelineSequenceNormalizer.direction_matches(event_dir, step_dir)
    event_dir = tostring(event_dir or "5")
    step_dir = tostring(step_dir or "5")
    if step_dir == "2" and (event_dir == "1" or event_dir == "2" or event_dir == "3") then return true end
    return event_dir == step_dir or event_dir == CTTimelineSequenceNormalizer.mirror_dir(step_dir)
end

function CTTimelineSequenceNormalizer.direction_matches_orientation(event_dir, step_dir, mirrored)
    event_dir = tostring(event_dir or "5")
    step_dir = tostring(step_dir or "5")
    if step_dir == "2" then
        return event_dir == "1" or event_dir == "2" or event_dir == "3", mirrored
    end

    local mirror = CTTimelineSequenceNormalizer.mirror_dir(step_dir)
    if mirror == step_dir then return event_dir == step_dir, mirrored end
    if mirrored == nil then
        if event_dir == step_dir then return true, false end
        if event_dir == mirror then return true, true end
        return false, nil
    end
    return event_dir == (mirrored and mirror or step_dir), mirrored
end

function CTTimelineSequenceNormalizer.motion_anchor_parts(step)
    local motion = CTTimelineSequenceNormalizer.compact_motion(step and step.motion or "")
        :gsub("%b()", ""):gsub("^>", ""):gsub("^J%.", "")
    local dirs, btn = motion:match("^([1-9]+)%+(.+)$")
    if not dirs or not btn then dirs, btn = motion:match("^([1-9]+)(PP)$") end
    if not dirs or not btn then dirs, btn = motion:match("^([1-9]+)(KK)$") end
    if not dirs or not btn then dirs, btn = motion:match("^([1-9]+)([LMH][PK])$") end
    if not dirs or not btn then dirs, btn = motion:match("^([1-9]+)([PK])$") end
    if not dirs or not btn then return nil, nil end

    local normalized_buttons = {}
    local button_parts = {}
    if btn == "P" or btn == "K" or btn == "PP" or btn == "KK" then
        return dirs:sub(-1), btn
    end

    for part in tostring(btn or ""):gmatch("[^+]+") do
        local token = tostring(part or ""):upper()
        if not CTTimelineSequenceNormalizer.button_set[token] then return nil, nil end
        normalized_buttons[token] = true
    end
    for _, button in ipairs(CTTimelineSequenceNormalizer.button_order) do
        if normalized_buttons[button] then button_parts[#button_parts + 1] = button end
    end
    if #button_parts == 0 then return nil, nil end
    return dirs:sub(-1), table.concat(button_parts, "+")
end

function CTTimelineSequenceNormalizer.button_matches_token(event, token)
    if type(event) ~= "table" then return false end
    token = tostring(token or ""):upper()
    if token == "P" then
        return event.new_button_key == "LP" or event.new_button_key == "MP" or event.new_button_key == "HP"
    elseif token == "K" then
        return event.new_button_key == "LK" or event.new_button_key == "MK" or event.new_button_key == "HK"
    elseif token == "PP" then
        local count = 0
        for _, button in ipairs({ "LP", "MP", "HP" }) do
            if event.new_buttons and event.new_buttons[button] then count = count + 1 end
        end
        return count >= 2
    elseif token == "KK" then
        local count = 0
        for _, button in ipairs({ "LK", "MK", "HK" }) do
            if event.new_buttons and event.new_buttons[button] then count = count + 1 end
        end
        return count >= 2
    elseif token:find("+", 1, true) then
        for part in token:gmatch("[^+]+") do
            if not (event.new_buttons and event.new_buttons[part]) then return false end
        end
        return true
    end
    return event.new_button_key == token
end

function CTTimelineSequenceNormalizer.is_drive_rush_step(step)
    local motion = CTTimelineSequenceNormalizer.compact_motion(step and step.motion or "")
    return motion == "DRC" or motion:find("DRIVERUSH", 1, true) ~= nil
        or is_drive_rush_id(step and step.id)
end

function CTTimelineSequenceNormalizer.is_simple_button_step(step)
    if type(step) ~= "table" or CTTimelineSequenceNormalizer.is_drive_rush_step(step) then return false end
    local dir, btn = CTTimelineSequenceNormalizer.simple_motion_parts(step)
    return dir ~= nil and btn ~= nil
end

function CTTimelineSequenceNormalizer.simple_button_step_key(step)
    if not CTTimelineSequenceNormalizer.is_simple_button_step(step) then return nil end
    local action_id = step and step.id
    if action_id ~= nil then return "id:" .. tostring(action_id) end
    return "motion:" .. CTTimelineSequenceNormalizer.compact_motion(step and step.motion or "")
end

function CTTimelineSequenceNormalizer.build_single_hit_evidence(sequence)
    local evidence = {}
    if type(sequence) ~= "table" then return evidence end

    local prev_combo = 0
    for _, step in ipairs(sequence) do
        local final_combo = tonumber(step and step.expected_combo) or 0
        local key = CTTimelineSequenceNormalizer.simple_button_step_key(step)
        if key and final_combo - prev_combo == 1 then
            evidence[key] = true
        end
        prev_combo = final_combo
    end

    return evidence
end

function CTTimelineSequenceNormalizer.event_matches_step(event, step, resolve_classic_motion)
    if type(event) ~= "table" or type(step) ~= "table" then return false end
    local direction_key = CTTimelineSequenceNormalizer.direction_step_key(step, resolve_classic_motion)
    if direction_key then
        return event.kind == "direction" and event.direction_step_key == direction_key
    end
    if CTTimelineSequenceNormalizer.is_drive_rush_step(step) then
        return event.new_buttons and event.new_buttons.MP and event.new_buttons.MK
            and event.new_button_key == "MP+MK"
    end

    local dir, btn = CTTimelineSequenceNormalizer.simple_motion_parts(step)
    if dir and btn then
        return event.new_button_key == btn and CTTimelineSequenceNormalizer.direction_matches(event.dir, dir)
    end

    dir, btn = CTTimelineSequenceNormalizer.motion_anchor_parts(step)
    if not dir or not btn then return false end
    return CTTimelineSequenceNormalizer.button_matches_token(event, btn)
        and (event.dir == "5" or CTTimelineSequenceNormalizer.direction_matches(event.dir, dir))
end

function CTTimelineSequenceNormalizer.find_event_for_step(events, start_idx, step, resolve_classic_motion)
    for i = math.max(1, tonumber(start_idx) or 1), #events do
        if CTTimelineSequenceNormalizer.event_matches_step(events[i], step, resolve_classic_motion) then return i end
    end
    return nil
end

function CTTimelineSequenceNormalizer.clone_step(step)
    local clone = {}
    for k, v in pairs(step) do
        if k ~= "_xt_meta" and k ~= "_wtt_cn_meta" and k ~= "timeline"
            and k ~= "scene_state" then
            if k == "motion_aliases" and type(v) == "table" then
                local aliases = {}
                for i, alias in ipairs(v) do aliases[i] = alias end
                clone[k] = aliases
            else
                clone[k] = v
            end
        end
    end
    clone._ct_timeline_expanded = true
    return clone
end

function CTTimelineSequenceNormalizer.repeat_combo_value(prev_combo, final_combo, occurrence, repeat_count)
    prev_combo = tonumber(prev_combo) or 0
    final_combo = tonumber(final_combo) or 0
    if final_combo <= prev_combo or repeat_count <= 1 then return final_combo end
    if occurrence >= repeat_count then return final_combo end
    local value = prev_combo + occurrence
    if value > final_combo then value = final_combo end
    return value
end

function CTTimelineSequenceNormalizer.insert_missing_direction_steps(sequence, events, matches)
    local matched_events = {}
    local matched_direction_keys = {}
    for step_index = 1, #sequence do
        local event_idx = matches[step_index]
        if event_idx then
            matched_events[event_idx] = true
            local event = events[event_idx]
            if event and event.kind == "direction" then
                matched_direction_keys[event.direction_step_key] = true
            end
        end
    end

    local insertions = {}
    for event_idx, event in ipairs(events) do
        if event.kind == "direction" and not matched_events[event_idx]
            and matched_direction_keys[event.direction_step_key] then
            local prev_step_idx = nil
            local next_step_idx = nil
            for step_idx = 1, #sequence do
                local matched_idx = matches[step_idx]
                if matched_idx and matched_idx < event_idx then prev_step_idx = step_idx end
                if matched_idx and matched_idx > event_idx then next_step_idx = step_idx; break end
            end
            -- Only repair a repeat bracketed by two already identified actions.
            -- This prevents pre-trial movement and trailing idle input from
            -- becoming synthetic validation steps.
            if prev_step_idx and next_step_idx then
                insertions[next_step_idx] = insertions[next_step_idx] or {}
                insertions[next_step_idx][#insertions[next_step_idx] + 1] = event
            end
        end
    end
    if next(insertions) == nil then return false end

    local augmented = {}
    local last_event = nil
    for step_idx, step in ipairs(sequence) do
        for _, event in ipairs(insertions[step_idx] or {}) do
            local template = sequence[event.template_index]
            local previous = augmented[#augmented]
            if template and previous then
                local clone = CTTimelineSequenceNormalizer.clone_step(template)
                clone._ct_direction_repeat = true
                clone.expected_combo = tonumber(previous.expected_combo) or 0
                clone.actual_combo = 0
                clone.has_hit = false
                clone.expected_hp = previous.expected_hp
                clone.damage_at_step = previous.damage_at_step
                clone.action_instance = nil
                clone.delay_from_prev = last_event
                    and math.max(0, (event.start_frame or 0) - (last_event.start_frame or 0)) or 0
                augmented[#augmented + 1] = clone
                last_event = event
            end
        end
        augmented[#augmented + 1] = step
        local matched_idx = matches[step_idx]
        if matched_idx then last_event = events[matched_idx] end
    end

    for i = #sequence, 1, -1 do sequence[i] = nil end
    for i, step in ipairs(augmented) do sequence[i] = step end
    return true
end

function CTTimelineSequenceNormalizer.expand(sequence, resolve_classic_motion)
    if type(sequence) ~= "table" or type(sequence[1]) ~= "table" then return end
    local timeline = sequence[1].timeline
    if type(timeline) ~= "table" or #timeline == 0 then return end

    local events = CTTimelineSequenceNormalizer.build_events(timeline, sequence, resolve_classic_motion)
    if #events == 0 then return end

    local matches = {}
    local search_idx = 1
    for i, step in ipairs(sequence) do
        local event_idx = CTTimelineSequenceNormalizer.find_event_for_step(
            events, search_idx, step, resolve_classic_motion)
        matches[i] = event_idx
        if event_idx then search_idx = event_idx + 1 end
    end

    if CTTimelineSequenceNormalizer.insert_missing_direction_steps(sequence, events, matches) then
        events = CTTimelineSequenceNormalizer.build_events(timeline, sequence, resolve_classic_motion)
        matches = {}
        search_idx = 1
        for i, step in ipairs(sequence) do
            local event_idx = CTTimelineSequenceNormalizer.find_event_for_step(
                events, search_idx, step, resolve_classic_motion)
            matches[i] = event_idx
            if event_idx then search_idx = event_idx + 1 end
        end
    end
    local single_hit_evidence = CTTimelineSequenceNormalizer.build_single_hit_evidence(sequence)

    local expanded = {}
    local changed = false
    local last_expanded_event_idx = nil
    local last_expanded_was_inserted = false

    for i, step in ipairs(sequence) do
        local prev_combo = #expanded > 0 and (tonumber(expanded[#expanded].expected_combo) or 0) or 0
        local final_combo = tonumber(step.expected_combo) or 0
        local duplicate_events = {}
        local step_event_idx = matches[i]

        local combo_delta = final_combo - prev_combo
        local simple_step_key = CTTimelineSequenceNormalizer.simple_button_step_key(step)
        local can_expand_repeated_simple = combo_delta <= 1
            or (combo_delta > 1 and simple_step_key and single_hit_evidence[simple_step_key] == true)
        if CTTimelineSequenceNormalizer.is_simple_button_step(step) and step_event_idx and can_expand_repeated_simple then
            local next_event_idx = nil
            for j = i + 1, #sequence do
                if matches[j] then next_event_idx = matches[j]; break end
            end
            if next_event_idx then
                local scan_end = next_event_idx - 1
                for event_idx = step_event_idx + 1, scan_end do
                    if CTTimelineSequenceNormalizer.event_matches_step(
                        events[event_idx], step, resolve_classic_motion) then
                        duplicate_events[#duplicate_events + 1] = event_idx
                    end
                end
            end
        end
        local max_extra_events = math.max(0, final_combo - prev_combo - 1)
        while #duplicate_events > max_extra_events do
            table.remove(duplicate_events)
        end

        local repeat_count = 1 + #duplicate_events
        if repeat_count > 1 then
            step.expected_combo = CTTimelineSequenceNormalizer.repeat_combo_value(prev_combo, final_combo, 1, repeat_count)
            changed = true
        end

        if step_event_idx and last_expanded_event_idx and last_expanded_was_inserted then
            step.delay_from_prev = math.max(0, (events[step_event_idx].start_frame or 0) - (events[last_expanded_event_idx].start_frame or 0))
            changed = true
        end

        expanded[#expanded + 1] = step
        if step_event_idx then
            last_expanded_event_idx = step_event_idx
            last_expanded_was_inserted = false
        end

        local previous_event_idx = step_event_idx
        for occurrence, event_idx in ipairs(duplicate_events) do
            local clone = CTTimelineSequenceNormalizer.clone_step(step)
            clone.expected_combo = CTTimelineSequenceNormalizer.repeat_combo_value(prev_combo, final_combo, occurrence + 1, repeat_count)
            clone.delay_from_prev = previous_event_idx and math.max(0, (events[event_idx].start_frame or 0) - (events[previous_event_idx].start_frame or 0)) or 0
            clone._ct_timeline_source_step = i
            clone._ct_timeline_event_index = events[event_idx].index
            expanded[#expanded + 1] = clone
            previous_event_idx = event_idx
            last_expanded_event_idx = event_idx
            last_expanded_was_inserted = true
        end
    end

    if not changed then return end
    for i = #sequence, 1, -1 do sequence[i] = nil end
    for i, step in ipairs(expanded) do sequence[i] = step end
end

return CTTimelineSequenceNormalizer
