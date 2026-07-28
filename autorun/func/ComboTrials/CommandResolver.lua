local M = {}

local BTN_MASKS = {
    [16] = "LP",
    [32] = "MP",
    [64] = "HP",
    [128] = "LK",
    [256] = "MK",
    [512] = "HK"
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
    local ok, display, status = pcall(renderer.get_command_display, character, action_id, "classic")
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
    local is_player_command = (held_buttons ~= 0 or edge_buttons ~= 0)
        and type(display) == "string" and display ~= ""
    return is_player_command, status, display
end

return M
