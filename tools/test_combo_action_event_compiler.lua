package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local compiler = dofile("autorun/func/ComboTrials/ActionEventCompiler.lua")
local transcriber = dofile("autorun/func/ComboTrials/Transcriber.lua")
local CharacterRules = require("func/ComboTrials/CharacterRules")
local ActionMatcher = require("func/ComboTrials/ActionMatcher")
local SceneState = require("func/ComboTrials/SceneState")

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
        [33] = "8",
        [34] = "8",
        [35] = "7",
        [36] = "8",
        [37] = "9",
        [38] = "7",
        [480] = "DP",
        [600] = "236+LP",
        [630] = "2+HP",
        [651] = "j.MP",
        [740] = "RAW DR",
        [900] = "236+K",
        [903] = "236+KK",
        [904] = "236+KK",
        [905] = "Normal",
        [908] = "6",
        [994] = "[2]8+HK",
        [1222] = "236236+K",
    }
    if motions[action_id] then
        local metadata = action_id == 904 and {
            ownership = "type20_action_phase",
            inherited_from_action_id = 903,
        } or nil
        return motions[action_id], "loaded", metadata
    end
    return nil, "action_id_missing"
end

local inherited_phase_followup = compiler.new({ character = "Kimberly", frame = 0 })
inherited_phase_followup.events = {
    {
        id = 903,
        frame = 10,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "button_release", released_buttons = 128 },
    },
    {
        id = 904,
        frame = 12,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "button_press", pressed_buttons = 128 },
    },
    {
        id = 908,
        frame = 18,
        has_hit = true,
        has_contact = true,
        expected_combo = 1,
        damage_at_step = 500,
        anchor = { kind = "button_release", released_buttons = 128 },
    },
}
inherited_phase_followup.max_combo = 1
inherited_phase_followup.current_damage = 500
inherited_phase_followup.hit_contacts = 1
local inherited_phase_result = compiler.finalize(inherited_phase_followup, {
    motion_resolver = test_motion_resolver,
})
assert(#inherited_phase_result.steps == 2
    and inherited_phase_result.steps[1].id == 903
    and inherited_phase_result.steps[2].id == 908,
    "a verified owner and its immediate type-20 phase must remain one command")
assert(inherited_phase_result.steps[2].motion == ">LK"
    and inherited_phase_result.stats.input_refined_motion_actions == 1,
    "an underspecified follow-up must use the actual player button edge")
local inherited_phase_evaluation = transcriber.evaluate({
    {
        id = 903,
        motion = "236+KK",
        expected_combo = 0,
        damage_at_step = 0,
        combo_stats = { damage = 500 },
    },
    {
        id = 908,
        motion = ">LK",
        expected_combo = 1,
        damage_at_step = 500,
    },
}, inherited_phase_result, {
    input_source = "raw_inputs",
    raw_inputs = { 0, 128, 0 },
    input_completed = true,
})
assert(inherited_phase_evaluation.ok == true
    and inherited_phase_evaluation.advisories[1]
        == "input_refined_followup_motion:1",
    "input-refined follow-up notation must remain accepted and auditable")
assert(inherited_phase_result.trace.suppressed_events[1].id == 904
    and inherited_phase_result.trace.suppressed_events[1].reason
        == "redundant_inherited_action_phase",
    "type-20 phase projection must remain explicit in the audit trace")

local generic_followup = compiler.new({ character = "Kimberly", frame = 0 })
generic_followup.events = {
    {
        id = 900,
        frame = 20,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "button_release", released_buttons = 128 },
    },
    {
        id = 905,
        frame = 28,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "button_release", released_buttons = 32 },
    },
}
local generic_followup_result = compiler.finalize(generic_followup, {
    motion_resolver = test_motion_resolver,
})
assert(#generic_followup_result.steps == 2
    and generic_followup_result.steps[1].motion == "236+K"
    and generic_followup_result.steps[2].motion == ">MP",
    "a catalog 'Normal' immediately after a setup Action must expose its real button")

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

local function cviper_delayed_motion_resolver(action_id)
    if action_id == 608 then return "HK", "strict_route" end
    if action_id == 930 then return "236+KK", "strict_route" end
    if action_id == 905 then return "236+PP", "strict_route" end
    if action_id == 969 then return "623+LP", "strict_route" end
    if action_id == 971 then return "623+MP", "strict_route" end
    if action_id == 973 then return "623+PP", "strict_route" end
    if action_id == 961 then return "j.236+HK", "strict_route" end
    if action_id == 1036 then return "528", "route_unverified" end
    if action_id == 1037 then return "528", "route_unverified" end
    if action_id == 1200 then return "236236+K", "strict_route" end
    if action_id == 1218 then return "214214+K", "strict_route" end
    return nil, "route_unverified"
end

