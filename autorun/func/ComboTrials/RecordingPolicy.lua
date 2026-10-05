local M = {}

function M.is_training_enabled()
    return true
end

-- Replay recording will return through the replay analysis module.
function M.is_replay_enabled()
    return false
end

return M
