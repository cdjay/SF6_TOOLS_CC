package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local compiler = dofile("autorun/func/ComboTrials/ActionEventCompiler.lua")
local transcriber = dofile("autorun/func/ComboTrials/Transcriber.lua")
local CharacterRules = require("func/ComboTrials/CharacterRules")
local ActionMatcher = require("func/ComboTrials/ActionMatcher")

assert(compiler.BIND_WINDOW == ActionMatcher.PLAYER_ACTION_BIND_WINDOW,
    "compiler and runtime validator must share one physical-input bind window")

local session = compiler.new({ character = "Ryu", frame = 0 })

local function observe(frame, action_id, action_frame, input, combo, victim_hp, damage_type)
    compiler.observe(session, {
        frame = frame,
        action_id = action_id,
        action_frame = action_frame,
        direct_input = input,
        facing_right = true,
        combo_count = combo or 0,
        actor_hp = 10000,
        actor_drive = frame < 4 and 60000 or 50000,
        actor_super = frame < 4 and 30000 or 20000,
        victim_hp = victim_hp or 10000,
        victim_damage_type = damage_type or 0,
    })
end

observe(1, 10, 10, 0, 0, 10000)
observe(2, 10, 11, 2, 0, 10000)
observe(3, 10, 12, 2 | 16, 0, 10000)
observe(4, 600, 0, 2 | 16, 0, 10000)
observe(5, 600, 1, 2, 1, 9700)
observe(6, 600, 2, 0, 1, 9700)

