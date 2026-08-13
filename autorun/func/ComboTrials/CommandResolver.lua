local M = {}

local RUNTIME_COMMON_DIRECTION_ACTIONS = {
    [17] = true,
    [18] = true,
    [36] = true,
    [37] = true,
    [38] = true,
}

local BTN_MASKS = {
    [16] = "LP",
    [32] = "MP",
    [64] = "HP",
    [128] = "LK",
    [256] = "MK",
    [512] = "HK"
}

local NAMED_BTN_MASKS = {
    LP = 16,
    MP = 32,
    HP = 64,
    LK = 128,
    MK = 256,
    HK = 512,
}

M.PLAYER_TRANSITION_INPUT_WINDOW = 12

local function decode_transition_button_mask(mask)
    mask = (tonumber(mask) or 0) & 0xFFF0
    local punch_count = ((mask & 16) ~= 0 and 1 or 0)
        + ((mask & 32) ~= 0 and 1 or 0) + ((mask & 64) ~= 0 and 1 or 0)
    local kick_count = ((mask & 128) ~= 0 and 1 or 0)
        + ((mask & 256) ~= 0 and 1 or 0) + ((mask & 512) ~= 0 and 1 or 0)
    if punch_count > 0 and kick_count == 0 then return punch_count >= 2 and "PP" or "P" end
    if kick_count > 0 and punch_count == 0 then return kick_count >= 2 and "KK" or "K" end
    local parts = {}
    for _, bit in ipairs({ 16, 32, 64, 128, 256, 512 }) do
        if (mask & bit) ~= 0 then table.insert(parts, BTN_MASKS[bit]) end
    end
    return table.concat(parts, "+")
end

local function is_direction_only_display(value)
    local compact = tostring(value or ""):upper():gsub("[%s_+%-]+", "")
    return compact:match("^[1-9]+$") ~= nil
end

local function explicit_button_mask_from_motion(value)
    local mask = 0
    for token in tostring(value or ""):upper():gmatch("[A-Z]+") do
        local button_mask = NAMED_BTN_MASKS[token]
        if button_mask then mask = mask | button_mask end
    end
    return mask
end

local function previous_compiled_event(session, event)
    local events = type(session) == "table" and session.events or nil
    if type(events) ~= "table" or type(event) ~= "table" then return nil end
    for index = #events, 1, -1 do
        local candidate = events[index]
        if candidate == event
            or (tonumber(candidate and candidate.id) == tonumber(event.id)
                and tonumber(candidate and candidate.frame) == tonumber(event.frame)) then
            return events[index - 1]
        end
    end
    return nil
end

-- A static suppress transition can become visible while the input snapshot
-- still contains the preceding command's attack button. Recover the physical
-- transition edge by subtracting only the explicitly named owner button(s)
-- from the combined adjacent input. This keeps the rule data-driven and
-- prevents the same cancel from alternating between K, P and HP+LK.
function M.find_input_bound_transition_edge(character, event, session, renderer)
    local anchor = type(event) == "table" and type(event.anchor) == "table"
        and event.anchor or {}
    local pressed = (tonumber(anchor.pressed_buttons) or 0) & 0xFFF0
    local released = (tonumber(anchor.released_buttons) or 0) & 0xFFF0
    local held = (tonumber(anchor.held_buttons) or 0) & 0xFFF0
    local edge = pressed ~= 0 and pressed or released
    local candidate = edge | held
    local previous = previous_compiled_event(session, event)
    if type(previous) == "table" and renderer and renderer.get_command_display then
        local delay = (tonumber(event.frame) or 0) - (tonumber(previous.frame) or 0)
        if delay >= 0 and delay <= M.PLAYER_TRANSITION_INPUT_WINDOW then
            local previous_anchor = type(previous.anchor) == "table"
                and previous.anchor or {}
            candidate = candidate
                | ((tonumber(previous_anchor.pressed_buttons) or 0) & 0xFFF0)
                | ((tonumber(previous_anchor.held_buttons) or 0) & 0xFFF0)
            local ok, previous_motion = pcall(
                renderer.get_command_display,
                character,
                previous.id,
                "classic"
            )
            if ok then
                local owner_buttons = explicit_button_mask_from_motion(previous_motion)
                local residual = candidate & (~owner_buttons) & 0xFFF0
                if residual ~= 0 then return residual end
            end
        end
    end
    return edge
end