local buffered_super = compiler.new({ character = "CViper", frame = 0 })
local function buffered_super_observe(frame, action_id, input)
    compiler.observe(buffered_super, {
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
buffered_super_observe(1, 930, 0)
buffered_super_observe(2, 930, 128)
buffered_super_observe(3, 930, 0)
buffered_super_observe(4, 936, 0)
buffered_super_observe(5, 1218, 0)
local buffered_super_result = compiler.finalize(buffered_super, {
    motion_resolver = cviper_delayed_motion_resolver,
})
assert(#buffered_super_result.steps == 1
    and buffered_super_result.steps[1].id == 1218
    and buffered_super_result.steps[1].motion == "214214+K"
    and buffered_super_result.trace.input_bound_events[1].anchor.kind
        == "button_press"
    and buffered_super_result.trace.promoted_events[1].from_id == 936,
    "a short release must not replace the press that launches a delayed durable Action")

local release_ghost = compiler.new({ character = "CViper", frame = 0 })
release_ghost.events = {
    {
        id = 608,
        frame = 10,
        has_hit = true,
        has_contact = true,
        expected_combo = 4,
        damage_at_step = 2850,
        anchor = { kind = "button_press", pressed_buttons = 512 },
    },
    {
        id = 1037,
        frame = 33,
        has_hit = false,
        has_contact = false,
        expected_combo = 0,
        damage_at_step = 2850,
        anchor = { kind = "button_release", released_buttons = 512 },
    },
    {
        id = 930,
        frame = 35,
        has_hit = true,
        has_contact = true,
        expected_combo = 10,
        damage_at_step = 5750,
        anchor = { kind = "button_press", pressed_buttons = 768 },
    },
}
release_ghost.current_damage = 5750
release_ghost.max_combo = 10
local release_ghost_result = compiler.finalize(release_ghost, {
    motion_resolver = cviper_delayed_motion_resolver,
})
assert(#release_ghost_result.steps == 2
    and release_ghost_result.steps[1].id == 608
    and release_ghost_result.steps[2].id == 930
    and release_ghost_result.trace.suppressed_events[1].id == 1037
    and release_ghost_result.trace.suppressed_events[1].reason
        == "ghost_release_transition",
    "transcription must suppress the same short release Ghost ignored by the live UI")

local direction_cancel = compiler.new({ character = "CViper", frame = 0 })
local function direction_cancel_observe(frame, action_id, input)
    compiler.observe(direction_cancel, {
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
direction_cancel_observe(1, 10, 0)
direction_cancel_observe(2, 10, 16)
direction_cancel_observe(3, 10, 0)
direction_cancel_observe(4, 969, 0)
direction_cancel_observe(5, 969, 2)
direction_cancel_observe(6, 969, 1)
direction_cancel_observe(7, 969, 1)
direction_cancel_observe(8, 1037, 1)
local direction_cancel_result = compiler.finalize(direction_cancel, {
    motion_resolver = cviper_delayed_motion_resolver,
})
assert(#direction_cancel_result.steps == 2
    and direction_cancel_result.steps[1].id == 969
    and direction_cancel_result.steps[2].id == 1037
    and direction_cancel_result.steps[2].motion == "528"
    and direction_cancel_result.trace.input_bound_events[2].anchor.kind
        == "direction_action",
    "a real direction-triggered high-jump cancel must remain a visible Action step")

local unverified_direction_precursor =
    compiler.new({ character = "CViper", frame = 0 })
unverified_direction_precursor.events = {
    {
        id = 1037,
        frame = 10,
        has_hit = true,
        has_contact = true,
        expected_combo = 2,
        damage_at_step = 1280,
        anchor = { kind = "button_press", pressed_buttons = 32 },
    },
    {
        id = 1037,
        frame = 30,
        has_hit = false,
        has_contact = false,
        expected_combo = 0,
        damage_at_step = 1280,
        anchor = { kind = "direction_action" },
    },
}
unverified_direction_precursor.observed_actions = {
    { id = 971, frame = 12, action_frame = 0 },
    { id = 1037, frame = 30, action_frame = 0 },
}
unverified_direction_precursor.current_damage = 1280
unverified_direction_precursor.max_combo = 2
local unverified_direction_result =
    compiler.finalize(unverified_direction_precursor, {
        motion_resolver = cviper_delayed_motion_resolver,
    })
assert(#unverified_direction_result.steps == 2
    and unverified_direction_result.steps[1].id == 971
    and unverified_direction_result.steps[2].id == 1037
    and unverified_direction_result.trace.promoted_events[1].from_id == 1037
    and unverified_direction_result.trace.promoted_events[1].to_id == 971,
    "a direction-only Action bound to an attack press must promote to the durable attack")

local source_bound_direction_precursor =
    compiler.new({ character = "CViper", frame = 0 })
source_bound_direction_precursor.events = {
    {
        id = 1037,
        frame = 10,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "button_press", pressed_buttons = 48 },
    },
    {
        id = 973,
        frame = 12,
        has_hit = true,
        has_contact = true,
        expected_combo = 4,
        damage_at_step = 2400,
        anchor = { kind = "button_release", released_buttons = 48 },
    },
}
source_bound_direction_precursor.current_damage = 2400
source_bound_direction_precursor.max_combo = 4
local source_bound_direction_result =
    compiler.finalize(source_bound_direction_precursor, {
        motion_resolver = cviper_delayed_motion_resolver,
    })
assert(#source_bound_direction_result.steps == 1
    and source_bound_direction_result.steps[1].id == 973
    and source_bound_direction_result.trace.suppressed_events[1].id == 1037
    and source_bound_direction_result.trace.suppressed_events[1].reason
        == "unverified_direction_button_precursor",
    "a source-bound durable attack must absorb its unexplained direction precursor")

local unmapped_direction_precursor =
    compiler.new({ character = "CViper", frame = 0 })
unmapped_direction_precursor.events = {
    {
        id = 1023,
        frame = 10,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "direction_action", direction = "8" },
    },
    {
        id = 961,
        frame = 13,
        has_hit = true,
        has_contact = true,
        expected_combo = 3,
        damage_at_step = 2220,
        anchor = { kind = "button_press", pressed_buttons = 512 },
    },
}
unmapped_direction_precursor.current_damage = 2220
unmapped_direction_precursor.max_combo = 3
local unmapped_direction_result =
    compiler.finalize(unmapped_direction_precursor, {
        motion_resolver = cviper_delayed_motion_resolver,
    })
assert(#unmapped_direction_result.steps == 1
    and unmapped_direction_result.steps[1].id == 961
    and unmapped_direction_result.trace.suppressed_events[1].id == 1023
    and unmapped_direction_result.trace.suppressed_events[1].reason
        == "unmapped_input_precursor",
    "an unmapped direction startup must yield to its immediate button Action")

local elena_direction_transition =
    compiler.new({ character = "Elena", frame = 0 })
elena_direction_transition.events = {
    {
        id = 900,
        frame = 10,
        has_hit = true,
        has_contact = true,
        expected_combo = 10,
        damage_at_step = 2739,
        anchor = { kind = "button_press", pressed_buttons = 128 },
    },
    {
        id = 904,
        frame = 67,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "direction_action", direction = "1" },
    },
    {
        id = 910,
        frame = 78,
        has_hit = true,
        has_contact = true,
        expected_combo = 11,
        damage_at_step = 3039,
        anchor = { kind = "button_press", pressed_buttons = 128 },
    },
}
elena_direction_transition.current_damage = 3039
elena_direction_transition.max_combo = 11
local function elena_motion_resolver(action_id)
    if action_id == 900 then return "236+LK", "strict_route" end
    if action_id == 910 then return "623+LK", "strict_route" end
    return nil, "action_id_missing"
end
local elena_direction_result =
    compiler.finalize(elena_direction_transition, {
        motion_resolver = elena_motion_resolver,
    })
assert(#elena_direction_result.steps == 2
    and elena_direction_result.steps[1].id == 900
    and elena_direction_result.steps[2].id == 910
    and elena_direction_result.stats.unresolved_motion_actions == 0
    and elena_direction_result.trace.suppressed_events[1].id == 904
    and elena_direction_result.trace.suppressed_events[1].reason
        == "unmapped_direction_transition",
    "an unmapped contact-free direction state must not become a V2 command")

local state_specific_di = compiler.new({ character = "Elena", frame = 0 })
state_specific_di.events = {
    {
        id = 856,
        frame = 20,
        has_hit = true,
        has_contact = true,
        expected_combo = 1,
        damage_at_step = 960,
        anchor = {
            kind = "button_press",
            direction = "6",
            pressed_buttons = 64 | 512,
            held_buttons = 64 | 512,
        },
    },
}
state_specific_di.current_damage = 960
state_specific_di.max_combo = 1
local state_specific_di_result = compiler.finalize(state_specific_di, {
    motion_resolver = elena_motion_resolver,
})
assert(#state_specific_di_result.steps == 1
    and state_specific_di_result.steps[1].id == 856
    and state_specific_di_result.steps[1].motion == "DI"
    and state_specific_di_result.stats.input_derived_motion_actions == 1
    and state_specific_di_result.stats.unresolved_motion_actions == 0,
    "an unmapped state-specific HP+HK Action must preserve its ID and display DI")

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

local honda_super_contact_phase = compiler.new({ character = "EHonda", frame = 0 })
honda_super_contact_phase.events = {
    {
        id = 1221,
        frame = 100,
        expected_combo = 20,
        damage_at_step = 4774,
        has_hit = false,
        has_contact = false,
        anchor = {
            kind = "button_press",
            pressed_buttons = 64,
            initial_action_id = 902,
        },
    },
    {
        id = 1222,
        frame = 167,
        expected_combo = 23,
        damage_at_step = 7024,
        has_hit = true,
        has_contact = true,
        anchor = {
            kind = "button_press",
            pressed_buttons = 32 | 256,
            initial_action_id = 1221,
        },
    },
}
honda_super_contact_phase.current_damage = 7024
honda_super_contact_phase.max_combo = 23
local honda_super_contact_result = compiler.finalize(honda_super_contact_phase, {
    motion_resolver = function(action_id)
        if action_id == 1221 then return "214214+P", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#honda_super_contact_result.steps == 1
    and honda_super_contact_result.steps[1].id == 1221
    and honda_super_contact_result.steps[1].motion == "214214+P"
    and honda_super_contact_result.steps[1].expected_combo == 23
    and honda_super_contact_result.steps[1].damage_at_step == 7024
    and honda_super_contact_result.steps[1].has_hit == true
    and honda_super_contact_result.stats.fallback_motion_actions == 0
    and honda_super_contact_result.trace.suppressed_events[1].id == 1222
    and honda_super_contact_result.trace.suppressed_events[1].merged_into == 1221
    and honda_super_contact_result.trace.suppressed_events[1].reason
        == "character_internal_action_phase",
    "Honda's unmapped super contact phase must merge into the real super command")

local alex_super_recovery_phase = compiler.new({ character = "Alex", frame = 0 })
alex_super_recovery_phase.events = {
    {
        id = 1208,
        frame = 100,
        expected_combo = 4,
        damage_at_step = 3620,
        has_hit = true,
        has_contact = true,
        anchor = {
            kind = "button_press",
            pressed_buttons = 64,
        },
    },
    {
        id = 1209,
        frame = 209,
        expected_combo = 0,
        damage_at_step = 3620,
        has_hit = false,
        has_contact = false,
        anchor = {
            kind = "double_tap",
            held_buttons = 32 | 256,
            initial_action_id = 1208,
        },
    },
    {
        id = 500,
        frame = 244,
        expected_combo = 0,
        damage_at_step = 3620,
        has_hit = false,
        has_contact = false,
        anchor = {
            kind = "double_tap",
            held_buttons = 32 | 256,
            initial_action_id = 1209,
        },
    },
}
alex_super_recovery_phase.current_damage = 3620
alex_super_recovery_phase.max_combo = 4
local alex_super_recovery_result = compiler.finalize(alex_super_recovery_phase, {
    motion_resolver = function(action_id)
        if action_id == 1208 then return "214214+P", "strict_route" end
        if action_id == 500 then return "RAW DR", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#alex_super_recovery_result.steps == 2
    and alex_super_recovery_result.steps[1].id == 1208
    and alex_super_recovery_result.steps[2].id == 500
    and alex_super_recovery_result.stats.fallback_motion_actions == 0
    and alex_super_recovery_result.trace.suppressed_events[1].id == 1209
    and alex_super_recovery_result.trace.suppressed_events[1].merged_into == 1208
    and alex_super_recovery_result.trace.suppressed_events[1].reason
        == "character_internal_action_phase",
    "Alex's unmapped super recovery phase must merge into the real super command")

local alex_hp_contact_phase = compiler.new({ character = "Alex", frame = 0 })
alex_hp_contact_phase.events = {
    {
        id = 608,
        frame = 100,
        expected_combo = 0,
        damage_at_step = 1600,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "button_press", pressed_buttons = 64 },
    },
    {
        id = 610,
        frame = 119,
        expected_combo = 3,
        damage_at_step = 2300,
        has_hit = true,
        has_contact = true,
        anchor = {
            kind = "button_press",
            pressed_buttons = 64,
            initial_action_id = 608,
        },
    },
    {
        id = 901,
        frame = 138,
        expected_combo = 4,
        damage_at_step = 2900,
        has_hit = true,
        has_contact = true,
        anchor = { kind = "button_press", pressed_buttons = 32 },
    },
}
alex_hp_contact_phase.current_damage = 2900
alex_hp_contact_phase.max_combo = 4
local alex_hp_contact_result = compiler.finalize(alex_hp_contact_phase, {
    motion_resolver = function(action_id)
        if action_id == 608 then return "HP", "strict_route" end
        if action_id == 901 then return "214+MP", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#alex_hp_contact_result.steps == 2
    and alex_hp_contact_result.steps[1].id == 608
    and alex_hp_contact_result.steps[1].expected_combo == 3
    and alex_hp_contact_result.steps[1].damage_at_step == 2300
    and alex_hp_contact_result.steps[2].id == 901
    and alex_hp_contact_result.stats.fallback_motion_actions == 0
    and alex_hp_contact_result.trace.suppressed_events[1].id == 610
    and alex_hp_contact_result.trace.suppressed_events[1].merged_into == 608
    and alex_hp_contact_result.trace.suppressed_events[1].reason
        == "character_internal_action_phase",
    "Alex's unmapped HP contact phase must merge into the real HP command")

local alex_hp_release_phase = compiler.new({ character = "Alex", frame = 0 })
alex_hp_release_phase.events = {
    {
        id = 976,
        frame = 100,
        expected_combo = 0,
        damage_at_step = 1000,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "button_press", pressed_buttons = 64 },
    },
    {
        id = 977,
        frame = 101,
        expected_combo = 2,
        damage_at_step = 1960,
        has_hit = true,
        has_contact = true,
        anchor = {
            kind = "button_release",
            released_buttons = 64,
            initial_action_id = 976,
        },
    },
}
alex_hp_release_phase.current_damage = 1960
alex_hp_release_phase.max_combo = 2
local alex_hp_release_result = compiler.finalize(alex_hp_release_phase, {
    motion_resolver = function(action_id)
        if action_id == 976 then return "HP", "strict_route" end
        if action_id == 977 then return ">HP (INSTANT)", "runtime_verified_override" end
        return nil, "action_id_missing"
    end,
})
assert(#alex_hp_release_result.steps == 1
    and alex_hp_release_result.steps[1].id == 976
    and alex_hp_release_result.steps[1].motion == "HP"
    and alex_hp_release_result.steps[1].expected_combo == 2
    and alex_hp_release_result.steps[1].damage_at_step == 1960
    and alex_hp_release_result.steps[1].has_hit == true
    and alex_hp_release_result.trace.suppressed_events[1].id == 977
    and alex_hp_release_result.trace.suppressed_events[1].merged_into == 976
    and alex_hp_release_result.trace.suppressed_events[1].reason
        == "character_internal_action_phase",
    "Alex's mapped HP release phase must merge only after Action 976")

local cammy_target_combo_phase = compiler.new({ character = "Cammy", frame = 0 })
cammy_target_combo_phase.events = {
    {
        id = 652,
        frame = 100,
        expected_combo = 4,
        damage_at_step = 1584,
        has_hit = true,
        has_contact = true,
        anchor = { kind = "button_press", pressed_buttons = 512 },
    },
    {
        id = 653,
        frame = 127,
        expected_combo = 5,
        damage_at_step = 1752,
        has_hit = true,
        has_contact = true,
        anchor = { kind = "button_press", pressed_buttons = 512 },
    },
    {
        id = 902,
        frame = 162,
        expected_combo = 6,
        damage_at_step = 1977,
        has_hit = true,
        has_contact = true,
        anchor = { kind = "button_press", pressed_buttons = 256 },
    },
}
cammy_target_combo_phase.current_damage = 1977
cammy_target_combo_phase.max_combo = 6
local cammy_target_combo_result = compiler.finalize(cammy_target_combo_phase, {
    motion_resolver = function(action_id)
        if action_id == 652 then return ">HK", "strict_route" end
        if action_id == 902 then return "236+MK", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#cammy_target_combo_result.steps == 2
    and cammy_target_combo_result.steps[1].id == 652
    and cammy_target_combo_result.steps[1].expected_combo == 5
    and cammy_target_combo_result.steps[1].damage_at_step == 1752
    and cammy_target_combo_result.steps[2].id == 902
    and cammy_target_combo_result.trace.suppressed_events[1].id == 653
    and cammy_target_combo_result.trace.suppressed_events[1].reason
        == "character_internal_action_phase",
    "Cammy's second target-combo contact Action must merge into its command owner")

local cammy_internal_recovery = compiler.new({ character = "Cammy", frame = 0 })
cammy_internal_recovery.events = {
    {
        id = 916,
        frame = 100,
        expected_combo = 1,
        damage_at_step = 500,
        has_hit = true,
        has_contact = true,
        anchor = { kind = "button_press", pressed_buttons = 256 },
    },
    {
        id = 933,
        frame = 118,
        expected_combo = 0,
        damage_at_step = 500,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "button_press", pressed_buttons = 256 },
    },
    {
        id = 500,
        frame = 180,
        expected_combo = 0,
        damage_at_step = 500,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "double_tap", held_buttons = 288 },
    },
    {
        id = 1022,
        frame = 220,
        expected_combo = 2,
        damage_at_step = 1000,
        has_hit = true,
        has_contact = true,
        anchor = { kind = "button_press", pressed_buttons = 512 },
    },
    {
        id = 1023,
        frame = 255,
        expected_combo = 0,
        damage_at_step = 1000,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "button_press", pressed_buttons = 512 },
    },
}
cammy_internal_recovery.current_damage = 1000
cammy_internal_recovery.max_combo = 2
local cammy_internal_recovery_result = compiler.finalize(cammy_internal_recovery, {
    motion_resolver = function(action_id)
        if action_id == 916 then return "623+MK", "strict_route" end
        if action_id == 500 then return "RAW DR", "strict_route" end
        if action_id == 1022 then return "j.214+HK", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#cammy_internal_recovery_result.steps == 3
    and cammy_internal_recovery_result.steps[1].id == 916
    and cammy_internal_recovery_result.steps[2].id == 500
    and cammy_internal_recovery_result.steps[3].id == 1022
    and cammy_internal_recovery_result.trace.suppressed_events[1].id == 933
    and cammy_internal_recovery_result.trace.suppressed_events[2].id == 1023,
    "Cammy's grounded and aerial recovery phases must not become instructions")

local cammy_air_throw_chord = compiler.new({ character = "Cammy", frame = 0 })
cammy_air_throw_chord.events = {
    {
        id = 966,
        frame = 100,
        expected_combo = 0,
        damage_at_step = 0,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "button_press", pressed_buttons = 16 },
    },
    {
        id = 979,
        frame = 101,
        expected_combo = 0,
        damage_at_step = 0,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "button_press", pressed_buttons = 128 },
    },
    {
        id = 981,
        frame = 110,
        expected_combo = 1,
        damage_at_step = 1150,
        has_hit = true,
        has_contact = true,
        anchor = { kind = "button_press", pressed_buttons = 144 },
    },
}
cammy_air_throw_chord.current_damage = 1150
cammy_air_throw_chord.max_combo = 1
local cammy_air_throw_result = compiler.finalize(cammy_air_throw_chord, {
    motion_resolver = function(action_id)
        if action_id == 966 then return "j.P", "route_unverified" end
        if action_id == 979 then return "j.Throw", "route_unverified" end
        return nil, "action_id_missing"
    end,
})
assert(#cammy_air_throw_result.steps == 1
    and cammy_air_throw_result.steps[1].id == 979
    and cammy_air_throw_result.steps[1].motion == "j.Throw"
    and cammy_air_throw_result.steps[1].expected_combo == 1
    and cammy_air_throw_result.steps[1].damage_at_step == 1150
    and cammy_air_throw_result.trace.suppressed_events[1].id == 966
    and cammy_air_throw_result.trace.suppressed_events[1].reason
        == "character_transient_input_precursor"
    and cammy_air_throw_result.trace.suppressed_events[2].id == 981
    and cammy_air_throw_result.trace.suppressed_events[2].reason
        == "character_internal_action_phase",
    "Cammy's staggered air-throw chord must produce only the durable throw command")

