-- RawRecordingFacts.lua
-- Keeps factual recording gauge snapshots without entering the Legacy action,
-- contact, command-resolution or detector pipeline.

local RawRecordingFacts = {
    name = "ComboTrials.Raw.RawRecordingFacts",
}

function RawRecordingFacts.observe(options)
    options = type(options) == "table" and options or {}
    local state = options.trial_state
    if type(state) ~= "table" or state.is_recording ~= true
        or options.player_index ~= state.recording_player then
        return false
    end
    local pending = tonumber(state._rec_pending_snapshot) or 0
    if pending > 0 then
        pending = pending - 1
        state._rec_pending_snapshot = pending
        if pending == 0 and type(options.capture_gauges) == "function" then
            local ok, gauges = pcall(options.capture_gauges, options.player_index)
            if ok then state._rec_gauges = gauges end
        end
    end
    if state._rec_gauges ~= nil and type(options.track_gauges) == "function" then
        pcall(options.track_gauges, options.victim, options.player_character,
            options.player_index)
    end
    return true
end

return RawRecordingFacts