function M.find_recent_action_button_edge(history, parent_start_frame, current_frame, window)
    if type(history) ~= "table" then return 0 end
    parent_start_frame = tonumber(parent_start_frame) or -1
    current_frame = tonumber(current_frame) or parent_start_frame
    window = tonumber(window) or M.PLAYER_TRANSITION_INPUT_WINDOW
    for i = #history, 1, -1 do
        local entry = history[i]
        local frame_tick = tonumber(type(entry) == "table" and entry.frame_tick) or -1
        if (current_frame - frame_tick) > window then break end
        -- Only edges pressed after the parent action began can describe a
        -- derived cancel. This excludes the P edge that launched 214+P.
        if frame_tick <= parent_start_frame then break end
        local button_edge = (tonumber(entry.mask) or 0) & 0xFFF0
        if button_edge ~= 0 then return button_edge end
    end
    return 0
end

function M.collect_action_button_edges(history, action_start_frame, current_frame, window)
    if type(history) ~= "table" then return 0, nil end
    action_start_frame = tonumber(action_start_frame) or -1
    current_frame = tonumber(current_frame) or action_start_frame
    window = tonumber(window) or M.PLAYER_TRANSITION_INPUT_WINDOW
    local buttons = 0
    local latest_frame = nil
    local press_frames = {}
    for i = #history, 1, -1 do
        local entry = history[i]
        local frame_tick = tonumber(type(entry) == "table" and entry.frame_tick) or -1
        if frame_tick < action_start_frame then break end
        if frame_tick <= current_frame
            and frame_tick - action_start_frame <= window then
            local edge = (tonumber(entry.mask) or 0) & 0xFFF0
            if edge ~= 0 then
                buttons = buttons | edge
                latest_frame = math.max(latest_frame or frame_tick, frame_tick)
                for bit_index = 4, 15 do
                    local bit = 1 << bit_index
                    -- History is scanned newest-first. Keep the newest physical
                    -- press for each button so live matching uses the same edge
                    -- as ActionEventCompiler after a release/re-press.
                    if (edge & bit) ~= 0 and press_frames[bit] == nil then
                        press_frames[bit] = frame_tick
                    end
                end
            end
        end
    end
    return buttons & 0xFFF0,
        latest_frame and math.max(0, latest_frame - action_start_frame) or nil,
        press_frames
end

-- A resolved catalog entry means the action was deliberately admitted by the
-- BCM base table or its curated exception aliases. Some stance normals use
-- flags=16/action_code=0 even when the player pressed an attack button, so the
-- generic intentionality heuristic alone incorrectly discards them.
function M.resolve_unified_command_action(character, action_id, direct_input, newly_pressed, renderer)
    local held_buttons = (tonumber(direct_input) or 0) & 0xFFF0
    local edge_buttons = (tonumber(newly_pressed) or 0) & 0xFFF0
    if not renderer or not renderer.get_command_display then
        return false, "resolver_unavailable", nil
    end
    local display, status
    if type(renderer.get_input_conditioned_command_display) == "function" then
        local conditioned_ok, conditioned_display, conditioned_status = pcall(
            renderer.get_input_conditioned_command_display,
            character,
            action_id,
            direct_input,
            newly_pressed,
            "classic"
        )
        if not conditioned_ok then return false, "resolver_error", nil end
        display, status = conditioned_display, conditioned_status
    end
    local ok = true
    if display == nil then
        ok, display, status = pcall(
            renderer.get_command_display,
            character,
            action_id,
            "classic"
        )
    end
    if not ok then return false, "resolver_error", nil end
    if status == "suppress_transition" then
        local transition_button = decode_transition_button_mask(newly_pressed)
        if transition_button ~= "" then
            return true, "player_input_transition", ">" .. transition_button .. " (取消)"
        end
        return false, status, nil
    end
    -- The engine can expose the catalog Action a few frames after the physical
    -- button edge, after direct_input has already returned to zero. The input
    -- buffer recovers that post-parent edge specifically for this transition.
    local has_player_buttons = held_buttons ~= 0 or edge_buttons ~= 0
    -- A route-unverified direction command does not explain an attack-button
    -- edge. Characters can expose such a short movement/high-jump Action just
    -- before the button's durable attack Action; protecting it as a catalog
    -- command would defeat the live ghost debounce and disagree with the raw
    -- input compiler.
    local unexplained_direction_button =
        status == "route_unverified"
        and edge_buttons ~= 0
        and is_direction_only_display(display)
    local runtime_common_direction =
        RUNTIME_COMMON_DIRECTION_ACTIONS[tonumber(action_id)] == true
    local is_player_command = (has_player_buttons or runtime_common_direction)
        and type(display) == "string" and display ~= ""
        and not unexplained_direction_button
    return is_player_command, status, display
end

return M
