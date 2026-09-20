local M = {}

-- Legacy recording is retired from the product UI. Keep its compiler and
-- cancellation paths intact until recording moves into replay analysis.
function M.is_enabled()
    return false
end

return M
