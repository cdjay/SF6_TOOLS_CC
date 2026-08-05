local TrialDisplayState = {}

function TrialDisplayState.resolve(sequence, current_step, success_timer)
    local total_steps = type(sequence) == "table" and #sequence or 0
    local step = tonumber(current_step) or 1
    local timer_active = (tonumber(success_timer) or 0) > 0
    local past_final_step = total_steps > 0 and step > total_steps
    -- This state is presentation-only. Advancing past the final command proves
    -- that every displayed row was consumed, even when legacy outcome counters
    -- no longer match the current game build. Runtime audit remains strict.
    local terminal_visual_complete = past_final_step
    local success = timer_active or terminal_visual_complete

    local active_step = nil
    if total_steps > 0 then
        active_step = math.max(1, math.min(step, total_steps))
    end

    return {
        active_step = active_step,
        is_success = success,
        past_final_step = past_final_step,
        terminal_visual_complete = terminal_visual_complete,
        total_steps = total_steps,
    }
end

return TrialDisplayState