local noncontact_fallback = compiler.new({ character = "MBison", frame = 0 })
noncontact_fallback.events = {
    {
        id = 921,
        frame = 10,
        has_hit = false,
        has_contact = false,
        anchor = {
            kind = "button_press",
            pressed_buttons = 512,
            held_buttons = 512,
            direction = "5",
        },
    },
}
local noncontact_fallback_result = compiler.finalize(noncontact_fallback, {
    motion_resolver = test_motion_resolver,
})
assert(#noncontact_fallback_result.steps == 1
    and noncontact_fallback_result.steps[1].id == 921
    and noncontact_fallback_result.steps[1].motion == "HK"
    and noncontact_fallback_result.stats.input_derived_motion_actions == 1
    and noncontact_fallback_result.stats.input_derived_noncontact_motion_actions == 1
    and noncontact_fallback_result.stats.unresolved_motion_actions == 0,
    "a real button-bound whiff Action must use physical input when its catalog row is absent")

local parry_fallback = compiler.new({ character = "MBison", frame = 0 })
parry_fallback.events = {
    {
        id = 974,
        frame = 10,
        expected_combo = 2,
        damage_at_step = 840,
        has_hit = true,
        has_contact = true,
        anchor = {
            kind = "button_press",
            pressed_buttons = 32 | 256,
            held_buttons = 32 | 256,
            direction = "5",
        },
    },
}
local parry_fallback_result = compiler.finalize(parry_fallback, {
    motion_resolver = test_motion_resolver,
})
assert(#parry_fallback_result.steps == 1
    and parry_fallback_result.steps[1].id == 974
    and parry_fallback_result.steps[1].motion == "PARRY",
    "an unmapped MP+MK Action must retain its real ID and display the system command")

