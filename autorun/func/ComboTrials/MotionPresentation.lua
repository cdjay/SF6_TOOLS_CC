local MotionPresentation = {
    name = "ComboTrials.MotionPresentation",
}

local NAMED_SEQUENCES = {
    [1231] = {
        patterns = { "SHUN%s+GOKU%s+SATSU", "瞬狱杀" },
        display = "LP,LP,6,LK,HP (瞬狱杀)",
    },
}

function MotionPresentation.resolve_named_sequence(action_id, motion)
    local entry = NAMED_SEQUENCES[tonumber(action_id)]
    if entry == nil then return nil end
    local normalized = tostring(motion or ""):upper()
    for _, pattern in ipairs(entry.patterns) do
        if normalized:find(pattern) ~= nil then return entry.display end
    end
    return nil
end

return MotionPresentation
