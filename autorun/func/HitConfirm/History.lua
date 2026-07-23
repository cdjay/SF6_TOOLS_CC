local History = {
    PATH = "Stats/HitConfirm_SessionStats.txt"
}

local function percentage(correct, total)
    if (tonumber(total) or 0) <= 0 then return 0 end
    return (tonumber(correct) or 0) * 100 / total
end

function History.append(session, user_config)
    if not session or (tonumber(session.total) or 0) <= 0 then return false, "empty session" end
    if fs and fs.create_dir then pcall(fs.create_dir, "Stats") end

    local exists = false
    local check = io.open(History.PATH, "r")
    if check then exists = true; check:close() end

    local file, open_error = io.open(History.PATH, "a+")
    if not file then return false, tostring(open_error or "open failed") end
    if not exists then
        file:write("DATE\tTIME\tMODE\tDURATION\tTOTAL\tSUCCESS\tPCT\tSCORE\tHIT_TOT\tHIT_OK\tHIT_PCT\tBLK_TOT\tBLK_OK\tBLK_PCT\n")
    end

    local duration = math.max(0, os.time() - (tonumber(session.started_at_epoch) or os.time()))
    local mode = user_config.session_mode == "timer"
        and ("TIMED_" .. tostring(user_config.timer_minutes) .. "M")
        or ("TRIALS_" .. tostring(user_config.trial_count))
    local line = string.format(
        "%s\t%s\t%s\t%02d:%02d\t%d\t%d\t%.2f%%\t%d\t%d\t%d\t%.2f%%\t%d\t%d\t%.2f%%\n",
        os.date("%Y-%m-%d"), os.date("%H:%M"), mode, math.floor(duration / 60), duration % 60,
        session.total, session.score, percentage(session.score, session.total), session.score,
        session.hit_tot, session.hit_ok, percentage(session.hit_ok, session.hit_tot),
        session.blk_tot, session.blk_ok, percentage(session.blk_ok, session.blk_tot)
    )
    local ok, write_error = pcall(function() file:write(line); file:flush() end)
    file:close()
    if not ok then return false, tostring(write_error) end
    return true
end

return History