local bison_contact_continuation =
    compiler.new({ character = "MBison", frame = 0 })
bison_contact_continuation.events = {
    {
        id = 981,
        frame = 10,
        expected_combo = 1,
        damage_at_step = 360,
        has_hit = true,
        has_contact = true,
        anchor = {
            kind = "button_press",
            pressed_buttons = 64,
        },
    },
    {
        id = 982,
        frame = 48,
        expected_combo = 2,
        damage_at_step = 1080,
        has_hit = true,
        has_contact = true,
        anchor = {
            kind = "double_tap",
            direction = "6",
            initial_action_id = 981,
        },
    },
}
local bison_contact_continuation_result =
    compiler.finalize(bison_contact_continuation, {
        motion_resolver = function(action_id)
            if action_id == 981 then return "214+HP", "strict_route" end
            return nil, "action_id_missing"
        end,
    })
assert(#bison_contact_continuation_result.steps == 1
    and bison_contact_continuation_result.steps[1].id == 981
    and bison_contact_continuation_result.steps[1].expected_combo == 2
    and bison_contact_continuation_result.steps[1].damage_at_step == 1080
    and bison_contact_continuation_result.trace.suppressed_events[1].reason
        == "unmapped_contact_continuation",
    "a direction-buffered unmapped multi-hit phase must merge into its mapped owner")