local result = compiler.finalize(session)
assert(#result.steps == 1, "one input-bound runtime Action must become one step")
assert(result.steps[1].id == 600, "the compiler must preserve the real Action ID")
assert(result.steps[1].expected_combo == 1, "runtime combo progress must be recorded")
assert(result.steps[1].damage_at_step == 300, "runtime damage must be recorded")
assert(result.steps[1].motion == "2+LP", "missing catalogs must fall back to input notation")
assert(result.stats.drive_used == 10000 and result.stats.super_used == 10000,
    "resource baselines must freeze on the first input, before Action startup consumes gauges")
assert(result.trace.observed_actions[1].id == 600,
    "the audit trace must retain runtime Action transitions before V2 projection")

local multi_string = compiler.new({ character = "Ryu", frame = 0 })
local function multi_string_observe(frame, action_id, input, combo, victim_hp)
    compiler.observe(multi_string, {
        frame = frame,
        action_id = action_id,
        action_frame = frame,
        direct_input = input,
        facing_right = true,
        combo_count = combo or 0,
        actor_hp = 10000,
        victim_hp = victim_hp,
    })
end
multi_string_observe(1, 10, 0, 0, 10000)
multi_string_observe(2, 10, 16, 0, 10000)
multi_string_observe(3, 600, 16, 1, 9700)
multi_string_observe(4, 600, 0, 0, 10000)
multi_string_observe(5, 600, 16, 1, 9300)
local multi_string_result = compiler.finalize(multi_string)
assert(multi_string_result.stats.damage == 1000,
    "damage must accumulate across training-health refills and later OKI strings")

local repeated = compiler.new({ character = "Ryu", frame = 0 })
local function repeat_observe(frame, action_frame, input)
    compiler.observe(repeated, {
        frame = frame,
        action_id = frame < 3 and 10 or 601,
        action_frame = action_frame,
        direct_input = input,
        facing_right = true,
        combo_count = 0,
        actor_hp = 10000,
        victim_hp = 10000,
    })
end
repeat_observe(1, 10, 0)
repeat_observe(2, 11, 32)
repeat_observe(3, 0, 32)
repeat_observe(4, 1, 0)
repeat_observe(5, 2, 32)
repeat_observe(6, 0, 32)
local repeated_result = compiler.finalize(repeated)
assert(#repeated_result.steps == 2, "same-ID ActionFrame rewind must preserve repeated commands")
assert(repeated_result.steps[1].id == 601 and repeated_result.steps[2].id == 601,
    "repeated commands must retain their observed Action ID")

local function test_motion_resolver(action_id)
    local motions = {
        [17] = "66",
        [34] = "8",
        [37] = "9",
        [480] = "DP",
        [600] = "236+LP",
        [630] = "2+HP",
        [651] = "j.MP",
        [740] = "RAW DR",
        [994] = "[2]8+HK",
        [1222] = "236236+K",
    }
    if motions[action_id] then return motions[action_id], "loaded" end
    return nil, "action_id_missing"
end

local delayed_catalog_action = compiler.new({ character = "Luke", frame = 0 })
local function delayed_observe(frame, action_id, input)
    compiler.observe(delayed_catalog_action, {
        frame = frame,
        action_id = action_id,
        action_frame = frame,
        direct_input = input,
        facing_right = true,
        combo_count = 0,
        actor_hp = 10000,
        victim_hp = 10000,
    })
end
delayed_observe(1, 10, 0)
delayed_observe(2, 10, 512)
delayed_observe(3, 949, 512)
delayed_observe(4, 516, 512)
delayed_observe(5, 1222, 512)
local delayed_result = compiler.finalize(delayed_catalog_action, {
    motion_resolver = test_motion_resolver,
})
assert(#delayed_result.steps == 1
    and delayed_result.steps[1].id == 1222
    and delayed_result.steps[1].motion == "236236+K",
    "an input anchor must follow unmapped internal Actions to the durable catalog Action")
assert(delayed_result.stats.promoted_action_events == 1
    and delayed_result.stats.fallback_motion_actions == 0
    and delayed_result.trace.promoted_events[1].from_id == 949,
    "delayed Action promotion must be explicit and auditable")

local release_between_actions = compiler.new({ character = "Luke", frame = 0 })
release_between_actions.events = {
    {
        id = 949,
        frame = 10,
        anchor = { kind = "button_press", pressed_buttons = 512 },
    },
    {
        id = 516,
        frame = 12,
        anchor = { kind = "button_release", released_buttons = 512 },
    },
}
release_between_actions.observed_actions = {
    { id = 516, frame = 12, action_frame = 0 },
    { id = 1222, frame = 25, action_frame = 0 },
}
local release_between_result = compiler.finalize(release_between_actions, {
    motion_resolver = test_motion_resolver,
})
assert(#release_between_result.steps == 1
    and release_between_result.steps[1].id == 1222
    and release_between_result.stats.promoted_action_events == 1
    and release_between_result.stats.suppressed_action_events == 1,
    "an internal release phase must not split one input from its durable Action")

local unrelated_after_release = compiler.new({ character = "Luke", frame = 0 })
unrelated_after_release.events = {
    {
        id = 600,
        frame = 1,
        anchor = { kind = "button_press", pressed_buttons = 16 },
    },
    {
        id = 922,
        frame = 10,
        anchor = { kind = "button_release", released_buttons = 16 },
    },
}
unrelated_after_release.observed_actions = {
    { id = 34, frame = 62, action_frame = 0 },
}
local unrelated_after_release_result = compiler.finalize(unrelated_after_release, {
    motion_resolver = test_motion_resolver,
})
assert(#unrelated_after_release_result.steps == 1
    and unrelated_after_release_result.steps[1].id == 600
    and unrelated_after_release_result.stats.promoted_action_events == 0,
    "a released button must never be promoted to a later unrelated movement")

local bounded_promotion = compiler.new({ character = "Luke", frame = 0 })
bounded_promotion.events = {
    {
        id = 949,
        frame = 10,
        anchor = { kind = "button_press", pressed_buttons = 512 },
    },
    {
        id = 600,
        frame = 20,
        anchor = { kind = "button_press", pressed_buttons = 16 },
    },
}
bounded_promotion.observed_actions = {
    { id = 1222, frame = 25, action_frame = 0 },
}
local bounded_result = compiler.finalize(bounded_promotion, {
    motion_resolver = test_motion_resolver,
})
assert(bounded_result.steps[1].id == 949
    and bounded_result.stats.promoted_action_events == 0,
    "promotion must never cross the next physical input-bound event")

local direction_precursor = compiler.new({ character = "Luke", frame = 0 })
direction_precursor.events = {
    {
        id = 952,
        frame = 10,
        anchor = { kind = "double_tap" },
    },
    {
        id = 17,
        frame = 25,
        anchor = { kind = "movement_action" },
    },
}
local direction_precursor_result = compiler.finalize(direction_precursor, {
    motion_resolver = test_motion_resolver,
})
assert(#direction_precursor_result.steps == 1
    and direction_precursor_result.steps[1].id == 17,
    "an unmapped directional precursor must collapse into the observed dash Action")

local super_direction_buffer = compiler.new({ character = "Luke", frame = 0 })
super_direction_buffer.events = {
    {
        id = 516,
        frame = 10,
        anchor = { kind = "double_tap" },
    },
    {
        id = 1222,
        frame = 23,
        anchor = { kind = "button_press", pressed_buttons = 512 },
    },
}
local super_direction_buffer_result = compiler.finalize(super_direction_buffer, {
    motion_resolver = test_motion_resolver,
})
assert(#super_direction_buffer_result.steps == 1
    and super_direction_buffer_result.steps[1].id == 1222
    and super_direction_buffer_result.stats.fallback_motion_actions == 0,
    "a super motion's unmapped double-tap buffer must merge into its button Action")

local contact_fallback = compiler.new({ character = "Guile", frame = 0 })
contact_fallback.events = {
    {
        id = 922,
        frame = 10,
        expected_combo = 2,
        damage_at_step = 1380,
        has_hit = true,
        has_contact = true,
        anchor = {
            kind = "button_press",
            pressed_buttons = 16 | 32,
            held_buttons = 16 | 32,
            direction = "3",
            direction_sequence = "2363",
        },
    },
}
contact_fallback.max_combo = 2
contact_fallback.current_damage = 1380
contact_fallback.hit_contacts = 1
contact_fallback.input_anchor_count = 1
local contact_fallback_result = compiler.finalize(contact_fallback, {
    motion_resolver = test_motion_resolver,
})
assert(#contact_fallback_result.steps == 1
    and contact_fallback_result.steps[1].id == 922
    and contact_fallback_result.steps[1].motion == "236+LP+MP",
    "a contact-proven Action missing from the catalog must use normalized input notation")
assert(contact_fallback_result.stats.fallback_motion_actions == 1
    and contact_fallback_result.stats.input_derived_motion_actions == 1
    and contact_fallback_result.stats.unresolved_motion_actions == 0,
    "contact-proven input notation must remain distinct from unresolved motion")
local contact_fallback_evaluation = transcriber.evaluate({
    {
        id = 922,
        motion = "236+LP+MP",
        expected_combo = 2,
        damage_at_step = 1380,
        combo_stats = { damage = 1380 },
    },
}, contact_fallback_result, {
    input_source = "timeline",
    raw_inputs = { 0, 3, 3 | 16 | 32 },
    input_completed = true,
})
assert(contact_fallback_evaluation.ok == true
    and contact_fallback_evaluation.advisories[1]
        == "input_derived_contact_motion:1",
    "a contact-proven input-derived motion must be auditable without blocking transcription")

local jump_attack = compiler.new({ character = "Luke", frame = 0 })
local function jump_attack_observe(frame, action_id, input, combo, victim_hp)
    compiler.observe(jump_attack, {
        frame = frame,
        action_id = action_id,
        action_frame = frame,
        direct_input = input,
        facing_right = true,
        combo_count = combo or 0,
        actor_hp = 10000,
        victim_hp = victim_hp or 10000,
    })
end
jump_attack_observe(1, 10, 0)
jump_attack_observe(2, 10, 4 | 32)
jump_attack_observe(3, 37, 4 | 32)
jump_attack_observe(4, 651, 4 | 32, 1, 9510)
local jump_attack_result = compiler.finalize(jump_attack, {
    motion_resolver = test_motion_resolver,
})
assert(#jump_attack_result.steps == 2
    and jump_attack_result.steps[1].id == 37
    and jump_attack_result.steps[2].id == 651
    and jump_attack_result.steps[1].has_hit == false
    and jump_attack_result.steps[2].has_hit == true,
    "one jump+button input must retain both the movement setup and airborne attack Actions")
assert(jump_attack_result.stats.input_anchors == 1
    and jump_attack_result.stats.unresolved_anchors == 0,
    "movement continuation must reuse its physical input without inventing an anchor")

local delayed_jump_attack = compiler.new({ character = "Luke", frame = 0 })
local delayed_jump_rows = {
    { 1, 10, 8, 0, 10000 },
    { 2, 10, 9, 0, 10000 },
    { 3, 34, 9 | 32, 0, 10000 },
    { 4, 37, 8 | 32, 0, 10000 },
    { 5, 651, 8 | 32, 1, 9510 },
}
for _, row in ipairs(delayed_jump_rows) do
    compiler.observe(delayed_jump_attack, {
        frame = row[1],
        action_id = row[2],
        action_frame = row[1],
        direct_input = row[3],
        facing_right = true,
        combo_count = row[4],
        actor_hp = 10000,
        victim_hp = row[5],
    })
end
local delayed_jump_result = compiler.finalize(delayed_jump_attack, {
    motion_resolver = test_motion_resolver,
})
assert(#delayed_jump_result.steps == 2
    and delayed_jump_result.steps[1].id == 37
    and delayed_jump_result.steps[2].id == 651
    and delayed_jump_result.steps[2].has_hit == true,
    "a direction-edge anchor must carry its held attack through jump startup")
assert(delayed_jump_result.trace.suppressed_events[1].id == 34
    and delayed_jump_result.trace.suppressed_events[1].reason
        == "jump_startup_transition",
    "JUMP_F_BGN must collapse into the durable forward-jump Action")

local released_jump_attack = compiler.new({ character = "Luke", frame = 0 })
local released_jump_rows = {
    { 1, 10, 0, 0, 10000 },
    { 2, 10, 9, 0, 10000 },
    { 3, 34, 9 | 32, 0, 10000 },
    { 4, 37, 9, 0, 10000 },
    { 5, 651, 9, 1, 9510 },
}
for _, row in ipairs(released_jump_rows) do
    compiler.observe(released_jump_attack, {
        frame = row[1],
        action_id = row[2],
        action_frame = row[1],
        direct_input = row[3],
        facing_right = true,
        combo_count = row[4],
        actor_hp = 10000,
        victim_hp = row[5],
    })
end
local released_jump_result = compiler.finalize(released_jump_attack, {
    motion_resolver = test_motion_resolver,
})
assert(#released_jump_result.steps == 2
    and released_jump_result.steps[1].id == 37
    and released_jump_result.steps[2].id == 651
    and released_jump_result.steps[2].has_hit == true,
    "a release anchor must retain the attack that starts immediately after a jump")

local active_jump_double_tap = compiler.new({ character = "Luke", frame = 0 })
local function active_jump_observe(frame, action_id, input)
    compiler.observe(active_jump_double_tap, {
        frame = frame,
        action_id = action_id,
        action_frame = frame,
        direct_input = input,
        facing_right = true,
        combo_count = 0,
        actor_hp = 10000,
        victim_hp = 10000,
    })
end
active_jump_observe(1, 10, 0)
active_jump_observe(2, 10, 4)
active_jump_observe(3, 37, 4)
active_jump_observe(4, 37, 0)
active_jump_observe(5, 37, 4)
local active_jump_result = compiler.finalize(active_jump_double_tap, {
    motion_resolver = test_motion_resolver,
})
assert(#active_jump_result.steps == 1 and active_jump_result.steps[1].id == 37,
    "a horizontal double tap during an active jump must not duplicate the jump step")

local release_transition = compiler.new({ character = "Ryu", frame = 0 })
local function release_observe(frame, action_id, input, combo, victim_hp)
    compiler.observe(release_transition, {
        frame = frame,
        action_id = action_id,
        action_frame = frame,
        direct_input = input,
        facing_right = true,
        combo_count = combo or 0,
        actor_hp = 10000,
        victim_hp = victim_hp or 10000,
    })
end
release_observe(1, 10, 0)
release_observe(2, 10, 16)
release_observe(3, 600, 16)
release_observe(4, 600, 0)
release_observe(5, 601, 0)
release_observe(6, 601, 0, 1, 9700)
local release_result = compiler.finalize(release_transition, {
    motion_resolver = test_motion_resolver,
})
assert(#release_result.steps == 1 and release_result.steps[1].id == 600,
    "an unmapped button-release Action phase must merge into its input command")
assert(release_result.steps[1].motion == "236+LP"
    and release_result.steps[1].damage_at_step == 300,
    "resolved command text and contact truth must survive release-phase merging")
assert(release_result.stats.fallback_motion_actions == 0
    and release_result.stats.suppressed_action_events == 1,
    "a fully resolved command must expose no guessed motion")

local stale_release_jump = compiler.new({ character = "Guile", frame = 0 })
local function stale_release_observe(frame, action_id, input, combo, victim_hp)
    compiler.observe(stale_release_jump, {
        frame = frame,
        action_id = action_id,
        action_frame = frame,
        direct_input = input,
        facing_right = true,
        combo_count = combo or 0,
        actor_hp = 10000,
        victim_hp = victim_hp or 10000,
    })
end
stale_release_observe(1, 10, 0)
stale_release_observe(2, 10, 64)
stale_release_observe(3, 600, 64)
stale_release_observe(4, 600, 0)
for frame = 5, 39 do
    stale_release_observe(frame, 600, 0)
end
stale_release_observe(40, 34, 1)
stale_release_observe(41, 34, 1)
stale_release_observe(42, 994, 1 | 512)
stale_release_observe(43, 994, 1 | 512, 1, 9000)
local stale_release_result = compiler.finalize(stale_release_jump, {
    motion_resolver = test_motion_resolver,
})
assert(#stale_release_result.steps == 2
    and stale_release_result.steps[1].id == 600
    and stale_release_result.steps[2].id == 994,
    "a stale button release must not turn charge-move jump startup into a step")
for _, event in ipairs(stale_release_result.trace.input_bound_events) do
    assert(event.id ~= 34,
        "the internal jump startup must remain observation truth, not V2 input truth")
end
local saw_observed_jump_startup = false
for _, observed in ipairs(stale_release_result.trace.observed_actions) do
    if observed.id == 34 then saw_observed_jump_startup = true end
end
assert(saw_observed_jump_startup,
    "the raw Action trace must still retain the internal jump startup")

local landing_precursor = compiler.new({ character = "Ryu", frame = 0 })
local function landing_observe(frame, action_id, input, combo, victim_hp)
    compiler.observe(landing_precursor, {
        frame = frame,
        action_id = action_id,
        action_frame = frame,
        direct_input = input,
        facing_right = true,
        combo_count = combo or 0,
        actor_hp = 10000,
        victim_hp = victim_hp or 10000,
    })
end
landing_observe(1, 10, 0)
landing_observe(2, 10, 64)
landing_observe(3, 657, 64)
landing_observe(4, 657, 0)
landing_observe(5, 630, 0)
landing_observe(6, 630, 0, 1, 9600)
local landing_result = compiler.finalize(landing_precursor, {
    motion_resolver = test_motion_resolver,
})
assert(#landing_result.steps == 1 and landing_result.steps[1].id == 630,
    "an unmapped landing phase must yield to the mapped Action from the same input")
assert(landing_result.trace.suppressed_events[1].reason == "unmapped_input_precursor",
    "internal precursor suppression must remain auditable")

local raw_drive_rush = compiler.new({ character = "Ryu", frame = 0 })
local function dr_observe(frame, action_id, input)
    compiler.observe(raw_drive_rush, {
        frame = frame,
        action_id = action_id,
        action_frame = frame,
        direct_input = input,
        facing_right = true,
        combo_count = 0,
        actor_hp = 10000,
        victim_hp = 10000,
    })
end
dr_observe(1, 10, 0)
dr_observe(2, 10, 32 | 256)
dr_observe(3, 480, 32 | 256)
dr_observe(4, 480, 4)
dr_observe(5, 480, 0)
dr_observe(6, 740, 4)
local dr_result = compiler.finalize(raw_drive_rush, {
    motion_resolver = test_motion_resolver,
})
assert(#dr_result.steps == 1
    and dr_result.steps[1].id == 740
    and dr_result.steps[1].motion == "RAW DR",
    "a quick Drive Parry precursor must collapse into the real RAW DR command")

local explicit_parry_rush = compiler.new({ character = "Ryu", frame = 0 })
local function parry_observe(frame, action_id, input)
    compiler.observe(explicit_parry_rush, {
        frame = frame,
        action_id = action_id,
        action_frame = frame,
        direct_input = input,
        facing_right = true,
        combo_count = 0,
        actor_hp = 10000,
        victim_hp = 10000,
    })
end
parry_observe(1, 10, 0)
parry_observe(2, 10, 32 | 256)
parry_observe(3, 480, 32 | 256)
parry_observe(4, 480, 32 | 256)
parry_observe(5, 480, 32 | 256)
parry_observe(6, 480, 32 | 256)
parry_observe(7, 480, 32 | 256)
parry_observe(8, 480, 0)
parry_observe(9, 740, 0)
local explicit_parry_result = compiler.finalize(explicit_parry_rush, {
    motion_resolver = test_motion_resolver,
})
assert(#explicit_parry_result.steps == 2
    and explicit_parry_result.steps[1].motion == "DP"
    and explicit_parry_result.steps[2].motion == "RAW DR",
    "a held Drive Parry followed by a later rush must remain two commands")

local parry_back_repress = compiler.new({ character = "Ryu", frame = 0 })
local parry_back_rows = {
    { 1, 1029, 0 },
    { 2, 1029, 8 | 32 | 256 },
    { 3, 480, 8 | 32 | 256 },
    { 4, 480, 8 | 32 | 256 },
    { 5, 480, 8 | 32 | 256 },
    { 6, 480, 8 | 32 | 256 },
    { 7, 480, 32 | 256 },
    { 8, 480, 32 | 256 },
    { 9, 740, 8 | 32 | 256 },
}
for _, row in ipairs(parry_back_rows) do
    compiler.observe(parry_back_repress, {
        frame = row[1],
        action_id = row[2],
        action_frame = row[1],
        direct_input = row[3],
        facing_right = true,
        combo_count = 0,
        actor_hp = 10000,
        victim_hp = 10000,
    })
end
local parry_back_result = compiler.finalize(parry_back_repress, {
    motion_resolver = test_motion_resolver,
})
assert(#parry_back_result.steps == 1
    and parry_back_result.steps[1].id == 480,
    "4+PARRY followed by another 4 is not a 44 anchor: the button command owns the first frame")

local resolver_failure = compiler.finalize(session, {
    motion_resolver = function() error("synthetic resolver failure") end,
})
assert(resolver_failure.stats.fallback_motion_actions == 1
    and resolver_failure.stats.resolver_error_actions == 1,
    "resolver failures must be observable instead of silently accepting guessed motion")

local source = {
    {
        id = 999,
        motion = "OLD",
        expected_combo = 1,
        damage_at_step = 300,
        timeline = { "1f : 5", "1f : 2+LP" },
        combo_stats = { damage = 300 },
        dummy_counter_type = 2,
        _xt_meta = { schema = 2, created_at = "old" },
    },
}
local resolver_evaluation = transcriber.evaluate(source, resolver_failure, {
    input_source = "timeline",
    raw_inputs = { 0, 2, 18, 18, 2, 0 },
    input_completed = true,
})
assert(table.concat(resolver_evaluation.reasons, ",")
        == "unresolved_action_motion,motion_resolver_error",
    "batch transcription must reject candidates produced after a motion resolver error")
local evaluation = transcriber.evaluate(source, result, {
    input_source = "timeline",
    raw_inputs = { 0, 2, 18, 18, 2, 0 },
    input_completed = true,
})
assert(evaluation.ok == true, "matching runtime outcome must be transcribable")

local failed = transcriber.evaluate(source, {
    steps = result.steps,
    stats = {
        damage = 0,
        max_combo = 0,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 0, 16, 0 },
    input_completed = true,
})
assert(failed.ok == false and failed.reasons[1] == "damage_mismatch",
    "outcome mismatch must be reported instead of silently saved")
assert(failed.suspected_causes[1] == "first_hit_punish_counter",
    "known environment requirements must be attached to failed reports")

local resource_source = {
    {
        id = 600,
        motion = "LP",
        expected_combo = 0,
        combo_stats = { damage = 0, drive_used = 10000, super_used = 10000 },
        timeline = { "1f : 5+LP" },
    },
}
local resource_failure = transcriber.evaluate(resource_source, {
    steps = result.steps,
    stats = {
        damage = 0,
        max_combo = 0,
        drive_used = 0,
        super_used = 0,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 16 },
    input_completed = true,
})
assert(table.concat(resource_failure.reasons, ",")
        == "drive_consumption_mismatch,super_consumption_mismatch",
    "resource consumption must be validated independently from damage")
local legacy_resource_evaluation = transcriber.evaluate(resource_source, {
    steps = result.steps,
    stats = {
        damage = 0,
        max_combo = 0,
        drive_used = 0,
        super_used = 0,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 16 },
    input_completed = true,
    compare_drive_usage = false,
})
assert(table.concat(legacy_resource_evaluation.reasons, ",")
        == "super_consumption_mismatch",
    "legacy Drive totals may be advisory while Super consumption remains strict")

local legacy_damage_source = {
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        damage_at_step = 300,
        combo_stats = { damage = 300 },
    },
}
local legacy_damage_drift = transcriber.evaluate(legacy_damage_source, {
    steps = {
        {
            id = 600,
            motion = "LP",
            expected_combo = 1,
            damage_at_step = 360,
        },
    },
    stats = {
        damage = 360,
        max_combo = 1,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 16 },
    input_completed = true,
    allow_legacy_damage_drift = true,
})
assert(legacy_damage_drift.ok == true
    and legacy_damage_drift.source_action_match == true,
    "legacy damage drift is safe only when Action IDs and combo structure match")
local changed_action_drift = transcriber.evaluate(legacy_damage_source, {
    steps = {
        {
            id = 601,
            motion = "MP",
            expected_combo = 1,
            damage_at_step = 360,
        },
    },
    stats = {
        damage = 360,
        max_combo = 1,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 32 },
    input_completed = true,
    allow_legacy_damage_drift = true,
})
assert(changed_action_drift.ok == false
    and changed_action_drift.reasons[1] == "damage_mismatch",
    "a different Action must not hide behind legacy damage-drift tolerance")
local rebuilt_legacy_outcome = transcriber.evaluate(legacy_damage_source, {
    steps = {
        {
            id = 601,
            motion = "MP",
            expected_combo = 2,
            damage_at_step = 360,
        },
    },
    stats = {
        damage = 360,
        max_combo = 2,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 32 },
    input_completed = true,
    allow_legacy_outcome_rebuild = true,
})
assert(rebuilt_legacy_outcome.ok == true
    and #rebuilt_legacy_outcome.reasons == 0
    and #rebuilt_legacy_outcome.advisories == 2
    and rebuilt_legacy_outcome.source_action_match == false,
    "transcription may rebuild stale derived outcome fields before strict raw replay")

local action_variant_drift = transcriber.evaluate({
    {
        id = 854,
        motion = "DI",
        expected_combo = 1,
        damage_at_step = 800,
        combo_stats = { damage = 800 },
    },
}, {
    steps = {
        {
            id = 855,
            motion = "DI",
            expected_combo = 1,
            damage_at_step = 960,
        },
    },
    stats = {
        damage = 960,
        max_combo = 1,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 64 | 512 },
    input_completed = true,
    allow_legacy_damage_drift = true,
    action_ids_equivalent = function(expected_id, observed_id)
        local rule = CharacterRules.get_match_rule(nil, nil, "Ryu", expected_id)
        return ActionMatcher.matches_expected_action_id(
            { id = expected_id },
            observed_id,
            rule
        )
    end,
})
assert(action_variant_drift.ok == true
    and action_variant_drift.source_action_match == true,
    "explicit Action aliases must preserve structural matching across game versions")

local candidate = assert(transcriber.build_candidate(source, result, {
    schema = 2,
    product_id = "sf6cc",
    product_version = "1.0.4",
    json_id = "xt.combo_trial",
    json_version = "2",
}, "2026-07-30T00:00:00+08:00", {
    input_source = "timeline",
    raw_inputs = { 0, 2, 18, 18, 2, 0 },
}))
assert(candidate[1].id == 600 and candidate[1].motion == "2+LP",
    "candidate steps must come from the new runtime compiler")
assert(candidate[1].timeline[2] == "1f : 2+LP",
    "the input truth must be copied without rewriting")
assert(#candidate[1].raw_inputs == 6 and candidate[1].raw_inputs[3] == 18,
    "timeline transcription must emit a frame-accurate raw input stream")
assert(candidate[1]._xt_meta.transcription.raw_inputs_origin == "captured_timeline_replay",
    "candidate metadata must disclose how raw input was obtained")
assert(candidate[1]._xt_meta.created_at == "old"
    and candidate[1]._xt_meta.updated_at == "2026-07-30T00:00:00+08:00",
    "metadata must be preserved and updated independently")

local synchronized_candidate = assert(transcriber.build_candidate({
    {
        id = 600,
        motion = "LP",
        recorded_by = 0,
        scene_state = {
            recorded_by = 0,
            players = {
                p1 = { resources = { hp = 10000 } },
                p2 = {
                    resources = { hp = 8000, drive = 30000 },
                    status = { burnout = false },
                },
            },
        },
        snapshot_gauges = {
            attacker = { current_hp = 2500, heal_hp = 2500, max_hp = 10000 },
            victim = { current_hp = 8000, heal_hp = 9000, max_hp = 10000 },
            defender_drive = 0,
            defender_burnout = true,
        },
    },
}, result, {
    schema = 2,
    product_id = "sf6cc",
    product_version = "1.0.4",
    json_id = "xt.combo_trial",
    json_version = "2",
}, "2026-07-30T00:00:00+08:00", {
    input_source = "timeline",
    raw_inputs = { 16 },
    source_advisories = { "source_damage_rebuilt:expected=300:observed=360" },
}))
assert(synchronized_candidate[1].snapshot_gauges.attacker.current_hp == 10000
    and synchronized_candidate[1].snapshot_gauges.attacker.heal_hp == 10000
    and synchronized_candidate[1].snapshot_gauges.victim.heal_hp == 9000
    and synchronized_candidate[1].snapshot_gauges.defender_drive == 30000
    and synchronized_candidate[1].snapshot_gauges.defender_burnout == false,
    "candidate output must keep V2 scene and legacy WTT settings coherent")
assert(synchronized_candidate[1]._xt_meta.transcription.synchronized_legacy_scene_fields == 4
    and #synchronized_candidate[1]._xt_meta.transcription.source_advisories == 1,
    "candidate metadata must disclose compatibility rewrites and source drift")

local verified = transcriber.verify_candidate(candidate, result, {
    raw_inputs = candidate[1].raw_inputs,
    input_completed = true,
})
assert(verified.ok == true,
    "a generated raw stream must reproduce its compiled Action and outcome truth")
local verification_failure = transcriber.verify_candidate(candidate, {
    steps = {
        {
            id = 601,
            expected_combo = 0,
            damage_at_step = 0,
            delay_from_prev = 0,
        },
    },
    stats = {
        damage = 0,
        max_combo = 0,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    raw_inputs = candidate[1].raw_inputs,
    input_completed = true,
})
assert(verification_failure.ok == false
    and table.concat(verification_failure.reasons, ","):match("raw_replay_action_id_mismatch"),
    "raw replay verification must reject streams that execute a different Action")
assert(transcriber.mark_raw_replay_verified(candidate, "2026-07-30T00:01:00+08:00")
    and candidate[1]._xt_meta.transcription.raw_replay_verified == true,
    "verified candidates must carry a machine-readable verification marker")

local pressure_candidate = assert(transcriber.build_candidate({
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        damage_at_step = 300,
        combo_stats = { damage = 300 },
    },
}, {
    steps = {
        {
            id = 600,
            motion = "LP",
            expected_combo = 1,
            damage_at_step = 300,
            has_hit = true,
            has_contact = true,
        },
        {
            id = 17,
            motion = "66",
            expected_combo = 0,
            damage_at_step = 300,
            has_hit = false,
            has_contact = false,
        },
        {
            id = 666,
            motion = "6+HP",
            expected_combo = 0,
            damage_at_step = 300,
            has_hit = false,
            has_contact = true,
            hit_result = "block",
            was_blocked = true,
        },
    },
    stats = {
        damage = 300,
        max_combo = 1,
        block_contacts = 1,
    },
}, {
    schema = 2,
    product_id = "sf6cc",
    product_version = "1.0.4",
    json_id = "xt.combo_trial",
    json_version = "2",
}, "2026-07-30T00:00:00+08:00"))
assert(pressure_candidate[3].validation_role == "pressure_tail",
    "a post-hit terminal Action with no new damage must be marked automatically")

local resumed = assert(transcriber.resume_run({
    character = "Ryu",
    started_at = "2026-07-30T00:00:00+08:00",
    candidate_root = "TrainingComboTrials_data/TranscribedCandidates/Ryu/run1",
    report_path = "TrainingComboTrials_data/TranscriptionReports/Ryu_run1.json",
    items = {
        {
            source_file = "TrainingComboTrials_data\\CustomCombos\\Ryu\\A.json",
            status = "passed",
            raw_replay_verified = true,
        },
        {
            source_file = "trainingcombotrials_data/customcombos/ryu/B.json",
            status = "failed",
            raw_replay_verified = false,
            validation_revision = transcriber.VALIDATION_REVISION,
        },
    },
}, "Ryu", {
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\A.json",
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\B.json",
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\C.json",
}, "2026-07-30T01:00:00+08:00"))
assert(#resumed.paths == 1 and resumed.paths[1]:match("C%.json$"),
    "resume must skip every source already recorded in the report")
assert(resumed.index == 2 and resumed.total == 3
    and resumed.passed == 1 and resumed.failed == 1,
    "resume must preserve progress and result counters")
assert(resumed.output_dir:match("run1$")
    and resumed.report_path:match("Ryu_run1%.json$"),
    "resume must append to the original candidate directory and report")

local unverified_remaining, retained_count = transcriber.remaining_paths({
    items = {
        {
            source_file = "TrainingComboTrials_data\\CustomCombos\\Ryu\\A.json",
            status = "passed",
        },
        {
            source_file = "TrainingComboTrials_data\\CustomCombos\\Ryu\\B.json",
            status = "failed",
            raw_replay_verified = false,
            validation_revision = transcriber.VALIDATION_REVISION,
        },
    },
}, {
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\A.json",
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\B.json",
})
assert(#unverified_remaining == 1 and unverified_remaining[1]:match("A%.json$")
    and retained_count == 1,
    "resume must revalidate legacy passes while retaining already classified failures")

local legacy_failure_remaining, legacy_failure_retained = transcriber.remaining_paths({
    items = {
        {
            source_file = "TrainingComboTrials_data\\CustomCombos\\Ryu\\A.json",
            status = "failed",
        },
        {
            source_file = "TrainingComboTrials_data\\CustomCombos\\Ryu\\B.json",
            status = "failed",
            raw_replay_verified = false,
            validation_revision = transcriber.VALIDATION_REVISION,
        },
    },
}, {
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\A.json",
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\B.json",
})
assert(#legacy_failure_remaining == 1
    and legacy_failure_remaining[1]:match("A%.json$")
    and legacy_failure_retained == 1,
    "resume must revalidate legacy failures but retain failures classified by the new flow")

local stale_failure_remaining, stale_failure_retained = transcriber.remaining_paths({
    items = {
        {
            source_file = "TrainingComboTrials_data\\CustomCombos\\Ryu\\A.json",
            status = "failed",
            raw_replay_verified = false,
            validation_revision = transcriber.VALIDATION_REVISION - 1,
        },
        {
            source_file = "TrainingComboTrials_data\\CustomCombos\\Ryu\\B.json",
            status = "failed",
            raw_replay_verified = false,
            validation_revision = transcriber.VALIDATION_REVISION,
        },
    },
}, {
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\A.json",
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\B.json",
})
assert(#stale_failure_remaining == 1
    and stale_failure_remaining[1]:match("A%.json$")
    and stale_failure_retained == 1,
    "resume must revalidate failures when the validation policy revision changes")

local explicit_failure_retry = transcriber.failed_source_paths({
    character = "Guile",
    items = {
        {
            source_file = "TrainingComboTrials_data\\CustomCombos\\Guile\\A.json",
            status = "passed",
            raw_replay_verified = true,
        },
        {
            source_file = "TrainingComboTrials_data\\CustomCombos\\Guile\\B.json",
            status = "failed",
            raw_replay_verified = false,
            validation_revision = transcriber.VALIDATION_REVISION,
        },
        {
            source_file = "trainingcombotrials_data/customcombos/guile/B.json",
            status = "failed",
        },
    },
})
assert(#explicit_failure_retry == 1
    and explicit_failure_retry[1]:match("B%.json$"),
    "manual environment changes must be able to retry only current transcription failures")

local environment_source = {
    {
        dummy_guard_type = 2,
        dummy_guard_switching = true,
        dummy_counter_type = 2,
        snapshot_gauges = {
            attacker = { current_hp = 2000, max_hp = 10000 },
            victim = { current_hp = 8000, heal_hp = 9000, max_hp = 10000 },
        },
        recorded_by = 0,
        scene_state = {
            recorded_by = 0,
            players = {
                p1 = {
                    unique = { stock = 1 },
                    resources = { hp = 2000 },
                    status = { burnout = false },
                },
                p2 = {
                    resources = { hp = 8000 },
                    status = { burnout = true },
                },
            },
        },
    },
}
local causes = transcriber.suspected_causes(environment_source)
assert(table.concat(causes, ",")
        == "first_hit_punish_counter,actor_low_health,actor_character_resource_required,"
            .. "defender_burnout,defender_virtual_damage,defender_guard_state_change",
    "failed reports must identify all known scene prerequisites without changing Action truth")

print("combo action event compiler tests passed")
