package.path = "autorun/?.lua;autorun/?/init.lua;" .. package.path

local Engine = require("func/HitConfirm/Engine")
local Stats = require("func/HitConfirm/Stats")
local Transport = require("func/Training_Telemetry")

local case = {
    _starter_ids = { [655] = true },
    _followup_ids = { [900] = true, [901] = true },
    _followup_by_action = {
        [900] = { id = "pp", command = "PP" },
        [901] = { id = "ppp", command = "PPP" }
    },
    rules = {
        hit_confirm_frames = 45,
        block_confirm_frames = 24,
        followup_hit_frames = 30,
        minimum_combo_count = 2,
        neutral_reset_frames = 3
    }
}

local function sample(frame, action_id, contact, combo_count, hit_stop)
    return {
        frame = frame,
        action_id = action_id,
        contact = contact,
        combo_count = combo_count or 0,
        hit_stop = hit_stop or 0
    }
end

local engine = Engine.new(case)

assert(engine:step(sample(1, 655)) == nil)
assert(engine:step(sample(5, 655, "hit", 1, 8)) == nil)
assert(engine:step(sample(10, 900, nil, 1)) == nil)
local hit_pp = engine:step(sample(18, 900, nil, 2, 5))
assert(hit_pp and hit_pp.correct and hit_pp.stimulus == "hit")
assert(hit_pp.followup_id == "pp" and hit_pp.followup_action_id == 900)
assert(hit_pp.decision_frames == 5)
assert(engine:step(sample(19, 900, nil, 2, 4)) == nil, "terminal result must only emit once")

engine:reset()
engine:step(sample(1, 655))
engine:step(sample(4, 655, "block", 0, 7))
local safe_block = engine:step(sample(28, 2, nil, 0, 0))
assert(safe_block and safe_block.correct and safe_block.stimulus == "block")
assert(safe_block.decision == "hold")

engine:reset()
engine:step(sample(1, 655))
engine:step(sample(4, 655, "block", 0, 7))
local misconfirm = engine:step(sample(9, 901, nil, 0, 0))
assert(misconfirm and not misconfirm.correct)
assert(misconfirm.failure_code == "blocked_misconfirm")
assert(misconfirm.followup_id == "ppp" and misconfirm.followup_action_id == 901)

engine:reset()
engine:step(sample(1, 655))
engine:step(sample(4, 655, "hit", 1, 7))
local missed = engine:step(sample(49, 2, nil, 0, 0))
assert(missed and not missed.correct and missed.failure_code == "missed_confirm")

engine:reset()
engine:step(sample(1, 655))
engine:step(sample(4, 655, "hit", 1, 7))
engine:step(sample(12, 900, nil, 1, 0))
local dropped = engine:step(sample(42, 2, nil, 0, 0))
assert(dropped and not dropped.correct and dropped.failure_code == "followup_did_not_combo")

-- Cooldown requires three neutral frames before accepting the next starter.
assert(engine:step(sample(43, 2, nil, 0, 0)) == nil)
assert(engine:step(sample(44, 2, nil, 0, 0)) == nil)
assert(engine:step(sample(45, 2, nil, 0, 0)) == nil)
assert(engine:get_phase() == "waiting")
assert(engine:step(sample(46, 655)) == nil)
assert(engine:get_phase() == "starter")

local session = {}
Stats.reset(session, 120)
Stats.record(session, hit_pp)
Stats.record(session, misconfirm)
Stats.record(session, missed)
local summary = Stats.summary(session)
assert(summary.attempts == 3 and summary.correct == 1)
assert(summary.hit.attempts == 2 and summary.hit.correct == 1)
assert(summary.block.attempts == 1 and summary.block.correct == 0)
assert(summary.errors.blocked_misconfirm == 1 and summary.errors.missed_confirm == 1)
assert(summary.followups.pp == 1 and summary.followups.ppp == 1)
assert(summary.reaction_frames.average == 5)

local encoded = Transport.encode_json({
    schema = "sf6cc.hit_confirm_attempt.v1",
    correct = true,
    values = { 655, 900, 901 },
    text = "老桑\n确认"
})
assert(encoded:find('"schema":"sf6cc.hit_confirm_attempt.v1"', 1, true))
assert(encoded:find('"values":[655,900,901]', 1, true))
assert(encoded:find('"text":"老桑\\n确认"', 1, true))

print("hit-confirm engine tests passed")