local marisa_delayed_contact = compiler.new({ character = "Marisa", frame = 0 })
marisa_delayed_contact.events = {
    {
        id = 686,
        frame = 10,
        expected_combo = 0,
        damage_at_step = 0,
        has_hit = false,
        has_contact = false,
        anchor = {
            kind = "button_press",
            pressed_buttons = 64,
        },
    },
    {
        id = 684,
        frame = 15,
        expected_combo = 1,
        damage_at_step = 1000,
        has_hit = true,
        has_contact = true,
        anchor = {
            kind = "direction_action",
            direction = "4",
            initial_action_id = 686,
        },
    },
}
local marisa_delayed_contact_result =
    compiler.finalize(marisa_delayed_contact, {
        motion_resolver = function(action_id)
            if action_id == 686 then return "4+HP", "strict_route" end
            return nil, "action_id_missing"
        end,
    })
assert(#marisa_delayed_contact_result.steps == 1
    and marisa_delayed_contact_result.steps[1].id == 686
    and marisa_delayed_contact_result.steps[1].expected_combo == 1
    and marisa_delayed_contact_result.steps[1].damage_at_step == 1000
    and marisa_delayed_contact_result.trace.suppressed_events[1].reason
        == "unmapped_contact_continuation",
    "an unmapped contact phase that starts during its mapped owner must merge even when the owner has not hit yet")

local drive_rush_phase = compiler.new({ character = "MBison", frame = 0 })
drive_rush_phase.events = {
    {
        id = 740,
        frame = 10,
        anchor = { kind = "double_tap", direction = "6" },
    },
    {
        id = 741,
        frame = 44,
        anchor = { kind = "double_tap", direction = "6" },
    },
}
local drive_rush_phase_result = compiler.finalize(drive_rush_phase, {
    motion_resolver = test_motion_resolver,
})
assert(#drive_rush_phase_result.steps == 1
    and drive_rush_phase_result.steps[1].id == 740
    and drive_rush_phase_result.trace.suppressed_events[1].reason
        == "redundant_drive_rush_phase",
    "a later Drive Rush execution phase must not become a second V2 command")

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

local vertical_jump_contact_startup = compiler.new({
    character = "EHonda",
    frame = 0,
})
vertical_jump_contact_startup.events = {
    {
        id = 33,
        frame = 10,
        expected_combo = 2,
        damage_at_step = 1700,
        has_hit = true,
        has_contact = true,
        anchor = { kind = "direction_action", direction = "8" },
    },
    {
        id = 36,
        frame = 14,
        expected_combo = 0,
        damage_at_step = 0,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "movement_action", direction = "8" },
    },
}
local vertical_jump_contact_result = compiler.finalize(
    vertical_jump_contact_startup,
    { motion_resolver = test_motion_resolver }
)
assert(#vertical_jump_contact_result.steps == 1
    and vertical_jump_contact_result.steps[1].id == 36
    and vertical_jump_contact_result.steps[1].expected_combo == 2
    and vertical_jump_contact_result.steps[1].damage_at_step == 1700
    and vertical_jump_contact_result.steps[1].has_hit == true
    and vertical_jump_contact_result.trace.suppressed_events[1].id == 33,
    "vertical jump BGN contact truth must move to the durable jump Action")

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
result.stats.unresolved_anchors = 1
local unbound_input_evaluation = transcriber.evaluate(source, result, {
    input_source = "timeline",
    raw_inputs = { 0, 2, 18, 18, 2, 0 },
    input_completed = true,
})
assert(unbound_input_evaluation.ok == true
    and unbound_input_evaluation.advisories[1]
        == "unbound_input_anchors:1",
    "an input that produced no runtime Action must remain an advisory in preserved raw input")
result.stats.unresolved_anchors = 0

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
local missing_terminal_contact = transcriber.evaluate({
    {
        id = 970,
        motion = "214+LP",
        expected_combo = 9,
        damage_at_step = 1890,
        combo_stats = { damage = 2690 },
    },
    {
        id = 660,
        motion = "j.HK",
        expected_combo = 1,
        damage_at_step = 2690,
        has_hit = true,
        has_contact = true,
    },
}, {
    steps = {
        {
            id = 970,
            motion = "214+LP",
            expected_combo = 9,
            damage_at_step = 1890,
            has_hit = true,
            has_contact = true,
        },
        {
            id = 660,
            motion = "j.HK",
            expected_combo = 0,
            damage_at_step = 1890,
            has_hit = false,
            has_contact = false,
        },
    },
    stats = {
        damage = 1890,
        max_combo = 9,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 0, 512, 0 },
    input_completed = true,
    allow_legacy_damage_drift = true,
    allow_legacy_outcome_rebuild = true,
})
assert(missing_terminal_contact.ok == false
    and missing_terminal_contact.reasons[1] == "terminal_expected_contact_missing",
    "an earlier max combo must not hide a missing terminal OKI hit")
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

