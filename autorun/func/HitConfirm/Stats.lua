local Stats = {}

local function percentage(correct, total)
    if (tonumber(total) or 0) <= 0 then return 0 end
    return (tonumber(correct) or 0) * 100 / total
end

function Stats.reset(session, timer_seconds)
    session.score = 0
    session.total = 0
    session.hit_ok = 0
    session.hit_tot = 0
    session.blk_ok = 0
    session.blk_tot = 0
    session.misconfirm = 0
    session.missed_confirm = 0
    session.followup_failed = 0
    session.followups = {}
    session.reaction_frames_total = 0
    session.reaction_frames_count = 0
    session.reaction_frames_min = nil
    session.reaction_frames_max = nil
    session.time_rem = timer_seconds or 0
    session.started_at_epoch = os.time()
end

function Stats.record(session, result)
    session.total = session.total + 1
    if result.correct then session.score = session.score + 1 end
    if result.stimulus == "hit" then
        session.hit_tot = session.hit_tot + 1
        if result.correct then session.hit_ok = session.hit_ok + 1 end
    elseif result.stimulus == "block" then
        session.blk_tot = session.blk_tot + 1
        if result.correct then session.blk_ok = session.blk_ok + 1 end
    end
    if result.failure_code == "blocked_misconfirm" then session.misconfirm = session.misconfirm + 1 end
    if result.failure_code == "missed_confirm" then session.missed_confirm = session.missed_confirm + 1 end
    if result.failure_code == "followup_did_not_combo" then session.followup_failed = session.followup_failed + 1 end
    if result.correct and result.stimulus == "hit" and result.decision_frames ~= nil then
        local frames = tonumber(result.decision_frames) or 0
        session.reaction_frames_total = session.reaction_frames_total + frames
        session.reaction_frames_count = session.reaction_frames_count + 1
        session.reaction_frames_min = session.reaction_frames_min and math.min(session.reaction_frames_min, frames) or frames
        session.reaction_frames_max = session.reaction_frames_max and math.max(session.reaction_frames_max, frames) or frames
    end
    if result.followup_id then
        session.followups[result.followup_id] = (session.followups[result.followup_id] or 0) + 1
    end
end

function Stats.summary(session)
    local average_reaction = nil
    if session.reaction_frames_count > 0 then average_reaction = session.reaction_frames_total / session.reaction_frames_count end
    return {
        attempts = session.total,
        correct = session.score,
        accuracy_pct = percentage(session.score, session.total),
        hit = { attempts = session.hit_tot, correct = session.hit_ok, accuracy_pct = percentage(session.hit_ok, session.hit_tot) },
        block = { attempts = session.blk_tot, correct = session.blk_ok, accuracy_pct = percentage(session.blk_ok, session.blk_tot) },
        errors = {
            blocked_misconfirm = session.misconfirm,
            missed_confirm = session.missed_confirm,
            followup_did_not_combo = session.followup_failed
        },
        followups = session.followups,
        reaction_frames = {
            average = average_reaction,
            minimum = session.reaction_frames_min,
            maximum = session.reaction_frames_max,
            samples = session.reaction_frames_count
        }
    }
end

Stats.percentage = percentage

return Stats