local regressed_combo_source = {
    {
        id = 608,
        motion = "HK",
        expected_combo = 1,
        damage_at_step = 1080,
        has_hit = true,
        has_contact = true,
        combo_stats = { damage = 2600 },
        _xt_meta = {
            environment = {
                dummy_counter_type = 2,
                dummy_guard_type = 2,
                dummy_guard_count = 10,
            },
        },
    },
    {
        id = 623,
        motion = "j.HP",
        expected_combo = 2,
        damage_at_step = 1880,
        has_hit = true,
        has_contact = true,
    },
    {
        id = 604,
        motion = "HP",
        expected_combo = 3,
        damage_at_step = 2600,
        has_hit = true,
        has_contact = true,
    },
}
local regressed_combo = transcriber.evaluate(regressed_combo_source, {
    steps = {
        {
            id = 608,
            motion = "HK",
            expected_combo = 1,
            damage_at_step = 1080,
            has_hit = true,
            has_contact = true,
        },
        {
            id = 623,
            motion = "j.HP",
            expected_combo = 2,
            damage_at_step = 1880,
            has_hit = true,
            has_contact = true,
        },
        {
            id = 604,
            motion = "HP",
            expected_combo = 0,
            damage_at_step = 1880,
            has_hit = false,
            has_contact = true,
            hit_result = "block",
            was_blocked = true,
        },
    },
    stats = {
        damage = 1880,
        max_combo = 2,
        unresolved_anchors = 0,
        block_contacts = 1,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 768, 0, 64, 0, 64, 0 },
    input_completed = true,
    allow_legacy_damage_drift = true,
    allow_legacy_outcome_rebuild = true,
    verify_environment = true,
    environment_observed = {
        dummy_counter_type = 2,
        dummy_guard_type = 2,
        dummy_guard_count = 10,
    },
})
assert(regressed_combo.ok == false
    and table.concat(regressed_combo.reasons, ","):match(
        "unexpected_block_before_combo_completion"
    )
    and table.concat(regressed_combo.reasons, ","):match(
        "combo_count_regressed:expected=3:observed=2"
    )
    and regressed_combo.environment_validation.matches == true,
    "a reproducible blocked drop must not rebuild a smaller combo as success")

local segmented_legacy_source = {
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        damage_at_step = 300,
        has_hit = true,
        has_contact = true,
        combo_stats = { damage = 900, super_used = 20000 },
    },
    {
        id = 500,
        motion = "DRC",
        expected_combo = 0,
        damage_at_step = 300,
        has_hit = true,
        has_contact = true,
    },
    {
        id = 601,
        motion = "MP",
        expected_combo = 2,
        damage_at_step = 600,
        has_hit = true,
        has_contact = true,
    },
    {
        id = 1221,
        motion = "214214+P",
        expected_combo = 4,
        damage_at_step = 900,
        has_hit = true,
        has_contact = true,
    },
}
local segmented_legacy_steps = {
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        damage_at_step = 300,
        has_hit = true,
        has_contact = true,
    },
    {
        id = 700,
        motion = "AUTO",
        expected_combo = 1,
        damage_at_step = 300,
        has_hit = false,
        has_contact = false,
    },
    {
        id = 500,
        motion = "DRC",
        expected_combo = 0,
        damage_at_step = 300,
        has_hit = false,
        has_contact = false,
    },
    {
        id = 601,
        motion = "MP",
        expected_combo = 1,
        damage_at_step = 700,
        has_hit = true,
        has_contact = true,
    },
    {
        id = 1221,
        motion = "214214+P",
        expected_combo = 2,
        damage_at_step = 1200,
        has_hit = true,
        has_contact = true,
    },
}
local segmented_legacy_rebuild = transcriber.evaluate(segmented_legacy_source, {
    steps = segmented_legacy_steps,
    stats = {
        damage = 1200,
        max_combo = 2,
        super_used = 30000,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 16, 0, 288, 0, 32, 0 },
    input_completed = true,
    allow_legacy_outcome_rebuild = true,
})
assert(segmented_legacy_rebuild.ok == true
    and segmented_legacy_rebuild.source_action_match == false
    and segmented_legacy_rebuild.source_action_subsequence_match == true
    and segmented_legacy_rebuild.legacy_segmented_outcome == true
    and table.concat(segmented_legacy_rebuild.advisories, ","):match(
        "source_segmented_combo_count_rebuilt"
    )
    and table.concat(segmented_legacy_rebuild.advisories, ","):match(
        "source_segmented_super_usage_rebuilt"
    ),
    "a complete segmented legacy route may rebuild cumulative combo and net Super fields")

local incomplete_segmented_steps = transcriber.deep_copy(segmented_legacy_steps)
table.remove(incomplete_segmented_steps, 4)
local incomplete_segmented_rebuild = transcriber.evaluate(segmented_legacy_source, {
    steps = incomplete_segmented_steps,
    stats = {
        damage = 900,
        max_combo = 2,
        super_used = 30000,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 16, 0, 288, 0, 32, 0 },
    input_completed = true,
    allow_legacy_outcome_rebuild = true,
})
assert(incomplete_segmented_rebuild.ok == false
    and incomplete_segmented_rebuild.source_action_subsequence_match == false
    and table.concat(incomplete_segmented_rebuild.reasons, ","):match(
        "combo_count_regressed"
    ),
    "a segmented route with a missing authored Action must remain a failure")

local terminal_pressure_rebuild = transcriber.evaluate({
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        damage_at_step = 300,
        has_hit = true,
        has_contact = true,
        combo_stats = { damage = 600 },
    },
    {
        id = 666,
        motion = "6+HP",
        expected_combo = 1,
        damage_at_step = 600,
        has_hit = true,
        has_contact = true,
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
        unresolved_anchors = 0,
        block_contacts = 1,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 16, 0, 64, 0 },
    input_completed = true,
    allow_legacy_damage_drift = true,
    allow_legacy_outcome_rebuild = true,
})
assert(terminal_pressure_rebuild.ok == true,
    "a block after the source maximum combo was reached may remain a pressure tail")

local environment_mismatch = transcriber.evaluate(regressed_combo_source, {
    steps = regressed_combo_source,
    stats = {
        damage = 2600,
        max_combo = 3,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 768, 0, 64, 0, 64, 0 },
    input_completed = true,
    verify_environment = true,
    environment_observed = {
        dummy_counter_type = 0,
        dummy_guard_type = 2,
        dummy_guard_count = 10,
    },
})
assert(environment_mismatch.ok == false
    and environment_mismatch.reasons[1]
        == "training_environment_mismatch:"
            .. "dummy_counter_type:expected=2:actual=0"
    and environment_mismatch.environment_validation.matches == false,
    "transcription must reject a punish-counter menu write that did not apply")

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
for _, pair in ipairs({ { 970, 971 }, { 971, 970 }, { 972, 973 }, { 973, 972 } }) do
    local rule = CharacterRules.get_match_rule(nil, nil, "EHonda", pair[1])
    assert(ActionMatcher.matches_expected_action_id(
            { id = pair[1] },
            pair[2],
            rule
        ),
        "Honda verified Action variants must match symmetrically")
end

local legacy_oki_source = {
    {
        id = 624,
        motion = "2MP",
        expected_combo = 1,
        damage_at_step = 600,
        has_hit = true,
        has_contact = true,
        dummy_guard_type = 2,
        dummy_guard_switching = true,
        _xt_meta = {
            dummy_guard_type = 2,
            dummy_guard_switching = true,
            environment = {
                dummy_guard_type = 2,
                dummy_guard_switching = true,
            },
        },
    },
    {
        id = 934,
        motion = ">6+P",
        expected_combo = 8,
        damage_at_step = 2584,
        has_hit = true,
        has_contact = true,
    },
    {
        id = 939,
        motion = "236+LP (空挥)",
        expected_combo = 0,
        damage_at_step = 2584,
        has_hit = false,
        has_contact = false,
    },
    {
        id = 969,
        motion = ">6+HK",
        expected_combo = 1,
        damage_at_step = 3624,
        has_hit = true,
        has_contact = true,
    },
}
local zero_combo_contact_source = {
    {
        id = 973,
        motion = "214+LP",
        expected_combo = 0,
        damage_at_step = 700,
        has_hit = true,
        has_contact = true,
        dummy_guard_type = 2,
        dummy_guard_switching = true,
        _xt_meta = {
            dummy_guard_type = 2,
            dummy_guard_switching = true,
            environment = {
                dummy_guard_type = 2,
                dummy_guard_switching = true,
            },
        },
    },
    {
        id = 740,
        motion = "RAW DR",
        expected_combo = 0,
        damage_at_step = 700,
        has_hit = false,
        has_contact = false,
    },
    {
        id = 612,
        motion = "HK",
        expected_combo = 1,
        damage_at_step = 1780,
        has_hit = true,
        has_contact = true,
    },
}
local prepared_zero_contact, zero_contact_adjustments =
    transcriber.prepare_capture_sequence(zero_combo_contact_source)
assert(#zero_contact_adjustments == 1
    and zero_contact_adjustments[1].reason
        == "expected_hit_after_zero_combo_contact"
    and prepared_zero_contact[1].dummy_guard_type == 0
    and prepared_zero_contact[1].dummy_guard_switching == false
    and zero_combo_contact_source[1].dummy_guard_type == 2,
    "a zero-combo setup hit followed by a new hit string must disable conflicting guard on a copy")
local prepared_oki, oki_adjustments =
    transcriber.prepare_capture_sequence(legacy_oki_source)
assert(#oki_adjustments == 1
    and oki_adjustments[1].reason
        == "expected_hit_reconnect_after_combo_reset"
    and prepared_oki[1].dummy_guard_type == 0
    and prepared_oki[1].dummy_guard_switching == false
    and prepared_oki[1]._xt_meta.dummy_guard_type == 0
    and prepared_oki[1]._xt_meta.environment.dummy_guard_type == 0
    and legacy_oki_source[1].dummy_guard_type == 2,
    "an expected post-reset hit string must disable conflicting guard on a copy")
local one_string_source = transcriber.deep_copy(legacy_oki_source)
one_string_source[3].expected_combo = 8
one_string_source[4].expected_combo = 9
local prepared_one_string, one_string_adjustments =
    transcriber.prepare_capture_sequence(one_string_source)
assert(#one_string_adjustments == 0
    and prepared_one_string[1].dummy_guard_type == 2,
    "a continuous combo must retain its recorded after-first-hit guard setting")
local blocked_oki_source = transcriber.deep_copy(legacy_oki_source)
blocked_oki_source[4].was_blocked = true
blocked_oki_source[4].hit_result = "block"
local prepared_blocked_oki, blocked_oki_adjustments =
    transcriber.prepare_capture_sequence(blocked_oki_source)
assert(#blocked_oki_adjustments == 0
    and prepared_blocked_oki[1].dummy_guard_type == 2,
    "an OKI sequence that expects block contact must retain its guard setting")

local legacy_low_health_source = {
    {
        id = 607,
        motion = "HP",
        expected_hp = 2100,
        recorded_by = 0,
        scene_state = {
            recorded_by = 0,
            players = {
                p1 = {
                    resources = {
                        hp = 10000,
                        heal_hp = 10000,
                        drive = 60000,
                        super = 30000,
                    },
                },
                p2 = { resources = { hp = 10000 } },
            },
        },
    },
    {
        id = 1217,
        motion = "236236+K",
        expected_hp = 2100,
    },
}
local prepared_low_health, low_health_adjustments =
    transcriber.prepare_capture_sequence(legacy_low_health_source)
local prepared_low_health_roles =
    SceneState.resolve_roles(prepared_low_health[1], 0)
assert(#low_health_adjustments == 1
    and low_health_adjustments[1].field
        == "scene_state.actor.resources.hp"
    and low_health_adjustments[1].reason
        == "stable_legacy_expected_hp"
    and SceneState.resources(prepared_low_health_roles.actor).hp == 2100
    and SceneState.resources(prepared_low_health_roles.actor).heal_hp == 2100
    and legacy_low_health_source[1].scene_state.players.p1.resources.hp == 10000,
    "a stable legacy low-health snapshot must repair only the copied actor scene for CA playback")
local unstable_low_health_source = transcriber.deep_copy(legacy_low_health_source)
unstable_low_health_source[2].expected_hp = 2000
local prepared_unstable_health, unstable_health_adjustments =
    transcriber.prepare_capture_sequence(unstable_low_health_source)
assert(#unstable_health_adjustments == 0
    and prepared_unstable_health[1].scene_state.players.p1.resources.hp == 10000,
    "conflicting legacy HP samples must not override the V2 scene authority")
local low_health_causes = transcriber.suspected_causes(legacy_low_health_source)
assert(table.concat(low_health_causes, ","):match("actor_low_health"),
    "legacy expected_hp must identify a missing low-health environment in failure reports")

local honda_legacy_buff_source = {
    {
        id = 926,
        motion = "214+HP",
        expected_hp = 10500,
        recorded_by = 0,
        scene_state = {
            recorded_by = 0,
            players = {
                p1 = {
                    fighter_id = 20,
                    resources = { hp = 10500 },
                    unique = { stock_0_020 = 0 },
                },
                p2 = { fighter_id = 1, resources = { hp = 10000 } },
            },
        },
    },
}
local prepared_honda_buff, honda_buff_adjustments =
    transcriber.prepare_capture_sequence(honda_legacy_buff_source)
local prepared_honda_roles = SceneState.resolve_roles(prepared_honda_buff[1], 0)
assert(#honda_buff_adjustments == 1
    and honda_buff_adjustments[1].field
        == "scene_state.actor.unique.stock_0_020"
    and honda_buff_adjustments[1].reason
        == "source_action_requires_unique_resource"
    and prepared_honda_roles.actor.state.unique.stock_0_020 == 1
    and honda_legacy_buff_source[1].scene_state.players.p1.unique.stock_0_020 == 0,
    "an enhanced Honda Action must repair missing initial Sumo Spirit on the copied scene")
local honda_buff_causes = transcriber.suspected_causes(honda_legacy_buff_source)
assert(table.concat(honda_buff_causes, ","):match(
        "actor_character_resource_required"
    ),
    "enhanced Honda Actions must diagnose a missing unique resource")

local honda_runtime_buff_source = transcriber.deep_copy(honda_legacy_buff_source)
honda_runtime_buff_source[1].id = 970
honda_runtime_buff_source[1].scene_state.players.p1.unique.stock_0_020 = 0
honda_runtime_buff_source[2] = { id = 926, motion = "214+HP", expected_hp = 10500 }
local prepared_runtime_buff, runtime_buff_adjustments =
    transcriber.prepare_capture_sequence(honda_runtime_buff_source)
assert(#runtime_buff_adjustments == 0
    and prepared_runtime_buff[1].scene_state.players.p1.unique.stock_0_020 == 0,
    "a replay that establishes Honda stock before the enhanced Action must retain stock zero")

local candidate = assert(transcriber.build_candidate(source, result, {
    schema = 2,
    product_id = "sf6cc",
    product_version = "1.0.4",
    json_id = "xt.combo_trial",
    json_version = "2",
}, "2026-07-30T00:00:00+08:00", {
    input_source = "timeline",
    raw_inputs = { 0, 2, 18, 18, 2, 0 },
    environment_adjustments = oki_adjustments,
}))
assert(candidate[1].id == 600 and candidate[1].motion == "2+LP",
    "candidate steps must come from the new runtime compiler")
assert(candidate[1].timeline[2] == "1f : 2+LP",
    "the input truth must be copied without rewriting")
assert(#candidate[1].raw_inputs == 6 and candidate[1].raw_inputs[3] == 18,
    "timeline transcription must emit a frame-accurate raw input stream")
assert(candidate[1]._xt_meta.transcription.raw_inputs_origin == "captured_timeline_replay",
    "candidate metadata must disclose how raw input was obtained")
assert(candidate[1]._xt_meta.transcription.environment_adjustments[1].reason
        == "expected_hit_reconnect_after_combo_reset",
    "candidate metadata must disclose derived training-environment changes")
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
local honda_variant_candidate = transcriber.deep_copy(candidate)
local honda_variant_compiled = transcriber.deep_copy(result)
honda_variant_candidate[1].id = 973
honda_variant_compiled.steps[1].id = 972
local honda_variant_verified = transcriber.verify_candidate(
    honda_variant_candidate,
    honda_variant_compiled,
    {
        raw_inputs = honda_variant_candidate[1].raw_inputs,
        input_completed = true,
        action_ids_equivalent = function(expected_id, observed_id)
            local rule = CharacterRules.get_match_rule(
                nil,
                nil,
                "EHonda",
                expected_id
            )
            return ActionMatcher.matches_expected_action_id(
                { id = expected_id },
                observed_id,
                rule
            )
        end,
    }
)
assert(honda_variant_verified.ok == true,
    "raw replay verification must accept explicitly equivalent Honda Action variants")
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

local report_paths = {
    "TrainingComboTrials_data/TranscriptionReports/"
        .. "CViper_failure_retry_20260731_115136.json",
    "TrainingComboTrials_data/TranscriptionReports/CViper_20260731_125047.json",
    "TrainingComboTrials_data/TranscriptionReports/CViper_in_progress.json",
}
local reports_by_path = {
    [report_paths[1]] = {
        schema = transcriber.REPORT_SCHEMA,
        finished_at = "2026-07-31T11:51:36+08:00",
        items = { { status = "passed" } },
    },
    [report_paths[2]] = {
        schema = transcriber.REPORT_SCHEMA,
        finished_at = "2026-07-31T12:53:50+08:00",
        items = { { status = "failed" } },
    },
    [report_paths[3]] = {
        schema = transcriber.REPORT_SCHEMA,
        started_at = "2026-07-31T13:07:01+08:00",
        items = { { status = "passed", source = "started_at" } },
    },
}
local latest_report_path, latest_report = transcriber.select_latest_report(
    report_paths,
    function(path) return reports_by_path[path] end,
    transcriber.REPORT_SCHEMA
)
assert(latest_report_path == report_paths[3]
    and latest_report.items[1].source == "started_at",
    "latest report loading must use started_at when finished_at is not available")

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

local failure_retry_run = transcriber.failure_retry_run({
    character = "Marisa",
    items = {
        {
            source_file = "TrainingComboTrials_data\\CustomCombos\\Marisa\\A.json",
            source_name = "A.json",
            candidate_file =
                "TrainingComboTrials_data/TranscribedCandidates/Marisa/run1/A.json",
            status = "passed",
            raw_replay_verified = true,
        },
        {
            source_file = "TrainingComboTrials_data\\CustomCombos\\Marisa\\B.json",
            source_name = "B.json",
            status = "failed",
            raw_replay_verified = false,
        },
        {
            source_file = "TrainingComboTrials_data\\CustomCombos\\Marisa\\C.json",
            source_name = "C.json",
            candidate_file =
                "TrainingComboTrials_data/TranscribedCandidates/Marisa/run1/C.json",
            status = "passed",
            raw_replay_verified = false,
        },
    },
}, "Marisa", {
    "TrainingComboTrials_data\\CustomCombos\\Marisa\\B.json",
}, "2026-07-31T17:00:00+08:00")
assert(#failure_retry_run.items == 1
    and failure_retry_run.items[1].source_name == "A.json"
    and #failure_retry_run.paths == 1
    and failure_retry_run.resume_processed == 1
    and failure_retry_run.index == 1
    and failure_retry_run.total == 2
    and failure_retry_run.passed == 1,
    "a failure retry report must retain verified passes and retry only failed paths")

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
