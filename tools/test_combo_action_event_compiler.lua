package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local compiler = dofile("autorun/func/ComboTrials/ActionEventCompiler.lua")
local transcriber = dofile("autorun/func/ComboTrials/Transcriber.lua")
local CharacterRules = require("func/ComboTrials/CharacterRules")
local ActionMatcher = require("func/ComboTrials/ActionMatcher")
local SceneState = require("func/ComboTrials/SceneState")

ACTION_EVENT_FIXTURES = {
    Alex = {
        ["608"] = { absorb_ids = "610", action_event_projection = {} },
        ["976"] = { absorb_ids = "977", action_event_projection = {} },
        ["1208"] = { absorb_ids = "1209", action_event_projection = {} },
    },
    Cammy = {
        ["652"] = { absorb_ids = "653", action_event_projection = {} },
        ["916"] = { absorb_ids = "933", action_event_projection = {} },
        ["979"] = {
            absorb_ids = "980,981",
            action_event_projection = {},
            action_event_rules = { transient_precursor_ids = "966" },
        },
        ["1022"] = { absorb_ids = "1023", action_event_projection = {} },
    },
    EHonda = {
        _character = {
            transcription_rules = {
                initial_unique_requirements = {
                    {
                        fighter_id = 20,
                        resource_id = "stock_0_020",
                        value = 1,
                        required_action_ids = "925,926,927,928,929",
                        producer_action_ids = "970,971",
                    },
                },
            },
        },
        ["1215"] = { absorb_ids = "1216", action_event_projection = {} },
        ["1221"] = { absorb_ids = "1222", action_event_projection = {} },
    },
    Lily = {
        ["930"] = {
            action_event_rules = { transient_precursor_ids = "929" },
        },
    },
    Ingrid = {
        ["945"] = {
            absorb_ids = "953",
            action_event_projection = {},
        },
        ["949"] = {
            action_event_rules = { transient_precursor_ids = "906,945" },
        },
    },
    Luke = {
        ["920"] = { absorb_ids = "921", action_event_projection = {} },
        ["924"] = { absorb_ids = "926", action_event_projection = {} },
        ["929"] = { absorb_ids = "930", action_event_projection = {} },
        ["960"] = {
            action_event_rules = {
                suppress_after = {
                    previous_ids = "955",
                    anchor_kind = "button_press",
                    max_delay_frames = 64,
                    require_no_contact = true,
                },
            },
        },
        ["1210"] = {
            action_event_rules = { transient_precursor_ids = "17" },
        },
    },
    Manon = {
        ["1022"] = { absorb_ids = "1041", action_event_projection = {} },
    },
    Jamie = {
        ["608"] = { action_event_rules = { transient_precursor_ids = "657" } },
        ["610"] = { action_event_rules = { transient_precursor_ids = "657" } },
        ["620"] = { action_event_rules = { transient_precursor_ids = "513" } },
        ["628"] = { action_event_rules = { transient_precursor_ids = "512" } },
        ["657"] = {
            action_event_rules = {
                suppress_after = {
                    previous_ids = "652",
                    anchor_kind = "button_release",
                    max_delay_frames = 64,
                    require_no_contact = true,
                },
            },
        },
    },
    CViper = {
        ["1037"] = {
            action_event_rules = {
                preserve_quick_successor = { max_delay_frames = 4 },
            },
        },
    },
}

COMMON_ACTION_VARIANT_FIXTURES = {
    ["854"] = { action_alias_ids = "855" },
}

HONDA_ACTION_VARIANT_FIXTURES = {
    ["970"] = { action_alias_ids = "971" },
    ["971"] = { action_alias_ids = "970" },
    ["972"] = { action_alias_ids = "973" },
    ["973"] = { action_alias_ids = "972" },
}

function new_character_rule_session(character, frame)
    local exceptions = ACTION_EVENT_FIXTURES[character] or {}
    return compiler.new({
        character = character,
        frame = frame or 0,
        action_event_projection_rules =
            CharacterRules.build_action_event_projection_rules(exceptions, {}),
        action_event_rules = CharacterRules.build_action_event_rules(exceptions, {}),
    })
end

assert(compiler.BIND_WINDOW == ActionMatcher.PLAYER_ACTION_BIND_WINDOW,
    "compiler and runtime validator must share one physical-input bind window")
assert(ActionMatcher.sequence_uses_input_truth({
        { relative_raw_inputs = { 0, 16, 0 } },
    }),
    "facing-relative raw input must enable strict input-truth matching")
assert(not ActionMatcher.sequence_uses_input_truth({
        {
            relative_raw_inputs = { "invalid" },
            timeline = { "1f : 5", "1f : LP" },
        },
    }),
    "a malformed extension that falls back to timeline must not enable strict input-truth matching")

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

do
local same_frame_super = compiler.new({ character = "Ingrid", frame = 0 })
compiler.observe(same_frame_super, {
    frame = 1,
    action_id = 10,
    action_frame = 1,
    direct_input = 0,
    facing_right = true,
    combo_count = 0,
    actor_hp = 10000,
    actor_drive = 60000,
    actor_super = 30000,
    victim_hp = 10000,
})
compiler.observe(same_frame_super, {
    frame = 2,
    action_id = 1227,
    action_frame = 0,
    direct_input = 512,
    facing_right = true,
    combo_count = 0,
    actor_hp = 10000,
    actor_drive = 60000,
    actor_super = 10000,
    victim_hp = 10000,
})
local same_frame_super_result = compiler.finalize(same_frame_super, {
    motion_resolver = function(action_id)
        if action_id == 1227 then return "214214+HP", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(same_frame_super_result.stats.super_used == 20000,
    "a super spent on the first button edge must retain the pre-input gauge baseline")
end

do
local ingrid_projectile = new_character_rule_session("Ingrid")
ingrid_projectile.events = {
    {
        id = 945,
        frame = 100,
        expected_combo = 2,
        damage_at_step = 1440,
        has_hit = true,
        has_contact = true,
        anchor = { kind = "button_press", pressed_buttons = 256 },
    },
    {
        id = 953,
        frame = 185,
        expected_combo = 4,
        damage_at_step = 1840,
        has_hit = true,
        has_contact = true,
        anchor = { kind = "direction_action", direction_sequence = "42" },
    },
}
ingrid_projectile.current_damage = 1840
ingrid_projectile.max_combo = 4
local ingrid_projectile_result = compiler.finalize(ingrid_projectile, {
    motion_resolver = function(action_id)
        if action_id == 945 then return "236+MK", "strict_route" end
        if action_id == 953 then return "2", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#ingrid_projectile_result.steps == 1
        and ingrid_projectile_result.steps[1].id == 945
        and ingrid_projectile_result.steps[1].expected_combo == 4
        and ingrid_projectile_result.steps[1].damage_at_step == 1840
        and ingrid_projectile_result.trace.suppressed_events[1].id == 953
        and ingrid_projectile_result.trace.suppressed_events[1].reason
            == "character_internal_action_phase",
    "Ingrid 953 must merge its hit outcome into the command-owning 945 step")
end

local manon_hit_phase = new_character_rule_session("Manon")
manon_hit_phase.events = {
    {
        id = 1022,
        frame = 100,
        expected_combo = 0,
        damage_at_step = 1654,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "button_press", pressed_buttons = 32 },
    },
    {
        id = 1041,
        frame = 124,
        expected_combo = 5,
        damage_at_step = 2480,
        has_hit = true,
        has_contact = true,
        anchor = { kind = "button_press", pressed_buttons = 32 },
    },
}
manon_hit_phase.current_damage = 2480
manon_hit_phase.max_combo = 5
local manon_hit_phase_result = compiler.finalize(manon_hit_phase, {
    motion_resolver = function(action_id)
        if action_id == 1022 then return "236+MP", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#manon_hit_phase_result.steps == 1
        and manon_hit_phase_result.steps[1].id == 1022
        and manon_hit_phase_result.steps[1].motion == "236+MP"
        and manon_hit_phase_result.steps[1].expected_combo == 5
        and manon_hit_phase_result.steps[1].damage_at_step == 2480
        and manon_hit_phase_result.trace.suppressed_events[1].id == 1041
        and manon_hit_phase_result.trace.suppressed_events[1].reason
            == "character_internal_action_phase",
    "Manon 1041 must merge its hit outcome into the command-owning 1022 step")

do
local luke_internal_phases = {
    { owner = 920, child = 921, motion = "214+LP", combo = 3, damage = 1760 },
    { owner = 924, child = 926, motion = "214+MP", combo = 9, damage = 3584 },
    { owner = 929, child = 930, motion = "214+HP", combo = 7, damage = 3719 },
}
for _, case in ipairs(luke_internal_phases) do
    local session = new_character_rule_session("Luke")
    session.events = {
        {
            id = case.owner,
            frame = 100,
            expected_combo = 0,
            damage_at_step = case.damage - 400,
            has_hit = false,
            has_contact = false,
            anchor = { kind = "button_press", pressed_buttons = 16 },
        },
        {
            id = case.child,
            frame = 113,
            expected_combo = case.combo,
            damage_at_step = case.damage,
            has_hit = true,
            has_contact = true,
            anchor = { kind = "direction_action", direction_sequence = "214" },
        },
    }
    session.current_damage = case.damage
    session.max_combo = case.combo
    local result = compiler.finalize(session, {
        motion_resolver = function(action_id)
            if action_id == case.owner then return case.motion, "strict_route" end
            return nil, "action_id_missing"
        end,
    })
    assert(#result.steps == 1
            and result.steps[1].id == case.owner
            and result.steps[1].motion == case.motion
            and result.steps[1].expected_combo == case.combo
            and result.steps[1].damage_at_step == case.damage
            and result.trace.suppressed_events[1].id == case.child
            and result.trace.suppressed_events[1].reason
                == "character_internal_action_phase",
        "Luke Flash Knuckle hit phases must merge into their command owners")
end

local luke_uppercut_tail = new_character_rule_session("Luke")
luke_uppercut_tail.events = {
    {
        id = 955,
        frame = 200,
        expected_combo = 5,
        damage_at_step = 1669,
        has_hit = true,
        has_contact = true,
        anchor = { kind = "button_press", pressed_buttons = 16 },
    },
    {
        id = 960,
        frame = 251,
        expected_combo = 0,
        damage_at_step = 1669,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "button_press", pressed_buttons = 16 },
    },
}
luke_uppercut_tail.current_damage = 1669
luke_uppercut_tail.max_combo = 5
local luke_uppercut_result = compiler.finalize(luke_uppercut_tail, {
    motion_resolver = function(action_id)
        if action_id == 955 then return "623+LP", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#luke_uppercut_result.steps == 1
        and luke_uppercut_result.steps[1].id == 955
        and luke_uppercut_result.steps[1].expected_combo == 5
        and luke_uppercut_result.steps[1].damage_at_step == 1669
        and luke_uppercut_result.trace.suppressed_events[1].id == 960
        and luke_uppercut_result.trace.suppressed_events[1].reason
            == "character_action_event_suppression",
    "Luke's non-contact 960 tail must not become an extra command step")

local luke_super_dash_precursor = new_character_rule_session("Luke")
luke_super_dash_precursor.events = {
    {
        id = 17,
        frame = 300,
        expected_combo = 0,
        damage_at_step = 1900,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "double_tap", direction = "6" },
    },
    {
        id = 17,
        frame = 316,
        expected_combo = 0,
        damage_at_step = 1900,
        has_hit = false,
        has_contact = false,
        anchor = { kind = "double_tap", direction = "6" },
    },
    {
        id = 1210,
        frame = 320,
        expected_combo = 13,
        damage_at_step = 4300,
        has_hit = true,
        has_contact = true,
        anchor = { kind = "button_press", pressed_buttons = 16 },
    },
}
luke_super_dash_precursor.current_damage = 4300
luke_super_dash_precursor.max_combo = 13
local luke_super_dash_result = compiler.finalize(luke_super_dash_precursor, {
    motion_resolver = function(action_id)
        if action_id == 17 then return "66", "strict_route" end
        if action_id == 1210 then return "214214+P", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#luke_super_dash_result.steps == 2
        and luke_super_dash_result.steps[1].id == 17
        and luke_super_dash_result.steps[2].id == 1210
        and luke_super_dash_result.steps[2].delay_from_prev == 20
        and luke_super_dash_result.trace.suppressed_events[1].id == 17
        and luke_super_dash_result.trace.suppressed_events[1].frame == 316
        and luke_super_dash_result.trace.suppressed_events[1].reason
            == "character_transient_input_precursor",
    "Luke SA2 input must suppress only the duplicate dash immediately before the super")
end

do
local cviper_cancel = new_character_rule_session("CViper")
local function cviper_cancel_observe(
    frame, action_id, input, combo, victim_hp, damage_type, hit_stop
)
    compiler.observe(cviper_cancel, {
        frame = frame,
        action_id = action_id,
        action_frame = frame,
        direct_input = input,
        facing_right = true,
        combo_count = combo or 0,
        actor_hp = 10000,
        victim_hp = victim_hp,
        victim_damage_type = damage_type or 0,
        victim_hit_stop = hit_stop or 0,
    })
end
cviper_cancel_observe(1, 5, 0, 0, 10000)
cviper_cancel_observe(2, 5, 32, 0, 10000)
cviper_cancel_observe(3, 1037, 32, 0, 10000)
cviper_cancel_observe(4, 1037, 32, 0, 10000)
cviper_cancel_observe(5, 971, 32, 0, 10000)
cviper_cancel_observe(6, 971, 32, 1, 9300, 3, 4)

local cviper_cancel_result = compiler.finalize(cviper_cancel, {
    motion_resolver = function(action_id)
        if action_id == 1037 then return "28", "runtime_verified_override" end
        if action_id == 971 then return "623+MP", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#cviper_cancel.events == 2
        and cviper_cancel.events[1].id == 1037
        and cviper_cancel.events[1].has_contact == false
        and cviper_cancel.events[2].id == 971
        and cviper_cancel.events[2].has_hit == true,
    "a mapped cancel must lend its input to the immediate durable successor")
assert(#cviper_cancel_result.steps == 2
        and cviper_cancel_result.steps[1].id == 1037
        and cviper_cancel_result.steps[1].motion == "28"
        and cviper_cancel_result.steps[2].id == 971
        and cviper_cancel_result.steps[2].delay_from_prev == 2
        and cviper_cancel_result.steps[2].expected_combo == 1,
    "the cancel and its same-input successor must remain separate V2 steps")
assert(cviper_cancel_result.steps[1].has_contact == false
        and cviper_cancel_result.steps[2].has_contact == true
        and cviper_cancel_result.stats.unresolved_anchors == 0,
    "same-input successor contact must not be attributed to the cancel step")
assert(ActionMatcher.should_preserve_quick_successor(
        cviper_cancel.action_event_rules,
        1037,
        2
    ) == true
        and ActionMatcher.should_preserve_quick_successor(
            cviper_cancel.action_event_rules,
            1037,
            5
        ) == false,
    "live ghost filtering must consume the compiler's bounded successor rule")
end

do
local poison_tail = compiler.new({ character = "AKI", frame = 0 })
local function poison_tail_observe(
    frame, action_id, input, combo, victim_hp, damage_type, hit_stop
)
    compiler.observe(poison_tail, {
        frame = frame,
        action_id = action_id,
        action_frame = frame,
        direct_input = input,
        facing_right = true,
        combo_count = combo or 0,
        actor_hp = 10000,
        victim_hp = victim_hp,
        victim_damage_type = damage_type or 0,
        victim_hit_stop = hit_stop or 0,
    })
end
poison_tail_observe(1, 10, 0, 0, 10000)
poison_tail_observe(2, 10, 16, 0, 10000)
poison_tail_observe(3, 600, 16, 0, 10000)
poison_tail_observe(4, 600, 16, 1, 9700, 3, 4)
poison_tail_observe(5, 600, 0, 0, 9700)
for frame = 6, 80 do
    -- The first few ticks deliberately retain a stale hit signal. Their 7 HP
    -- delta still identifies them as passive poison rather than a new contact.
    local stale_signal = frame <= 20
    poison_tail_observe(
        frame,
        600,
        0,
        0,
        9700 - ((frame - 5) * 7),
        stale_signal and 3 or 0,
        stale_signal and 4 or 0
    )
end
local poison_tail_result = compiler.finalize(poison_tail)
assert(poison_tail_result.stats.hit_contacts == 1
        and poison_tail_result.trace.last_activity_frame == 4,
    "passive poison must not create contacts or keep the replay tail active")
assert(poison_tail_result.stats.damage == 300
        and poison_tail_result.stats.observed_hp_loss > 300
        and poison_tail_result.stats.unconfirmed_hp_loss > 0
        and poison_tail_result.stats.passive_damage_ticks == 75
        and poison_tail_result.stats.passive_damage_max_tick == 7
        and poison_tail_result.steps[1].damage_at_step == 300,
    "damage truth must stop at the last confirmed contact while retaining raw HP-loss telemetry")
end

do
local same_combo_hit = compiler.new({ character = "Ryu", frame = 0 })
local function same_combo_observe(
    frame, action_id, input, combo, victim_hp, damage_type, hit_stop
)
    compiler.observe(same_combo_hit, {
        frame = frame,
        action_id = action_id,
        action_frame = frame,
        direct_input = input,
        facing_right = true,
        combo_count = combo or 0,
        actor_hp = 10000,
        victim_hp = victim_hp,
        victim_damage_type = damage_type or 0,
        victim_hit_stop = hit_stop or 0,
    })
end
same_combo_observe(1, 10, 0, 0, 10000)
same_combo_observe(2, 10, 16, 0, 10000)
same_combo_observe(3, 600, 16, 1, 9700)
same_combo_observe(4, 600, 0, 1, 9700)
same_combo_observe(5, 600, 32, 1, 9700)
same_combo_observe(6, 601, 32, 1, 9100, 3, 4)
local same_combo_result = compiler.finalize(same_combo_hit)
assert(#same_combo_result.steps == 2
        and same_combo_result.steps[2].has_hit == true
        and same_combo_result.stats.hit_contacts == 2
        and same_combo_result.stats.damage == 900,
    "a real hit signal must confirm a second contact when combo count stays unchanged")
end

do
local delayed_hit_damage = compiler.new({ character = "Ryu", frame = 0 })
local delayed_rows = {
    { 1, 10, 0, 0, 10000, 0, 0 },
    { 2, 10, 16, 0, 10000, 0, 0 },
    { 3, 600, 16, 0, 10000, 0, 0 },
    { 4, 600, 16, 1, 10000, 3, 4 },
    { 5, 600, 0, 1, 9700, 3, 4 },
}
for _, row in ipairs(delayed_rows) do
    compiler.observe(delayed_hit_damage, {
        frame = row[1],
        action_id = row[2],
        action_frame = row[1],
        direct_input = row[3],
        facing_right = true,
        combo_count = row[4],
        actor_hp = 10000,
        victim_hp = row[5],
        victim_damage_type = row[6],
        victim_hit_stop = row[7],
    })
end
local delayed_damage_result = compiler.finalize(delayed_hit_damage)
assert(delayed_damage_result.stats.hit_contacts == 1
        and delayed_damage_result.stats.damage == 300
        and delayed_damage_result.stats.passive_damage_ticks == 0
        and delayed_damage_result.steps[1].damage_at_step == 300,
    "an HP field that settles one frame after combo growth must confirm damage without duplicating contact")
end

do
local delayed_command_throw = compiler.new({ character = "Lily", frame = 0 })
local delayed_throw_rows = {
    -- frame, Action, input, combo, victim HP, damage type, hit stop
    { 1, 1, 0, 0, 10000, 0, 0 },
    { 2, 1, 64, 0, 10000, 0, 0 },
    { 3, 606, 64, 0, 10000, 0, 0 },
    { 4, 606, 64, 1, 8920, 3, 4 },
    { 5, 606, 0, 1, 8920, 0, 0 },
    { 10, 606, 64, 1, 8920, 0, 0 },
    { 11, 1005, 64, 1, 8920, 0, 0 },
    { 12, 1005, 0, 1, 8920, 0, 0 },
    { 13, 1006, 0, 1, 8920, 0, 0 },
    -- Lily's command throw reports neither an ordinary hit signal nor combo
    -- growth when its delayed damage becomes visible.
    { 120, 1006, 0, 1, 6400, 0, 0 },
    { 121, 1006, 0, 1, 6400, 0, 0 },
}
for _, row in ipairs(delayed_throw_rows) do
    compiler.observe(delayed_command_throw, {
        frame = row[1],
        action_id = row[2],
        action_frame = row[1],
        direct_input = row[3],
        facing_right = true,
        combo_count = row[4],
        actor_hp = 10000,
        victim_hp = row[5],
        victim_damage_type = row[6],
        victim_hit_stop = row[7],
    })
end
local delayed_throw_result = compiler.finalize(delayed_command_throw, {
    motion_resolver = function(action_id)
        if action_id == 606 then return "HP", "strict_route" end
        if action_id == 1005 then return "360+HP", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#delayed_command_throw.events == 3
        and delayed_command_throw.events[3].id == 1006
        and #delayed_throw_result.steps == 2
        and delayed_throw_result.steps[1].id == 606
        and delayed_throw_result.steps[2].id == 1005
        and delayed_throw_result.steps[2].has_hit == true
        and delayed_throw_result.steps[2].has_contact == true
        and delayed_throw_result.steps[2].expected_combo == 1
        and delayed_throw_result.steps[2].damage_at_step == 3600
        and delayed_throw_result.stats.damage == 3600
        and delayed_throw_result.stats.unconfirmed_hp_loss == 0
        and delayed_throw_result.stats.passive_damage_ticks == 0
        and delayed_throw_result.trace.suppressed_events[1].id == 1006,
    "a large HP drop during the same input-bound throw Action must remain contact truth even without ordinary hit signals")
end

do
local poison_direction = compiler.new({ character = "AKI", frame = 0 })
local poison_direction_rows = {
    { 1, 10, 0, 0, 10000 },
    { 2, 10, 16, 0, 10000 },
    { 3, 600, 16, 1, 9700 },
    { 4, 600, 0, 0, 9700 },
    { 5, 600, 2, 0, 9700 },
    { 6, 512, 10, 0, 9699 },
    { 7, 516, 8, 0, 9698 },
}
for _, row in ipairs(poison_direction_rows) do
    compiler.observe(poison_direction, {
        frame = row[1],
        action_id = row[2],
        action_frame = row[1],
        direct_input = row[3],
        facing_right = true,
        combo_count = row[4],
        actor_hp = 10000,
        victim_hp = row[5],
        victim_damage_type = 0,
        victim_hit_stop = 0,
    })
end
local poison_direction_result = compiler.finalize(poison_direction, {
    motion_resolver = function(action_id)
        if action_id == 600 then return "LP", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#poison_direction_result.steps == 1
        and poison_direction_result.steps[1].id == 600
        and poison_direction_result.stats.unresolved_motion_actions == 0
        and #poison_direction_result.trace.suppressed_events == 2,
    "poison ticks must not turn unmapped direction transitions into visible contact Actions")
end

do
local poison_drive_rush = compiler.new({ character = "AKI", frame = 0 })
local poison_drive_rows = {
    { 1, 10, 0, 10000, 0, 0 },
    { 2, 10, 32 | 256, 10000, 3, 4 },
    { 3, 480, 32 | 256, 10000, 3, 4 },
    { 4, 480, 32 | 256, 9993, 3, 4 },
    { 5, 740, 4, 9986, 0, 0 },
}
for _, row in ipairs(poison_drive_rows) do
    compiler.observe(poison_drive_rush, {
        frame = row[1],
        action_id = row[2],
        action_frame = row[1],
        direct_input = row[3],
        facing_right = true,
        combo_count = 0,
        actor_hp = 10000,
        victim_hp = row[4],
        victim_damage_type = row[5],
        victim_hit_stop = row[6],
    })
end
local poison_drive_result = compiler.finalize(poison_drive_rush, {
    motion_resolver = function(action_id)
        if action_id == 740 then return "RAW DR", "strict_route" end
        if action_id == 480 then return "PARRY", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#poison_drive_result.steps == 1
        and poison_drive_result.steps[1].id == 740
        and poison_drive_result.steps[1].has_contact ~= true,
    "a poison tick must not prevent the short 480 precursor from promoting to RAW DR")
end

do
local block_chip = compiler.new({ character = "Ryu", frame = 0 })
local block_rows = {
    { 1, 10, 0, 10000, 0, 0 },
    { 2, 10, 16, 10000, 0, 0 },
    { 3, 600, 16, 10000, 0, 0 },
    { 4, 600, 16, 9900, 30, 4 },
}
for _, row in ipairs(block_rows) do
    compiler.observe(block_chip, {
        frame = row[1],
        action_id = row[2],
        action_frame = row[1],
        direct_input = row[3],
        facing_right = true,
        combo_count = 0,
        actor_hp = 10000,
        victim_hp = row[4],
        victim_damage_type = row[5],
        victim_hit_stop = row[6],
    })
end
local block_result = compiler.finalize(block_chip)
assert(block_result.stats.damage == 100
        and block_result.stats.block_contacts == 1
        and block_result.steps[1].has_hit ~= true
        and block_result.steps[1].has_contact == true
        and block_result.steps[1].was_blocked == true,
    "real block chip must remain confirmed damage without becoming a hit")
end

do
local poison_block = compiler.new({ character = "AKI", frame = 0 })
local poison_block_rows = {
    { 1, 10, 0, 10000, 0, 0 },
    { 2, 10, 16, 10000, 0, 0 },
    { 3, 600, 16, 10000, 0, 0 },
    { 4, 600, 16, 10000, 30, 4 },
    { 5, 600, 0, 10000, 30, 4 },
    { 6, 600, 0, 9990, 30, 4 },
    { 7, 600, 0, 9970, 30, 4 },
}
for _, row in ipairs(poison_block_rows) do
    compiler.observe(poison_block, {
        frame = row[1],
        action_id = row[2],
        action_frame = row[1],
        direct_input = row[3],
        facing_right = true,
        combo_count = 0,
        actor_hp = 10000,
        victim_hp = row[4],
        victim_damage_type = row[5],
        victim_hit_stop = row[6],
    })
end
local poison_block_result = compiler.finalize(poison_block)
assert(poison_block_result.stats.damage == 0
        and poison_block_result.stats.block_contacts == 1
        and poison_block_result.stats.passive_damage_ticks == 2
        and poison_block_result.stats.passive_damage_total == 30
        and poison_block_result.stats.passive_damage_max_tick == 20
        and poison_block_result.steps[1].has_contact == true
        and poison_block_result.steps[1].was_blocked == true,
    "poison during continued blockstun must stay passive rather than becoming chip damage")
end

do
local multi_block_same_action = compiler.new({ character = "Ryu", frame = 0 })
local multi_block_rows = {
    { 1, 10, 0, 10000, 0, 0 },
    { 2, 10, 16, 10000, 0, 0 },
    { 3, 600, 16, 10000, 0, 0 },
    { 4, 600, 16, 10000, 30, 4 },
    { 5, 600, 0, 10000, 30, 0 },
    { 6, 600, 0, 10000, 30, 4 },
}
for _, row in ipairs(multi_block_rows) do
    compiler.observe(multi_block_same_action, {
        frame = row[1],
        action_id = row[2],
        action_frame = row[1],
        direct_input = row[3],
        facing_right = true,
        combo_count = 0,
        actor_hp = 10000,
        victim_hp = row[4],
        victim_damage_type = row[5],
        victim_hit_stop = row[6],
    })
end
local multi_block_result = compiler.finalize(multi_block_same_action)
assert(multi_block_result.stats.block_contacts == 1
        and multi_block_result.steps[1].was_blocked == true,
    "multiple block hit-stop cycles owned by one V2 Action must count as one blocked step")
end

do
local stale_large_poison = compiler.new({ character = "AKI", frame = 0 })
local stale_large_rows = {
    { 1, 10, 0, 0, 10000, 0, 0 },
    { 2, 10, 16, 0, 10000, 0, 0 },
    { 3, 600, 16, 0, 10000, 0, 0 },
    { 4, 600, 16, 1, 9700, 3, 4 },
    { 5, 600, 0, 0, 9690, 3, 4 },
    { 6, 512, 2, 0, 9670, 3, 4 },
}
for _, row in ipairs(stale_large_rows) do
    compiler.observe(stale_large_poison, {
        frame = row[1],
        action_id = row[2],
        action_frame = row[1],
        direct_input = row[3],
        facing_right = true,
        combo_count = row[4],
        actor_hp = 10000,
        victim_hp = row[5],
        victim_damage_type = row[6],
        victim_hit_stop = row[7],
    })
end
local stale_large_result = compiler.finalize(stale_large_poison, {
    motion_resolver = function(action_id)
        if action_id == 600 then return "LP", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(stale_large_result.stats.hit_contacts == 1
        and stale_large_result.stats.passive_damage_ticks == 2
        and stale_large_result.stats.passive_damage_max_tick == 20
        and #stale_large_result.steps == 1
        and stale_large_result.steps[1].id == 600,
    "10-20 HP poison with a continuous stale hit signal must not manufacture contacts")
end

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

local honda_super_contact_phase = new_character_rule_session("EHonda")
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

local alex_super_recovery_phase = new_character_rule_session("Alex")
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

local alex_hp_contact_phase = new_character_rule_session("Alex")
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

local alex_hp_release_phase = new_character_rule_session("Alex")
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

local cammy_target_combo_phase = new_character_rule_session("Cammy")
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

local cammy_internal_recovery = new_character_rule_session("Cammy")
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

local cammy_air_throw_chord = new_character_rule_session("Cammy")
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

do
local function finalize_lily_staggered_kicks(first_contact, delay, projection_rules)
    local session = new_character_rule_session("Lily")
    if projection_rules then
        session.action_event_projection_rules = projection_rules
    end
    session.events = {
        {
            id = 929,
            frame = 100,
            expected_combo = first_contact and 1 or 0,
            damage_at_step = first_contact and 700 or 0,
            has_hit = first_contact == true,
            has_contact = first_contact == true,
            anchor = { kind = "button_press", pressed_buttons = 512 },
        },
        {
            id = 930,
            frame = 100 + (delay or 1),
            expected_combo = 3,
            damage_at_step = 816,
            has_hit = true,
            has_contact = true,
            anchor = { kind = "button_press", pressed_buttons = 256,
                held_buttons = 768 },
        },
    }
    session.current_damage = 816
    session.confirmed_damage = 816
    session.max_combo = 3
    return session, compiler.finalize(session, {
        motion_resolver = function(action_id)
            if action_id == 929 then return "236+HK", "strict_route" end
            if action_id == 930 then return "236+MK+HK", "strict_route" end
            return nil, "action_id_missing"
        end,
    })
end

local lily_staggered_session, lily_staggered_result =
    finalize_lily_staggered_kicks(false, 1)
assert(#lily_staggered_session.events == 2
        and #lily_staggered_result.trace.input_bound_events == 2
        and #lily_staggered_result.steps == 1
        and lily_staggered_result.steps[1].id == 930
        and lily_staggered_result.steps[1].motion == "236+MK+HK"
        and lily_staggered_result.steps[1].has_contact == true
        and lily_staggered_result.trace.suppressed_events[1].id == 929
        and lily_staggered_result.trace.suppressed_events[1].merged_into == 930
        and lily_staggered_result.trace.suppressed_events[1].reason
            == "character_transient_input_precursor",
    "Lily's one-frame HK precursor must fold into the completed MK+HK chord while preserving the raw Action trace")

local standalone_lily_kick = compiler.new({ character = "Lily", frame = 0 })
standalone_lily_kick.events = {
    {
        id = 929,
        frame = 100,
        expected_combo = 1,
        damage_at_step = 700,
        has_hit = true,
        has_contact = true,
        anchor = { kind = "button_press", pressed_buttons = 512 },
    },
}
standalone_lily_kick.current_damage = 700
standalone_lily_kick.confirmed_damage = 700
standalone_lily_kick.max_combo = 1
local standalone_lily_result = compiler.finalize(standalone_lily_kick, {
    motion_resolver = function(action_id)
        if action_id == 929 then return "236+HK", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#standalone_lily_result.steps == 1
        and standalone_lily_result.steps[1].id == 929,
    "Lily's standalone 236+HK must remain a real instruction")

local _, contacted_lily_result = finalize_lily_staggered_kicks(true, 1)
local _, late_lily_result = finalize_lily_staggered_kicks(false, 21)
assert(#contacted_lily_result.steps == 2 and #late_lily_result.steps == 2,
    "a contacted or late Lily 929 Action must never be mistaken for a transient chord precursor")

local lily_absorb_only_projection =
    CharacterRules.build_action_event_projection_rules({
        ["930"] = { absorb_ids = "929" },
    }, {})
assert(lily_absorb_only_projection[929] == nil,
    "Lily's absorb-only 930 rule must not canonicalize the transient 929 precursor")
local _, product_lily_result =
    finalize_lily_staggered_kicks(false, 1, lily_absorb_only_projection)
assert(#product_lily_result.steps == 1
        and product_lily_result.steps[1].id == 930
        and product_lily_result.trace.suppressed_events[1].id == 929
        and product_lily_result.trace.suppressed_events[1].reason
            == "character_transient_input_precursor",
    "Lily's shipped absorb-only rule must preserve the 929 transient fold into 930")
end

do
local aki_action_event_projection_rules =
    CharacterRules.build_action_event_projection_rules({
        ["944"] = {
            absorb_ids = "936,941,945",
            record_absorb_as_parent = true,
            action_event_projection = {
                canonical_owner_ids = "945",
                max_fold_delay_frames = 1,
                require_same_anchor = true,
            },
        },
        ["998"] = {
            absorb_ids = "999",
            action_event_projection = { carry_input_anchor = true },
        },
    }, {})
local aki_owner_rule = aki_action_event_projection_rules[945]
assert(type(aki_owner_rule) == "table"
        and aki_owner_rule.kind == "canonical_owner"
        and aki_owner_rule.owner_id == 944
        and aki_action_event_projection_rules[936].kind == "internal_phase"
        and aki_action_event_projection_rules[999].owner_id == 998
        and aki_action_event_projection_rules[999].carry_input_anchor == true,
    "loaded character rules must compile exact Action-event projection ownership")
local lily_action_event_projection_rules =
    CharacterRules.build_action_event_projection_rules({
        ["905"] = {
            absorb_ids = "906,907",
            action_event_projection = {},
        },
        ["976"] = {
            absorb_ids = "974,983,984",
            action_event_projection = {},
        },
    }, {})
assert(lily_action_event_projection_rules[906].kind == "internal_phase"
        and lily_action_event_projection_rules[906].owner_id == 905
        and lily_action_event_projection_rules[907].kind == "internal_phase"
        and lily_action_event_projection_rules[907].owner_id == 905
        and lily_action_event_projection_rules[974].kind == "internal_phase"
        and lily_action_event_projection_rules[974].owner_id == 976
        and lily_action_event_projection_rules[983].kind == "internal_phase"
        and lily_action_event_projection_rules[983].owner_id == 976
        and lily_action_event_projection_rules[984].kind == "internal_phase"
        and lily_action_event_projection_rules[984].owner_id == 976
        and lily_action_event_projection_rules[907].carry_input_anchor == false
        and lily_action_event_projection_rules[984].carry_input_anchor == false,
    "Lily's loaded product rules must project only the declared phases without implicit input passthrough")

local function finalize_unprojected_akuma_transition(owner_id, child_id)
    local session = compiler.new({
        character = "Akuma",
        frame = 0,
    })
    session.events = {
        {
            id = owner_id,
            frame = 100,
            expected_combo = 0,
            damage_at_step = 0,
            has_hit = false,
            has_contact = false,
            anchor = { kind = "button_press", pressed_buttons = 512 },
        },
        {
            id = child_id,
            frame = 136,
            expected_combo = 3,
            damage_at_step = 1200,
            has_hit = true,
            has_contact = true,
            anchor = { kind = "action_transition", pressed_buttons = 0 },
        },
    }
    session.current_damage = 1200
    session.max_combo = 3
    return compiler.finalize(session, {
        motion_resolver = function(action_id)
            if action_id == owner_id then return "OWNER", "strict_route" end
            if action_id == child_id then return "INTERNAL", "strict_route" end
            return nil, "action_id_missing"
        end,
    })
end
for _, pair in ipairs({
    { 903, 908 },
    { 904, 914 },
    { 947, 948 },
    { 952, 948 },
    { 998, 1010 },
    { 999, 1010 },
    { 1000, 1010 },
    { 1005, 1010 },
    { 1006, 1010 },
    { 1007, 1010 },
    { 1213, 1216 },
    { 1214, 1216 },
}) do
    local owner_id, child_id = pair[1], pair[2]
    local result = finalize_unprojected_akuma_transition(owner_id, child_id)
    assert(#result.steps == 2
            and result.steps[1].id == owner_id
            and result.steps[1].expected_combo == 0
            and result.steps[1].damage_at_step == 0
            and result.steps[1].has_hit == false
            and result.steps[1].has_contact == false
            and result.steps[2].id == child_id
            and result.steps[2].expected_combo == 3
            and result.steps[2].damage_at_step == 1200
            and result.steps[2].has_hit == true
            and result.steps[2].has_contact == true
            and result.steps[2].delay_from_prev == 36
            and #result.trace.suppressed_events == 0,
        "Akuma display-only phase metadata must not fold either real runtime Action")
end

local akuma_replay_compiled = finalize_unprojected_akuma_transition(903, 908)
local akuma_replay_candidate = transcriber.deep_copy(akuma_replay_compiled.steps)
akuma_replay_candidate[1].relative_raw_inputs = { 512, 0 }
local akuma_replay_runtime = {
    raw_inputs = akuma_replay_candidate[1].relative_raw_inputs,
    input_source = "relative_raw_inputs",
    input_completed = true,
}
local akuma_replay_verified = transcriber.verify_candidate(
    akuma_replay_candidate,
    akuma_replay_compiled,
    akuma_replay_runtime
)
assert(akuma_replay_verified.ok == true,
    "the retained Akuma owner then child sequence must pass strict raw replay verification: "
        .. table.concat(akuma_replay_verified.reasons or {}, ","))

local function verification_reasons_match(evaluation, pattern)
    return type(evaluation) == "table"
        and table.concat(evaluation.reasons or {}, ","):match(pattern) ~= nil
end

local missing_child_replay = transcriber.deep_copy(akuma_replay_compiled)
table.remove(missing_child_replay.steps, 2)
local missing_child_verified = transcriber.verify_candidate(
    akuma_replay_candidate,
    missing_child_replay,
    akuma_replay_runtime
)
assert(missing_child_verified.ok == false
        and verification_reasons_match(
            missing_child_verified, "raw_replay_action_count_mismatch"),
    "raw replay must reject a missing contextual child Action")

local wrong_child_replay = transcriber.deep_copy(akuma_replay_compiled)
wrong_child_replay.steps[2].id = 909
local wrong_child_verified = transcriber.verify_candidate(
    akuma_replay_candidate,
    wrong_child_replay,
    akuma_replay_runtime
)
assert(wrong_child_verified.ok == false
        and verification_reasons_match(
            wrong_child_verified, "raw_replay_action_id_mismatch"),
    "raw replay must reject a different contextual child Action")

local reversed_replay = transcriber.deep_copy(akuma_replay_compiled)
reversed_replay.steps[1], reversed_replay.steps[2] =
    reversed_replay.steps[2], reversed_replay.steps[1]
local reversed_verified = transcriber.verify_candidate(
    akuma_replay_candidate,
    reversed_replay,
    akuma_replay_runtime
)
assert(reversed_verified.ok == false
        and verification_reasons_match(
            reversed_verified, "raw_replay_action_id_mismatch"),
    "raw replay must reject child-before-owner ordering")

local late_child_replay = transcriber.deep_copy(akuma_replay_compiled)
late_child_replay.steps[2].delay_from_prev =
    late_child_replay.steps[2].delay_from_prev + 3
local late_child_verified = transcriber.verify_candidate(
    akuma_replay_candidate,
    late_child_replay,
    akuma_replay_runtime
)
assert(late_child_verified.ok == false
        and verification_reasons_match(
            late_child_verified, "raw_replay_action_timing_mismatch"),
    "raw replay must reject an out-of-tolerance contextual child timing")

local function new_aki_projection_session()
    return compiler.new({
        character = "AKI",
        frame = 0,
        action_event_projection_rules = aki_action_event_projection_rules,
    })
end

local function new_lily_projection_session()
    return compiler.new({
        character = "Lily",
        frame = 0,
        action_event_projection_rules = lily_action_event_projection_rules,
    })
end

local function observe_lily_projection(
    session,
    frame,
    action_id,
    input,
    combo_count,
    victim_hp
)
    compiler.observe(session, {
        frame = frame,
        action_id = action_id,
        action_frame = 19717.944824,
        direct_input = input,
        facing_right = true,
        combo_count = combo_count or 0,
        actor_hp = 10000,
        victim_hp = victim_hp or 10000,
        victim_damage_type = (combo_count or 0) > 0 and 1 or 0,
        victim_hit_stop = 0,
    })
end

do
local lily_wind_buffer = new_lily_projection_session()
observe_lily_projection(lily_wind_buffer, 1, 10, 0, 0, 10000)
observe_lily_projection(lily_wind_buffer, 2, 10, 32, 0, 10000)
observe_lily_projection(lily_wind_buffer, 3, 905, 32, 0, 10000)
observe_lily_projection(lily_wind_buffer, 4, 905, 0, 0, 10000)
observe_lily_projection(lily_wind_buffer, 5, 905, 32, 0, 10000)
observe_lily_projection(lily_wind_buffer, 6, 907, 32, 4, 9280)
observe_lily_projection(lily_wind_buffer, 7, 907, 0, 4, 9280)
observe_lily_projection(lily_wind_buffer, 8, 907, 64, 4, 9280)
observe_lily_projection(lily_wind_buffer, 9, 1216, 64, 4, 9280)
local lily_wind_buffer_result = compiler.finalize(lily_wind_buffer, {
    motion_resolver = function(action_id)
        if action_id == 905 then return "214+MP", "strict_route" end
        if action_id == 1216 then return "214214+P", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#lily_wind_buffer.events == 3
        and lily_wind_buffer.events[1].id == 905
        and lily_wind_buffer.events[2].id == 907
        and lily_wind_buffer.events[3].id == 1216
        and lily_wind_buffer.events[2].anchor.frame == 5
        and lily_wind_buffer.events[3].anchor.frame == 8
        and lily_wind_buffer.events[2].anchor.pressed_buttons == 32
        and lily_wind_buffer.events[3].anchor.pressed_buttons == 64,
    "Lily 907 must consume only its own buffered punch while a fresh SA punch binds the durable super Action")
assert(#lily_wind_buffer_result.steps == 2
        and lily_wind_buffer_result.steps[1].id == 905
        and lily_wind_buffer_result.steps[1].motion == "214+MP"
        and lily_wind_buffer_result.steps[1].expected_combo == 4
        and lily_wind_buffer_result.steps[1].damage_at_step == 720
        and lily_wind_buffer_result.steps[1].has_hit == true
        and lily_wind_buffer_result.steps[2].id == 1216
        and lily_wind_buffer_result.steps[2].motion == "214214+P"
        and lily_wind_buffer_result.trace.input_bound_events[2].id == 907
        and lily_wind_buffer_result.trace.suppressed_events[1].id == 907
        and lily_wind_buffer_result.trace.suppressed_events[1].merged_into == 905
        and lily_wind_buffer_result.trace.suppressed_events[1].reason
            == "character_internal_action_phase",
    "Lily 907 must contribute only contact truth to 905 without becoming a V2 instruction")

local lily_dive_buffer = new_lily_projection_session()
observe_lily_projection(lily_dive_buffer, 1, 10, 0, 0, 10000)
observe_lily_projection(lily_dive_buffer, 2, 10, 112, 0, 10000)
observe_lily_projection(lily_dive_buffer, 3, 976, 112, 7, 9880)
observe_lily_projection(lily_dive_buffer, 4, 976, 0, 7, 9880)
observe_lily_projection(lily_dive_buffer, 5, 974, 0, 8, 9040)
observe_lily_projection(lily_dive_buffer, 6, 974, 256, 8, 9040)
observe_lily_projection(lily_dive_buffer, 7, 983, 256, 8, 9040)
observe_lily_projection(lily_dive_buffer, 8, 983, 0, 8, 9040)
observe_lily_projection(lily_dive_buffer, 9, 984, 0, 8, 9040)
observe_lily_projection(lily_dive_buffer, 10, 984, 128, 8, 9040)
observe_lily_projection(lily_dive_buffer, 11, 1207, 128, 8, 9040)
local lily_dive_buffer_result = compiler.finalize(lily_dive_buffer, {
    motion_resolver = function(action_id)
        if action_id == 976 then return "j.PPP", "strict_route" end
        if action_id == 1207 then return "236236+K", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#lily_dive_buffer.events == 5
        and lily_dive_buffer.events[1].id == 976
        and lily_dive_buffer.events[2].id == 974
        and lily_dive_buffer.events[3].id == 983
        and lily_dive_buffer.events[4].id == 984
        and lily_dive_buffer.events[5].id == 1207
        and lily_dive_buffer.events[2].anchor.frame == 4
        and lily_dive_buffer.events[3].anchor.frame == 6
        and lily_dive_buffer.events[4].anchor.frame == 8
        and lily_dive_buffer.events[5].anchor.frame == 10
        and lily_dive_buffer.events[2].anchor.released_buttons == 112
        and lily_dive_buffer.events[3].anchor.pressed_buttons == 256
        and lily_dive_buffer.events[4].anchor.released_buttons == 256
        and lily_dive_buffer.events[5].anchor.pressed_buttons == 128,
    "Lily's complete 974/983/984 phase chain must consume its own edges while a fresh SA2 kick binds the durable super Action")
assert(#lily_dive_buffer_result.steps == 2
        and lily_dive_buffer_result.steps[1].id == 976
        and lily_dive_buffer_result.steps[1].motion == "j.PPP"
        and lily_dive_buffer_result.steps[1].expected_combo == 8
        and lily_dive_buffer_result.steps[1].damage_at_step == 960
        and lily_dive_buffer_result.steps[1].has_hit == true
        and lily_dive_buffer_result.steps[2].id == 1207
        and lily_dive_buffer_result.steps[2].motion == "236236+K"
        and lily_dive_buffer_result.trace.input_bound_events[2].id == 974
        and lily_dive_buffer_result.trace.suppressed_events[1].id == 974
        and lily_dive_buffer_result.trace.suppressed_events[1].merged_into == 976
        and lily_dive_buffer_result.trace.suppressed_events[1].reason
            == "character_internal_action_phase"
        and lily_dive_buffer_result.trace.suppressed_events[2].id == 983
        and lily_dive_buffer_result.trace.suppressed_events[2].merged_into == 976
        and lily_dive_buffer_result.trace.suppressed_events[3].id == 984
        and lily_dive_buffer_result.trace.suppressed_events[3].merged_into == 976,
    "Lily's later dive phases must contribute only outcome truth to 976 without becoming V2 instructions")

local lily_redundant_dive_press = new_lily_projection_session()
observe_lily_projection(lily_redundant_dive_press, 1, 10, 0, 0, 10000)
observe_lily_projection(lily_redundant_dive_press, 2, 10, 112, 0, 10000)
observe_lily_projection(lily_redundant_dive_press, 3, 976, 112, 7, 9880)
observe_lily_projection(lily_redundant_dive_press, 4, 976, 0, 7, 9880)
observe_lily_projection(lily_redundant_dive_press, 5, 976, 112, 7, 9880)
observe_lily_projection(lily_redundant_dive_press, 6, 974, 112, 8, 9040)
observe_lily_projection(lily_redundant_dive_press, 7, 974, 112, 8, 9040)
observe_lily_projection(lily_redundant_dive_press, 8, 983, 112, 8, 9040)
observe_lily_projection(lily_redundant_dive_press, 9, 984, 112, 8, 9040)
observe_lily_projection(lily_redundant_dive_press, 50, 984, 112, 8, 9040)
local lily_redundant_dive_result = compiler.finalize(
    lily_redundant_dive_press,
    {
        motion_resolver = function(action_id)
            if action_id == 976 then return "j.PPP", "strict_route" end
            return nil, "action_id_missing"
        end,
    }
)
assert(#lily_redundant_dive_press.events == 2
        and lily_redundant_dive_press.events[1].id == 976
        and lily_redundant_dive_press.events[2].id == 974
        and lily_redundant_dive_press.unresolved_anchor_count == 0
        and #lily_redundant_dive_result.steps == 1
        and lily_redundant_dive_result.steps[1].id == 976
        and lily_redundant_dive_result.steps[1].expected_combo == 8
        and lily_redundant_dive_result.steps[1].damage_at_step == 960
        and #lily_redundant_dive_result.trace.suppressed_events == 1,
    "a redundant PPP press consumed by Lily's first internal phase must not leak into later recovery Actions")
end

do
local uninjected_aki_projection = compiler.new({ character = "AKI", frame = 0 })
uninjected_aki_projection.events = {
    {
        id = 945,
        frame = 100,
        anchor = { kind = "button_press", pressed_buttons = 16 | 32 },
    },
}
local uninjected_aki_result = compiler.finalize(uninjected_aki_projection, {
    motion_resolver = function(action_id)
        if action_id == 944 then return "236+PP", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(uninjected_aki_result.steps[1].id == 945
        and uninjected_aki_result.trace.projected_events[1]
            .normalized_from_action_id == nil,
    "the compiler must fail closed instead of loading character JSON itself")
end

local aki_od_snake_lash = new_aki_projection_session()
aki_od_snake_lash.events = {
    {
        id = 945,
        frame = 100,
        expected_combo = 0,
        damage_at_step = 0,
        has_hit = false,
        has_contact = false,
        hold_frames = 6,
        anchor = {
            kind = "button_press",
            pressed_buttons = 16 | 32,
            held_buttons = 16 | 32,
            hold_frames = 6,
        },
    },
    {
        id = 936,
        frame = 126,
        expected_combo = 1,
        damage_at_step = 480,
        has_hit = true,
        has_contact = true,
        hold_frames = 80,
        is_holdable = true,
        hold_partial_check = true,
        -- A coincident MP+MK release must not relabel this internal hit as
        -- Parry or transfer its hold classification to the PP command owner.
        anchor = {
            kind = "button_release",
            released_buttons = 32 | 256,
            hold_frames = 80,
        },
    },
    {
        id = 941,
        frame = 129,
        expected_combo = 2,
        damage_at_step = 920,
        has_hit = true,
        has_contact = true,
        anchor = { kind = "direction_action", direction = "2" },
    },
}
aki_od_snake_lash.observed_actions = {
    { id = 945, frame = 100 },
    { id = 936, frame = 126 },
    { id = 941, frame = 129 },
}
aki_od_snake_lash.current_damage = 920
aki_od_snake_lash.max_combo = 2
local aki_od_snake_lash_result = compiler.finalize(aki_od_snake_lash, {
    motion_resolver = function(action_id)
        if action_id == 944 then return "236+PP", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#aki_od_snake_lash_result.steps == 1
        and aki_od_snake_lash_result.steps[1].id == 944
        and aki_od_snake_lash_result.steps[1].motion == "236+PP"
        and aki_od_snake_lash_result.steps[1].expected_combo == 2
        and aki_od_snake_lash_result.steps[1].damage_at_step == 920
        and aki_od_snake_lash_result.steps[1].has_hit == true
        and aki_od_snake_lash_result.steps[1].has_contact == true
        and aki_od_snake_lash_result.steps[1].hold_frames == 6
        and aki_od_snake_lash_result.steps[1].is_holdable ~= true
        and aki_od_snake_lash_result.steps[1].hold_partial_check ~= true
        and aki_od_snake_lash_result.stats.fallback_motion_actions == 0,
    "AKI 945 must project as owner 944 while 936/941 contribute only hit truth")
assert(aki_od_snake_lash_result.trace.observed_actions[1].id == 945
        and aki_od_snake_lash_result.trace.input_bound_events[1].id == 945
        and aki_od_snake_lash_result.trace.projected_events[1].id == 944
        and aki_od_snake_lash_result.trace.projected_events[1]
            .normalized_from_action_id == 945
        and aki_od_snake_lash_result.trace.projected_events[1].anchor_buttons
            == (16 | 32)
        and aki_od_snake_lash_result.trace.suppressed_events[1].id == 936
        and aki_od_snake_lash_result.trace.suppressed_events[1].merged_into == 944
        and aki_od_snake_lash_result.trace.suppressed_events[2].id == 941
        and aki_od_snake_lash_result.trace.suppressed_events[2].merged_into == 944,
    "AKI owner projection must preserve raw Action truth and expose normalization in trace")
assert(aki_od_snake_lash.events[1].id == 945
        and aki_od_snake_lash.events[1].expected_combo == 0
        and aki_od_snake_lash.events[1].damage_at_step == 0
        and aki_od_snake_lash.events[1].hold_frames == 6
        and aki_od_snake_lash.events[1].anchor.pressed_buttons == (16 | 32),
    "projected outcome truth must not mutate the source owner event")

local aki_duplicate_owner = new_aki_projection_session()
aki_duplicate_owner.events = {
    {
        id = 944,
        frame = 100,
        action_frame = 19717.944824,
        expected_combo = 0,
        damage_at_step = 0,
        has_hit = false,
        has_contact = false,
        hold_frames = 4,
        anchor = {
            kind = "button_press",
            pressed_buttons = 32 | 64,
            frame = 99,
            hold_frames = 4,
        },
    },
    {
        id = 945,
        frame = 100,
        action_frame = 19717.944824,
        expected_combo = 1,
        damage_at_step = 400,
        has_hit = true,
        has_contact = true,
        hold_frames = 90,
        is_holdable = true,
        anchor = {
            kind = "button_release",
            released_buttons = 32 | 64,
            frame = 99,
            hold_frames = 90,
        },
    },
}
aki_duplicate_owner.observed_actions = {
    { id = 944, frame = 100 },
    { id = 945, frame = 100 },
}
aki_duplicate_owner.current_damage = 400
local aki_duplicate_owner_result = compiler.finalize(aki_duplicate_owner, {
    motion_resolver = function(action_id)
        if action_id == 944 then return "236+PP", "strict_route" end
        return nil, "action_id_missing"
    end,
})
assert(#aki_duplicate_owner_result.steps == 1
        and aki_duplicate_owner_result.steps[1].id == 944
        and aki_duplicate_owner_result.steps[1].expected_combo == 1
        and aki_duplicate_owner_result.steps[1].damage_at_step == 400
        and aki_duplicate_owner_result.steps[1].hold_frames == 4
        and aki_duplicate_owner_result.steps[1].is_holdable ~= true
        and aki_duplicate_owner_result.trace.observed_actions[2].id == 945
        and aki_duplicate_owner_result.trace.input_bound_events[2].id == 945
        and aki_duplicate_owner_result.trace.suppressed_events[1].id == 945
        and aki_duplicate_owner_result.trace.suppressed_events[1].reason
            == "character_canonical_owner_variant",
    "a runtime 944-to-945 owner variant must not emit duplicate 236+PP steps")
assert(aki_duplicate_owner.events[1].expected_combo == 0
        and aki_duplicate_owner.events[1].damage_at_step == 0
        and aki_duplicate_owner.events[1].hold_frames == 4
        and aki_duplicate_owner.events[1].anchor.kind == "button_press",
    "folding a canonical owner variant must leave the raw owner facts unchanged")

local function observe_aki_owner_transition(session, frame, action_id, input)
    compiler.observe(session, {
        frame = frame,
        action_id = action_id,
        -- Production reports can expose this non-frame counter value. Owner
        -- folding must use observed transition timing and physical input edges.
        action_frame = 19717.944824,
        direct_input = input,
        facing_right = true,
        combo_count = 0,
        actor_hp = 10000,
        victim_hp = 10000,
        victim_damage_type = 0,
        victim_hit_stop = 0,
    })
end

local aki_observed_owner_release = new_aki_projection_session()
observe_aki_owner_transition(aki_observed_owner_release, 1, 10, 0)
observe_aki_owner_transition(aki_observed_owner_release, 2, 944, 16 | 32)
observe_aki_owner_transition(aki_observed_owner_release, 3, 945, 32)
observe_aki_owner_transition(aki_observed_owner_release, 4, 10, 32)
observe_aki_owner_transition(aki_observed_owner_release, 5, 609, 32)
local aki_observed_owner_release_result = compiler.finalize(
    aki_observed_owner_release,
    {
        motion_resolver = function(action_id)
            if action_id == 944 then return "236+PP", "strict_route" end
            if action_id == 609 then return "LP", "strict_route" end
            return nil, "action_id_missing"
        end,
    }
)
assert(#aki_observed_owner_release.events == 2
        and aki_observed_owner_release.events[1].id == 944
        and aki_observed_owner_release.events[2].id == 945
        and aki_observed_owner_release.events[1].anchor.kind == "button_press"
        and aki_observed_owner_release.events[1].anchor.frame == 2
        and aki_observed_owner_release.events[2].anchor.kind == "button_release"
        and aki_observed_owner_release.events[2].anchor.released_buttons == 16
        and aki_observed_owner_release.events[2].anchor.frame == 3
        and #aki_observed_owner_release.observed_actions == 4
        and aki_observed_owner_release.observed_actions[4].id == 609,
    "observe must retain raw Action transitions without rebinding the 945 release")
assert(#aki_observed_owner_release_result.steps == 1
        and aki_observed_owner_release_result.steps[1].id == 944
        and aki_observed_owner_release_result.steps[1].motion == "236+PP"
        and #aki_observed_owner_release_result.trace.suppressed_events == 1
        and aki_observed_owner_release_result.trace.suppressed_events[1].id == 945
        and aki_observed_owner_release_result.trace.suppressed_events[1].reason
            == "character_canonical_owner_variant",
    "a next-frame 945 button release must fold into its observed 944 owner")

local aki_observed_fresh_press = new_aki_projection_session()
observe_aki_owner_transition(aki_observed_fresh_press, 1, 10, 0)
observe_aki_owner_transition(aki_observed_fresh_press, 2, 944, 16 | 32)
observe_aki_owner_transition(aki_observed_fresh_press, 3, 945, 16 | 32 | 64)
local aki_observed_fresh_press_result = compiler.finalize(
    aki_observed_fresh_press,
    {
        motion_resolver = function(action_id)
            if action_id == 944 then return "236+PP", "strict_route" end
            return nil, "action_id_missing"
        end,
    }
)
assert(#aki_observed_fresh_press.events == 2
        and aki_observed_fresh_press.events[2].id == 945
        and aki_observed_fresh_press.events[2].anchor.kind == "button_press"
        and aki_observed_fresh_press.events[2].anchor.pressed_buttons == 64
        and aki_observed_fresh_press.events[2].anchor.frame == 3,
    "observe must distinguish a fresh press from the owner's release phase")
assert(#aki_observed_fresh_press_result.steps == 2
        and aki_observed_fresh_press_result.steps[1].id == 944
        and aki_observed_fresh_press_result.steps[2].id == 944
        and aki_observed_fresh_press_result.steps[2].delay_from_prev == 1
        and #aki_observed_fresh_press_result.trace.suppressed_events == 0,
    "an adjacent 945 backed by a fresh button press must remain visible")

local aki_later_owner_variant = new_aki_projection_session()
aki_later_owner_variant.events = {
    {
        id = 944,
        frame = 100,
        action_frame = 0,
        anchor = { kind = "button_press", pressed_buttons = 16 | 32 },
    },
    {
        id = 945,
        frame = 300,
        action_frame = 0,
        anchor = { kind = "button_press", pressed_buttons = 32 | 64 },
    },
}
local aki_later_owner_variant_result = compiler.finalize(
    aki_later_owner_variant,
    {
        motion_resolver = function(action_id)
            if action_id == 944 then return "236+PP", "strict_route" end
            return nil, "action_id_missing"
        end,
    }
)
assert(#aki_later_owner_variant_result.steps == 2
        and aki_later_owner_variant_result.steps[1].id == 944
        and aki_later_owner_variant_result.steps[2].id == 944
        and aki_later_owner_variant_result.steps[2].motion == "236+PP"
        and aki_later_owner_variant_result.steps[2].delay_from_prev == 200
        and aki_later_owner_variant_result.trace.projected_events[2]
            .normalized_from_action_id == 945
        and #aki_later_owner_variant_result.trace.suppressed_events == 0,
    "a later 945 with a fresh PP press must remain a second visible command")

local aki_snake_step_phase = new_aki_projection_session()
aki_snake_step_phase.events = {
    {
        id = 998,
        frame = 100,
        expected_combo = 1,
        damage_at_step = 600,
        has_hit = true,
        has_contact = true,
        hold_frames = 3,
        anchor = {
            kind = "button_press",
            pressed_buttons = 512,
            hold_frames = 3,
        },
    },
    {
        id = 999,
        frame = 146,
        expected_combo = 1,
        damage_at_step = 600,
        has_hit = false,
        has_contact = false,
        hold_frames = 72,
        is_holdable = true,
        hold_partial_check = true,
        anchor = {
            kind = "button_press",
            pressed_buttons = 512,
            direction = "2",
        },
    },
}
aki_snake_step_phase.current_damage = 600
local function aki_phase_motion_resolver(action_id)
    if action_id == 998 then return "K", "strict_route" end
    return nil, "action_id_missing"
end
local aki_snake_step_phase_result = compiler.finalize(aki_snake_step_phase, {
    motion_resolver = aki_phase_motion_resolver,
})
assert(#aki_snake_step_phase_result.steps == 1
        and aki_snake_step_phase_result.steps[1].id == 998
        and aki_snake_step_phase_result.steps[1].motion == "K"
        and aki_snake_step_phase_result.steps[1].hold_frames == 3
        and aki_snake_step_phase_result.steps[1].is_holdable ~= true
        and aki_snake_step_phase_result.steps[1].hold_partial_check ~= true
        and aki_snake_step_phase_result.trace.projected_events[1].anchor_buttons
            == 512
        and aki_snake_step_phase_result.stats.fallback_motion_actions == 0
        and aki_snake_step_phase_result.trace.suppressed_events[1].id == 999
        and aki_snake_step_phase_result.trace.suppressed_events[1].merged_into == 998
        and aki_snake_step_phase_result.trace.suppressed_events[1].reason
            == "character_internal_action_phase",
    "AKI's fixed 998-to-999 internal phase must not consume a buffered 2+HK edge")
assert(aki_snake_step_phase.events[1].expected_combo == 1
        and aki_snake_step_phase.events[1].damage_at_step == 600
        and aki_snake_step_phase.events[1].hold_frames == 3
        and aki_snake_step_phase.events[1].anchor.pressed_buttons == 512,
    "folding 999 must not mutate the raw 998 owner event")

local aki_pending_internal_phase = new_aki_projection_session()
local function observe_aki_pending_phase(frame, action_id, input)
    compiler.observe(aki_pending_internal_phase, {
        frame = frame,
        action_id = action_id,
        -- Production reports can expose this non-frame counter value. Runtime
        -- phase ownership must rely on observed transition timing instead.
        action_frame = 19717.944824,
        direct_input = input,
        facing_right = true,
        combo_count = 0,
        actor_hp = 10000,
        victim_hp = 10000,
        victim_damage_type = 0,
        victim_hit_stop = 0,
    })
end
observe_aki_pending_phase(1, 10, 0)
observe_aki_pending_phase(2, 10, 512)
observe_aki_pending_phase(3, 998, 512)
observe_aki_pending_phase(4, 998, 0)
observe_aki_pending_phase(5, 998, 16)
observe_aki_pending_phase(6, 999, 16)
observe_aki_pending_phase(7, 609, 16)
local aki_pending_internal_result = compiler.finalize(
    aki_pending_internal_phase,
    {
        motion_resolver = function(action_id)
            if action_id == 998 then return "K", "strict_route" end
            if action_id == 609 then return "LP", "strict_route" end
            return nil, "action_id_missing"
        end,
    }
)
assert(#aki_pending_internal_phase.observed_actions == 3
        and aki_pending_internal_phase.observed_actions[1].id == 998
        and aki_pending_internal_phase.observed_actions[2].id == 999
        and aki_pending_internal_phase.observed_actions[3].id == 609
        and #aki_pending_internal_phase.events == 3
        and aki_pending_internal_phase.events[2].id == 999
        and aki_pending_internal_phase.events[3].id == 609
        and aki_pending_internal_phase.events[2].anchor.frame == 5
        and aki_pending_internal_phase.events[3].anchor.frame == 5
        and aki_pending_internal_phase.events[2].anchor.pressed_buttons == 16
        and aki_pending_internal_phase.events[3].anchor.pressed_buttons == 16,
    "an internal 999 event must return its temporarily bound LP anchor to the durable Action")
assert(#aki_pending_internal_result.steps == 2
        and aki_pending_internal_result.steps[1].id == 998
        and aki_pending_internal_result.steps[2].id == 609
        and aki_pending_internal_result.steps[2].motion == "LP"
        and aki_pending_internal_result.trace.projected_events[2].anchor_buttons == 16
        and aki_pending_internal_result.trace.suppressed_events[1].id == 999,
    "final projection must fold 999 while retaining the LP-bound durable 609 step")

do
local function build_aki_continuation_session(include_locomotion, expire_only)
    local continuation_session = new_aki_projection_session()
    local rows = {
        { 1, 10, 0 },
        { 2, 10, 512 },
        { 3, 998, 512 },
        { 4, 998, 0 },
        { 5, 998, 16 },
        { 6, 999, 16 },
    }
    if include_locomotion then
        rows[#rows + 1] = { 7, 17, 16 }
        rows[#rows + 1] = { 8, 609, 16 }
    elseif expire_only then
        rows[#rows + 1] = { 60, 999, 16 }
    end
    for _, row in ipairs(rows) do
        compiler.observe(continuation_session, {
            frame = row[1],
            action_id = row[2],
            action_frame = row[1],
            direct_input = row[3],
            facing_right = true,
            combo_count = 0,
            actor_hp = 10000,
            victim_hp = 10000,
            victim_damage_type = 0,
            victim_hit_stop = 0,
        })
    end
    return continuation_session
end

local aki_pending_at_finalize = build_aki_continuation_session(false, false)
local aki_pending_at_finalize_result = compiler.finalize(
    aki_pending_at_finalize,
    { motion_resolver = aki_phase_motion_resolver }
)
assert(aki_pending_at_finalize_result.stats.unresolved_anchors == 0
        and aki_pending_at_finalize_result.trace.pending_anchor
            .is_internal_phase_continuation == true,
    "an explicitly carried internal continuation must be non-failing even when capture finalizes before it expires")

local aki_locomotion_between = build_aki_continuation_session(true, false)
local aki_locomotion_between_result = compiler.finalize(
    aki_locomotion_between,
    {
        motion_resolver = function(action_id)
            if action_id == 998 then return "K", "strict_route" end
            if action_id == 609 then return "LP", "strict_route" end
            return nil, "action_id_missing"
        end,
    }
)
assert(#aki_locomotion_between.events == 3
        and aki_locomotion_between.events[1].id == 998
        and aki_locomotion_between.events[2].id == 999
        and aki_locomotion_between.events[3].id == 609
        and #aki_locomotion_between_result.steps == 2
        and aki_locomotion_between_result.steps[2].id == 609,
    "a common locomotion Action must not steal an explicitly carried attack edge")

local aki_expired_continuation = build_aki_continuation_session(false, true)
local aki_expired_continuation_result = compiler.finalize(
    aki_expired_continuation,
    { motion_resolver = aki_phase_motion_resolver }
)
assert(aki_expired_continuation_result.stats.unresolved_anchors == 0
        and aki_expired_continuation_result.trace
            .expired_internal_continuation_count == 1,
    "an unused carried internal edge must expire visibly without becoming an unresolved command")
end

do
local aki_replaced_pending_phase = new_aki_projection_session()
local function observe_replaced_pending(frame, action_id, input)
    compiler.observe(aki_replaced_pending_phase, {
        frame = frame,
        action_id = action_id,
        action_frame = 19717.944824,
        direct_input = input,
        facing_right = true,
        combo_count = 0,
        actor_hp = 10000,
        victim_hp = 10000,
        victim_damage_type = 0,
        victim_hit_stop = 0,
    })
end
observe_replaced_pending(1, 10, 0)
observe_replaced_pending(2, 10, 512)
observe_replaced_pending(3, 998, 512)
observe_replaced_pending(4, 998, 0)
observe_replaced_pending(5, 998, 16)
observe_replaced_pending(6, 999, 16)
observe_replaced_pending(7, 999, 32)
observe_replaced_pending(8, 609, 32)
assert(aki_replaced_pending_phase.events[3].id == 609
        and aki_replaced_pending_phase.events[3].anchor.frame == 7
        and aki_replaced_pending_phase.events[3].anchor.pressed_buttons == 32,
    "a fresh input edge must replace an anchor restored by an internal phase")
end

local non_aki_snake_step_ids = compiler.new({ character = "Ryu", frame = 0 })
non_aki_snake_step_ids.events = aki_snake_step_phase.events
local non_aki_snake_step_result = compiler.finalize(non_aki_snake_step_ids, {
    motion_resolver = aki_phase_motion_resolver,
})
assert(#non_aki_snake_step_result.steps == 2
        and non_aki_snake_step_result.steps[2].id == 999
        and non_aki_snake_step_result.steps[2].motion == "2+HK",
    "AKI phase IDs must not be suppressed for other characters")

local aki_wrong_snake_step_owner = new_aki_projection_session()
aki_wrong_snake_step_owner.events = {
    {
        id = 997,
        frame = 100,
        anchor = { kind = "button_press", pressed_buttons = 16 },
    },
    aki_snake_step_phase.events[2],
}
local aki_wrong_snake_step_result = compiler.finalize(
    aki_wrong_snake_step_owner,
    {
        motion_resolver = function(action_id)
            if action_id == 997 then return "LP", "strict_route" end
            return nil, "action_id_missing"
        end,
    }
)
assert(#aki_wrong_snake_step_result.steps == 2
        and aki_wrong_snake_step_result.steps[2].id == 999
        and aki_wrong_snake_step_result.steps[2].motion == "2+HK",
    "AKI 999 must fold only after its exact 998 owner")
end

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

do
local meter_confirmed_parry_rush = compiler.new({ character = "Lily", frame = 0 })
local meter_rush_rows = {
    { 1, 10, 0, 60000 },
    { 2, 10, 32 | 256, 60000 },
    { 3, 480, 32 | 256, 59900 },
    { 4, 480, 32 | 256, 59900 },
    { 5, 480, 32 | 256, 59900 },
    { 6, 480, 32 | 256, 59900 },
    { 7, 480, 32 | 256, 59900 },
    { 8, 740, 32 | 256, 49900 },
}
for _, row in ipairs(meter_rush_rows) do
    compiler.observe(meter_confirmed_parry_rush, {
        frame = row[1],
        action_id = row[2],
        action_frame = row[1],
        direct_input = row[3],
        facing_right = true,
        combo_count = 0,
        actor_hp = 10000,
        actor_drive = row[4],
        victim_hp = 10000,
    })
end
local meter_rush_result = compiler.finalize(meter_confirmed_parry_rush, {
    motion_resolver = test_motion_resolver,
})
assert(#meter_rush_result.steps == 2
        and meter_rush_result.steps[1].id == 480
        and meter_rush_result.steps[2].id == 740
        and meter_rush_result.steps[2].delay_from_prev == 5
        and meter_rush_result.trace.input_bound_events[2].bind_reason
            == "drive_cost_confirmed_raw_dr_transition",
    "a late anchorless 480-to-740 transition with a local one-bar Drive spend must preserve the real RAW DR step")
end

do
local deferred_meter_parry_rush = compiler.new({ character = "Lily", frame = 0 })
local deferred_meter_rows = {
    { 1, 10, 0, 30480 },
    { 2, 10, 32 | 256, 30480 },
    { 3, 480, 32 | 256, 30480 },
    { 4, 480, 32 | 256, 30480 },
    { 5, 480, 32 | 256, 30480 },
    { 6, 480, 32 | 256, 30480 },
    { 7, 480, 32 | 256, 30480 },
    -- Action 740 is already real here, but the engine has not committed its
    -- one-bar cost to the live gauge yet.
    { 8, 740, 32 | 256, 30420 },
    { 9, 740, 32 | 256, 30420 },
    -- The report showed the settled cost for the first time on the following
    -- attack frame. That attack must keep its own physical input anchor.
    { 23, 651, 64, 20420 },
}
for _, row in ipairs(deferred_meter_rows) do
    compiler.observe(deferred_meter_parry_rush, {
        frame = row[1],
        action_id = row[2],
        action_frame = row[1],
        direct_input = row[3],
        facing_right = true,
        combo_count = 0,
        actor_hp = 10000,
        actor_drive = row[4],
        victim_hp = 10000,
    })
end
local deferred_meter_result = compiler.finalize(deferred_meter_parry_rush, {
    motion_resolver = test_motion_resolver,
})
assert(#deferred_meter_result.steps == 3
        and deferred_meter_result.steps[1].id == 480
        and deferred_meter_result.steps[2].id == 740
        and deferred_meter_result.steps[2].delay_from_prev == 5
        and deferred_meter_result.steps[3].id == 651
        and deferred_meter_result.steps[3].delay_from_prev == 15
        and deferred_meter_result.trace.input_bound_events[2].frame == 8
        and deferred_meter_result.trace.input_bound_events[2].bind_reason
            == "deferred_drive_cost_confirmed_raw_dr_transition"
        and deferred_meter_result.trace.expired_meter_raw_dr_count == 0,
    "a delayed local Drive cost must preserve Action 740 at its real frame without stealing the next attack anchor")
end

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

do
local malformed_source_ok, malformed_source_evaluation = pcall(
    transcriber.evaluate,
    nil,
    { steps = {}, stats = {} },
    {
        input_source = "timeline",
        raw_inputs = { 0 },
        input_completed = true,
    }
)
assert(malformed_source_ok
        and malformed_source_evaluation.ok == false
        and malformed_source_evaluation.reasons[1] == "no_action_steps",
    "a malformed source sequence must report failure instead of raising")

local partial_super_cases = {
    { source = 6900, observed = 10000 },
    { source = 17000, observed = 20000 },
    { source = 14800, observed = 20000 },
}
local partial_super_source = {
    {
        id = 1200,
        motion = "236236+P",
        expected_combo = 20,
        damage_at_step = 4080,
        has_hit = true,
        has_contact = true,
        combo_stats = { damage = 4080, super_used = 6900 },
        timeline = { "1f : 5+LP" },
    },
}
local function partial_super_compiled(super_used)
    return {
        steps = {
            {
                id = 1200,
                motion = "236236+P",
                expected_combo = 20,
                damage_at_step = 4080,
                has_hit = true,
                has_contact = true,
            },
        },
        stats = {
            damage = 4080,
            max_combo = 20,
            super_used = super_used,
            unresolved_anchors = 0,
            block_contacts = 0,
        },
    }
end
local partial_super_runtime = {
    input_source = "timeline",
    raw_inputs = { 16, 0 },
    input_completed = true,
    allow_legacy_outcome_rebuild = true,
}
for _, case in ipairs(partial_super_cases) do
    local source_case = transcriber.deep_copy(partial_super_source)
    source_case[1].combo_stats.super_used = case.source
    local evaluation_case = transcriber.evaluate(
        source_case,
        partial_super_compiled(case.observed),
        partial_super_runtime
    )
    assert(evaluation_case.ok == true
        and table.concat(evaluation_case.advisories, ",") == string.format(
            "source_partial_super_usage_rebuilt:expected=%d:observed=%d",
            case.source,
            case.observed
        ),
        "a proven legacy partial Super sample must rebuild to its next exact whole level")
end

local zero_super_observed = transcriber.evaluate(
    partial_super_source,
    partial_super_compiled(0),
    partial_super_runtime
)
assert(zero_super_observed.ok == false
        and table.concat(zero_super_observed.reasons, ","):match(
            "super_consumption_mismatch"
        )
        and #zero_super_observed.advisories == 0,
    "missing runtime Super consumption must never use the legacy partial-value bridge")
local wrong_partial_action = partial_super_compiled(10000)
wrong_partial_action.steps[1].id = 1201
local wrong_partial_action_evaluation = transcriber.evaluate(
    partial_super_source,
    wrong_partial_action,
    partial_super_runtime
)
assert(wrong_partial_action_evaluation.ok == false
        and table.concat(wrong_partial_action_evaluation.reasons, ","):match(
            "super_consumption_mismatch"
        )
        and #wrong_partial_action_evaluation.advisories == 0,
    "a different Action must keep partial Super metadata strict")
local regressed_partial_combo = partial_super_compiled(10000)
regressed_partial_combo.steps[1].expected_combo = 19
regressed_partial_combo.stats.max_combo = 19
local regressed_partial_evaluation = transcriber.evaluate(
    partial_super_source,
    regressed_partial_combo,
    partial_super_runtime
)
assert(regressed_partial_evaluation.ok == false
        and table.concat(regressed_partial_evaluation.reasons, ","):match(
            "combo_count_regressed"
        )
        and table.concat(regressed_partial_evaluation.reasons, ","):match(
            "super_consumption_mismatch"
        ),
    "a smaller combo must not be hidden by partial Super reconstruction")
local canonical_super_source = transcriber.deep_copy(partial_super_source)
canonical_super_source[1].combo_stats.super_used = 10000
local canonical_super_drift = transcriber.evaluate(
    canonical_super_source,
    partial_super_compiled(20000),
    partial_super_runtime
)
assert(canonical_super_drift.ok == false
        and table.concat(canonical_super_drift.reasons, ","):match(
            "super_consumption_mismatch"
        ),
    "a canonical whole-level source cost must remain strict")
local skipped_super_level = transcriber.evaluate(
    partial_super_source,
    partial_super_compiled(20000),
    partial_super_runtime
)
assert(skipped_super_level.ok == false
        and table.concat(skipped_super_level.reasons, ","):match(
            "super_consumption_mismatch"
        ),
    "a partial source cost may rebuild only to its immediate whole level")
local mismatched_partial_damage = partial_super_compiled(10000)
mismatched_partial_damage.stats.damage = 4000
mismatched_partial_damage.steps[1].damage_at_step = 4000
local mismatched_partial_damage_evaluation = transcriber.evaluate(
    partial_super_source,
    mismatched_partial_damage,
    partial_super_runtime
)
assert(mismatched_partial_damage_evaluation.ok == false
        and table.concat(mismatched_partial_damage_evaluation.reasons, ","):match(
            "super_consumption_mismatch"
        ),
    "damage drift must keep partial Super metadata strict")
local disabled_partial_bridge_runtime = transcriber.deep_copy(partial_super_runtime)
disabled_partial_bridge_runtime.allow_legacy_outcome_rebuild = false
local disabled_partial_bridge = transcriber.evaluate(
    partial_super_source,
    partial_super_compiled(10000),
    disabled_partial_bridge_runtime
)
assert(disabled_partial_bridge.ok == false
        and table.concat(disabled_partial_bridge.reasons, ","):match(
            "super_consumption_mismatch"
        ),
    "partial Super reconstruction must stay disabled outside legacy source capture")
local missing_super_contact = partial_super_compiled(10000)
missing_super_contact.steps[1].has_hit = false
missing_super_contact.steps[1].has_contact = false
local missing_super_contact_evaluation = transcriber.evaluate(
    partial_super_source,
    missing_super_contact,
    partial_super_runtime
)
assert(missing_super_contact_evaluation.ok == false
        and table.concat(missing_super_contact_evaluation.reasons, ","):match(
            "terminal_expected_contact_missing"
        )
        and table.concat(missing_super_contact_evaluation.reasons, ","):match(
            "super_consumption_mismatch"
        ),
    "missing terminal contact must keep partial Super metadata strict")

local partial_super_candidate = assert(transcriber.build_candidate(
    partial_super_source,
    partial_super_compiled(10000),
    {
        schema = 2,
        product_id = "sf6cc",
        product_version = "1.0.4",
        json_id = "xt.combo_trial",
        json_version = "2",
    },
    "2026-08-01T00:00:00+08:00",
    {
        input_source = "timeline",
        relative_raw_inputs = { 16, 0 },
    }
))
assert(partial_super_candidate[1].combo_stats.super_used == 10000,
    "a rebuilt candidate must persist runtime whole-level Super truth")
local partial_super_verified = transcriber.verify_candidate(
    partial_super_candidate,
    partial_super_compiled(10000),
    {
        raw_inputs = { 16, 0 },
        input_source = "relative_raw_inputs",
        input_completed = true,
    }
)
assert(partial_super_verified.ok == true,
    "the second raw replay must strictly verify the rebuilt whole-level Super cost")
end

local legacy_damage_source = {
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        damage_at_step = 300,
        combo_stats = { damage = 300 },
    },
}
do
local missing_terminal_source = {
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
}
local missing_terminal_contact = transcriber.evaluate(missing_terminal_source, {
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
local false_default_terminal_source =
    transcriber.deep_copy(missing_terminal_source)
false_default_terminal_source[2].has_hit = false
false_default_terminal_source[2].has_contact = nil
local false_default_terminal = transcriber.evaluate(
    false_default_terminal_source,
    {
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
    },
    {
        input_source = "timeline",
        raw_inputs = { 0, 512, 0 },
        input_completed = true,
        allow_legacy_damage_drift = true,
        allow_legacy_outcome_rebuild = true,
    }
)
assert(false_default_terminal.ok == false
        and false_default_terminal.reasons[1]
            == "terminal_expected_contact_missing",
    "a default false must not hide a missed terminal below the source prefix max")
do
local explicit_terminal_noncontact_source = {
    {
        id = 994,
        motion = ">P",
        expected_combo = 5,
        damage_at_step = 2000,
        has_hit = true,
        has_contact = true,
        combo_stats = { damage = 2119 },
    },
    {
        id = 904,
        motion = "214+MP",
        expected_combo = 6,
        damage_at_step = 2119,
        has_hit = false,
    },
}
local explicit_terminal_noncontact = transcriber.evaluate(
    explicit_terminal_noncontact_source,
{
    steps = {
        {
            id = 994,
            motion = ">P",
            expected_combo = 6,
            damage_at_step = 2616,
            has_hit = true,
            has_contact = true,
        },
        {
            id = 904,
            motion = "214+MP",
            expected_combo = 0,
            damage_at_step = 2616,
            has_hit = false,
            has_contact = false,
        },
    },
    stats = {
        damage = 2616,
        max_combo = 6,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 64, 0, 32, 0 },
    input_completed = true,
    allow_legacy_damage_drift = true,
})
assert(explicit_terminal_noncontact.ok == true
    and explicit_terminal_noncontact.source_action_match == true,
    "an explicit terminal noncontact must outrank delayed legacy damage counters")

local lily_command_throw_source = {
    {
        id = 606,
        motion = "HP",
        expected_combo = 1,
        damage_at_step = 1080,
        has_hit = true,
        has_contact = true,
        combo_stats = { damage = 3600 },
        relative_raw_inputs = { 64, 0, 64, 0 },
    },
    {
        id = 1005,
        motion = "360+HP",
        expected_combo = 1,
        damage_at_step = 3600,
        has_hit = false,
        has_contact = false,
    },
}
local unattributed_throw_compiled = {
    steps = {
        {
            id = 606,
            motion = "HP",
            expected_combo = 1,
            damage_at_step = 1080,
            has_hit = true,
            has_contact = true,
        },
        {
            id = 1005,
            motion = "360+HP",
            expected_combo = 0,
            damage_at_step = 1080,
            has_hit = false,
            has_contact = false,
        },
    },
    stats = {
        damage = 1080,
        observed_hp_loss = 3600,
        unconfirmed_hp_loss = 2520,
        passive_damage_ticks = 1,
        passive_damage_total = 2520,
        passive_damage_max_tick = 2520,
        max_combo = 1,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}
local unattributed_throw_capture = transcriber.evaluate(
    lily_command_throw_source,
    unattributed_throw_compiled,
    {
        input_source = "relative_raw_inputs",
        raw_inputs = { 64, 0, 64, 0 },
        input_completed = true,
        allow_legacy_damage_drift = true,
        allow_legacy_outcome_rebuild = true,
    }
)
assert(unattributed_throw_capture.ok == false
        and table.concat(unattributed_throw_capture.reasons, ","):match(
            "unattributed_damage_tick:max=2520:unconfirmed=2520"
        ),
    "legacy damage tolerance must fail closed when a real large damage sample remains unattributed")

local polluted_throw_candidate = transcriber.deep_copy(lily_command_throw_source)
polluted_throw_candidate[1].combo_stats.damage = 1080
polluted_throw_candidate[2].expected_combo = 0
polluted_throw_candidate[2].damage_at_step = 1080
local polluted_throw_verification = transcriber.verify_candidate(
    polluted_throw_candidate,
    unattributed_throw_compiled,
    {
        input_source = "relative_raw_inputs",
        raw_inputs = { 64, 0, 64, 0 },
        input_completed = true,
    }
)
assert(polluted_throw_verification.ok == false
        and table.concat(polluted_throw_verification.reasons, ","):match(
            "raw_replay_unattributed_damage_tick:max=2520:unconfirmed=2520"
        ),
    "a second raw replay must reject an already polluted low-damage throw candidate")

local growing_terminal_damage = transcriber.evaluate(
    explicit_terminal_noncontact_source,
{
    steps = {
        {
            id = 994,
            motion = ">P",
            expected_combo = 6,
            damage_at_step = 2616,
            has_hit = true,
            has_contact = true,
        },
        {
            id = 904,
            motion = "214+MP",
            expected_combo = 0,
            damage_at_step = 2716,
            has_hit = false,
            has_contact = false,
        },
    },
    stats = {
        damage = 2716,
        max_combo = 6,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 64, 0, 32, 0 },
    input_completed = true,
    allow_legacy_damage_drift = true,
})
assert(growing_terminal_damage.ok == false
        and growing_terminal_damage.reasons[1]
            == "terminal_expected_contact_missing",
    "an explicit false must not excuse an observed terminal damage increase")
local zero_combo_terminal = transcriber.evaluate({
    {
        id = 700,
        motion = "THROW",
        expected_combo = 0,
        damage_at_step = 1000,
        has_hit = true,
        has_contact = true,
        combo_stats = { damage = 2000 },
    },
    {
        id = 701,
        motion = "THROW",
        expected_combo = 0,
        damage_at_step = 2000,
        has_hit = false,
    },
}, {
    steps = {
        {
            id = 700,
            motion = "THROW",
            expected_combo = 0,
            damage_at_step = 1000,
            has_hit = true,
            has_contact = true,
        },
        {
            id = 701,
            motion = "THROW",
            expected_combo = 0,
            damage_at_step = 1000,
            has_hit = false,
            has_contact = false,
        },
    },
    stats = {
        damage = 1000,
        max_combo = 0,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 80, 0, 80, 0 },
    input_completed = true,
    allow_legacy_damage_drift = true,
})
assert(zero_combo_terminal.ok == false
        and zero_combo_terminal.reasons[1]
            == "terminal_expected_contact_missing",
    "zero-combo damage must not use the delayed-counter terminal exemption")
end
end
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
local guard_retry_source, guard_retry_adjustments =
    transcriber.prepare_guard_retry(regressed_combo_source, regressed_combo)
assert(type(guard_retry_source) == "table"
    and #guard_retry_adjustments == 1
    and guard_retry_adjustments[1].reason
        == "runtime_blocked_before_expected_combo_completion"
    and guard_retry_source[1].dummy_guard_type == 0
    and guard_retry_source[1]._xt_meta.dummy_guard_type == 0
    and guard_retry_source[1]._xt_meta.environment.dummy_guard_type == 0
    and regressed_combo_source[1]._xt_meta.environment.dummy_guard_type == 2,
    "a runtime-proven obsolete after-first-hit guard must prepare one guardless retry copy")
local no_guard_retry = transcriber.prepare_guard_retry(regressed_combo_source, {
    ok = false,
    reasons = { "combo_count_regressed:expected=3:observed=2" },
})
assert(no_guard_retry == nil,
    "combo regression without observed guard truncation must not disable defense")

do
local poison_masked_reset_source = {
    {
        id = 855,
        motion = "DI",
        expected_combo = 1,
        damage_at_step = 800,
        has_hit = true,
        has_contact = true,
        combo_stats = { damage = 6699 },
    },
    {
        id = 904,
        motion = "214+MP",
        expected_combo = 1,
        damage_at_step = 829,
        has_hit = true,
        has_contact = true,
    },
    {
        id = 37,
        motion = "9",
        expected_combo = 1,
        damage_at_step = 854,
        has_hit = true,
        has_contact = true,
    },
    {
        id = 652,
        motion = "j.HP",
        expected_combo = 2,
        damage_at_step = 1527,
        has_hit = true,
        has_contact = true,
    },
    {
        id = 1260,
        motion = "236236+P",
        expected_combo = 28,
        damage_at_step = 6699,
        has_hit = true,
        has_contact = true,
    },
}
local poison_masked_compiled = {
    steps = {
        {
            id = 855,
            motion = "DI",
            expected_combo = 1,
            damage_at_step = 800,
            has_hit = true,
            has_contact = true,
        },
        {
            id = 904,
            motion = "214+MP",
            expected_combo = 0,
            damage_at_step = 800,
            has_hit = false,
            has_contact = false,
        },
        {
            id = 37,
            motion = "9",
            expected_combo = 0,
            damage_at_step = 800,
            has_hit = false,
            has_contact = false,
        },
        {
            id = 652,
            motion = "j.HP",
            expected_combo = 1,
            damage_at_step = 1673,
            has_hit = true,
            has_contact = true,
        },
        {
            id = 1260,
            motion = "236236+P",
            expected_combo = 27,
            damage_at_step = 7792,
            has_hit = true,
            has_contact = true,
        },
    },
    stats = {
        damage = 7792,
        max_combo = 27,
        unresolved_anchors = 0,
        unresolved_motion_actions = 0,
        block_contacts = 0,
        passive_damage_ticks = 12,
        passive_damage_total = 84,
        passive_damage_max_tick = 7,
    },
    trace = {
        observed_actions = {
            { id = 855, frame = 10 },
            { id = 904, frame = 20 },
            { id = 37, frame = 30 },
            { id = 652, frame = 40 },
            { id = 1260, frame = 50 },
        },
        projected_events = {
            {
                id = 855,
                frame = 10,
                first_contact_frame = 12,
                expected_combo = 1,
                has_hit = true,
                has_contact = true,
            },
            { id = 904, frame = 20, expected_combo = 0 },
            { id = 37, frame = 30, expected_combo = 0 },
            {
                id = 652,
                frame = 40,
                first_contact_frame = 42,
                expected_combo = 1,
                has_hit = true,
                has_contact = true,
            },
            {
                id = 1260,
                frame = 50,
                first_contact_frame = 52,
                expected_combo = 27,
                has_hit = true,
                has_contact = true,
            },
        },
        combo_reset_frames = { 18 },
        passive_damage_frames = { 20, 24, 28, 32, 36 },
        passive_damage_samples = {
            { frame = 20, delta = 7 },
            { frame = 24, delta = 7 },
            { frame = 28, delta = 7 },
            { frame = 32, delta = 7 },
            { frame = 36, delta = 7 },
        },
    },
}
local poison_masked_runtime = {
    input_source = "timeline",
    raw_inputs = { 576, 0, 32, 0, 64, 0, 16, 0 },
    input_completed = true,
    timed_out = false,
    allow_legacy_damage_drift = true,
    allow_legacy_outcome_rebuild = true,
}
local poison_masked_reset = transcriber.evaluate(
    poison_masked_reset_source,
    poison_masked_compiled,
    poison_masked_runtime
)
local poison_reset_advisories = table.concat(
    poison_masked_reset.advisories,
    ","
)
assert(poison_masked_reset.ok == true
        and poison_masked_reset.legacy_segmented_outcome == true
        and poison_masked_reset.expected_reconnect_reason == nil
        and poison_masked_reset.observed_reconnect_reason
            == "observed_hit_reconnect_after_combo_reset"
        and poison_masked_reset.observed_combo_rebuild.reconstructed_combo == 28
        and poison_masked_reset.observed_combo_rebuild.segment_peaks[1] == 1
        and poison_masked_reset.observed_combo_rebuild.segment_peaks[2] == 27
        and poison_masked_reset.persistent_damage_window_ticks[1] == 5
        and poison_reset_advisories:match(
            "source_combo_reset_rebuilt_from_runtime"
        )
        and poison_reset_advisories:match(
            "source_segmented_combo_count_rebuilt:expected=28:observed=27"
        ),
    "runtime Action truth must rebuild a legacy combo count whose reset was masked by poison")
do
local shifted_contact_source = transcriber.deep_copy(poison_masked_reset_source)
table.insert(shifted_contact_source, 5, {
    id = 612,
    motion = "MK",
    expected_combo = 4,
    damage_at_step = 2200,
    has_hit = true,
    has_contact = true,
})
table.insert(shifted_contact_source, 6, {
    id = 603,
    motion = "MP",
    expected_combo = 4,
    damage_at_step = 2500,
    has_hit = true,
    has_contact = true,
})
local shifted_contact_compiled = transcriber.deep_copy(poison_masked_compiled)
table.insert(shifted_contact_compiled.steps, 5, {
    id = 612,
    motion = "MK",
    expected_combo = 2,
    damage_at_step = 2200,
    has_hit = true,
    has_contact = true,
})
table.insert(shifted_contact_compiled.steps, 6, {
    id = 603,
    motion = "MP",
    expected_combo = 3,
    damage_at_step = 2500,
    has_hit = true,
    has_contact = true,
})
table.insert(shifted_contact_compiled.trace.projected_events, 5, {
    id = 612,
    frame = 45,
    first_contact_frame = 47,
    expected_combo = 2,
    has_hit = true,
    has_contact = true,
})
table.insert(shifted_contact_compiled.trace.projected_events, 6, {
    id = 603,
    frame = 51,
    first_contact_frame = 53,
    expected_combo = 3,
    has_hit = true,
    has_contact = true,
})
shifted_contact_compiled.trace.projected_events[7].frame = 60
shifted_contact_compiled.trace.projected_events[7].first_contact_frame = 62
table.insert(shifted_contact_compiled.trace.observed_actions, 5, {
    id = 612,
    frame = 45,
})
table.insert(shifted_contact_compiled.trace.observed_actions, 6, {
    id = 603,
    frame = 51,
})
shifted_contact_compiled.trace.observed_actions[7].frame = 60
local shifted_contact = transcriber.evaluate(
    shifted_contact_source,
    shifted_contact_compiled,
    poison_masked_runtime
)
local shifted_contact_advisories = table.concat(
    shifted_contact.advisories,
    ","
)
assert(shifted_contact.ok == true
        and shifted_contact.legacy_segmented_outcome == true
        and shifted_contact.observed_combo_rebuild.attribution_lead_steps == 1
        and shifted_contact.observed_combo_rebuild.max_attribution_lead == 1
        and shifted_contact_advisories:match(
            "source_contact_attribution_rebuilt:steps=1:max_lead=1"
        ),
    "a source multi-hit count may lead temporarily when the same segment catches up exactly")
local missed_source_contact_compiled =
    transcriber.deep_copy(shifted_contact_compiled)
missed_source_contact_compiled.steps[5].expected_combo = 0
missed_source_contact_compiled.steps[5].has_hit = false
missed_source_contact_compiled.steps[5].has_contact = false
missed_source_contact_compiled.trace.projected_events[5].expected_combo = 0
missed_source_contact_compiled.trace.projected_events[5].has_hit = false
missed_source_contact_compiled.trace.projected_events[5].has_contact = false
missed_source_contact_compiled.trace.projected_events[5].first_contact_frame = nil
local missed_source_contact = transcriber.evaluate(
    shifted_contact_source,
    missed_source_contact_compiled,
    poison_masked_runtime
)
assert(missed_source_contact.ok == false
        and missed_source_contact.observed_combo_rebuild == nil
        and table.concat(missed_source_contact.reasons, ","):match(
            "combo_count_regressed:expected=28:observed=27"
        ),
    "a later catch-up must not hide an authored contact that runtime missed")
local regressing_segment_compiled =
    transcriber.deep_copy(shifted_contact_compiled)
regressing_segment_compiled.steps[6].expected_combo = 1
regressing_segment_compiled.trace.projected_events[6].expected_combo = 1
local regressing_segment = transcriber.evaluate(
    shifted_contact_source,
    regressing_segment_compiled,
    poison_masked_runtime
)
assert(regressing_segment.ok == false
        and regressing_segment.observed_combo_rebuild == nil
        and table.concat(regressing_segment.reasons, ","):match(
            "combo_count_regressed:expected=28:observed=27"
        ),
    "runtime contact combo must not regress inside one reconstructed segment")
local cross_segment_lead_source = transcriber.deep_copy(shifted_contact_source)
cross_segment_lead_source[4].expected_combo = 3
local cross_segment_lead = transcriber.evaluate(
    cross_segment_lead_source,
    shifted_contact_compiled,
    poison_masked_runtime
)
assert(cross_segment_lead.ok == false
        and cross_segment_lead.observed_combo_rebuild == nil
        and table.concat(cross_segment_lead.reasons, ","):match(
            "combo_count_regressed:expected=28:observed=27"
        ),
    "source contact attribution drift must not cross a runtime combo reset")
end
local ordinary_drop_compiled = transcriber.deep_copy(poison_masked_compiled)
ordinary_drop_compiled.trace.passive_damage_frames = { 2, 3, 4, 60, 61 }
ordinary_drop_compiled.trace.passive_damage_samples = {
    { frame = 2, delta = 7 },
    { frame = 3, delta = 7 },
    { frame = 4, delta = 7 },
    { frame = 60, delta = 7 },
    { frame = 61, delta = 7 },
}
local ordinary_drop = transcriber.evaluate(
    poison_masked_reset_source,
    ordinary_drop_compiled,
    poison_masked_runtime
)
assert(ordinary_drop.ok == false
        and ordinary_drop.persistent_damage_evidence == false
        and table.concat(ordinary_drop.reasons, ","):match(
            "combo_count_regressed:expected=28:observed=27"
        ),
    "a normal dropped combo must not be reclassified as a legacy DOT-masked reset")
local large_regression_compiled = transcriber.deep_copy(poison_masked_compiled)
large_regression_compiled.steps[5].expected_combo = 1
large_regression_compiled.stats.max_combo = 1
large_regression_compiled.trace.projected_events[5].expected_combo = 1
local large_regression = transcriber.evaluate(
    poison_masked_reset_source,
    large_regression_compiled,
    poison_masked_runtime
)
assert(large_regression.ok == false
        and large_regression.observed_combo_rebuild == nil
        and table.concat(large_regression.reasons, ","):match(
            "combo_count_regressed:expected=28:observed=1"
        ),
    "persistent damage must not excuse a large combo regression that cannot reconstruct the source total")
end

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

local folded_segmented_source = transcriber.deep_copy(segmented_legacy_source)
folded_segmented_source[3].id = 921
folded_segmented_source[3].motion = "236+MK"
table.insert(folded_segmented_source, 4, {
    id = 926,
    motion = ">6HK",
    expected_combo = 3,
    damage_at_step = 750,
    has_hit = true,
    has_contact = true,
})
local folded_segmented_steps = {
    transcriber.deep_copy(segmented_legacy_steps[1]),
    transcriber.deep_copy(segmented_legacy_steps[2]),
    transcriber.deep_copy(segmented_legacy_steps[3]),
    {
        id = 1001,
        motion = "214+MK",
        expected_combo = 1,
        damage_at_step = 700,
        has_hit = true,
        has_contact = true,
    },
    transcriber.deep_copy(segmented_legacy_steps[5]),
}
local folded_segmented_rebuild = transcriber.evaluate(folded_segmented_source, {
    steps = folded_segmented_steps,
    stats = {
        damage = 1200,
        max_combo = 2,
        super_used = 30000,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 16, 0, 288, 0, 256, 0, 64, 0 },
    input_completed = true,
    allow_legacy_outcome_rebuild = true,
})
assert(folded_segmented_rebuild.ok == true
    and folded_segmented_rebuild.source_action_subsequence_match == false
    and folded_segmented_rebuild.legacy_authored_action_subsequence_match == true
    and folded_segmented_rebuild.legacy_segmented_outcome == true
    and table.concat(folded_segmented_rebuild.advisories, ","):match(
        "source_segmented_action_stream_rebuilt"
    ),
    "a mirrored current Action may replace a folded legacy derived follow-up in a complete segmented route")

local traced_segmented_source = transcriber.deep_copy(folded_segmented_source)
table.insert(traced_segmented_source, 3, {
    id = 480,
    motion = "PARRY",
    expected_combo = 0,
    damage_at_step = 300,
    has_hit = false,
    has_contact = false,
})
table.insert(traced_segmented_source, 4, {
    id = 500,
    motion = "RAW DR",
    expected_combo = 0,
    damage_at_step = 300,
    has_hit = false,
    has_contact = false,
})
local traced_segmented_rebuild = transcriber.evaluate(traced_segmented_source, {
    steps = folded_segmented_steps,
    trace = {
        observed_actions = {
            { id = 600, frame = 10 },
            { id = 700, frame = 15 },
            { id = 500, frame = 20 },
            { id = 480, frame = 25 },
            { id = 500, frame = 30 },
            { id = 1001, frame = 40 },
            { id = 1221, frame = 50 },
        },
    },
    stats = {
        damage = 1200,
        max_combo = 2,
        super_used = 30000,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}, {
    input_source = "timeline",
    raw_inputs = { 16, 0, 288, 0, 256, 0, 64, 0 },
    input_completed = true,
    allow_legacy_outcome_rebuild = true,
})
assert(traced_segmented_rebuild.ok == true
    and traced_segmented_rebuild.source_action_subsequence_match == false
    and traced_segmented_rebuild.legacy_authored_action_subsequence_match == true
    and traced_segmented_rebuild.legacy_segmented_outcome == true,
    "a complete observed Action trace may prove legacy transient states omitted from command rows")

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

local crouch_environment_source = transcriber.deep_copy(regressed_combo_source)
crouch_environment_source[1].dummy_action_type = 1
crouch_environment_source[1].requires_dummy_crouch = true
crouch_environment_source[1]._xt_meta.environment.dummy_action_type = 1
local crouch_environment_mismatch = transcriber.evaluate(crouch_environment_source, {
    steps = crouch_environment_source,
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
        dummy_action_type = 0,
        dummy_counter_type = 2,
        dummy_guard_type = 2,
        dummy_guard_count = 10,
    },
})
assert(crouch_environment_mismatch.ok == false
    and crouch_environment_mismatch.reasons[1]
        == "training_environment_mismatch:"
            .. "dummy_action_type:expected=1:actual=0",
    "transcription must reject a crouch requirement that remained standing")

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
        local rule = CharacterRules.get_match_rule(
            nil,
            COMMON_ACTION_VARIANT_FIXTURES,
            "Ryu",
            expected_id
        )
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
do
local legacy_owner_rules = {
    ["944"] = {
        absorb_ids = "936,941,945",
        record_absorb_as_parent = true,
    },
}
local legacy_owner_source = {
    {
        id = 944,
        motion = "236+PP",
        expected_combo = 2,
        damage_at_step = 600,
        has_hit = true,
        has_contact = true,
        combo_stats = { damage = 600 },
    },
}
local legacy_owner_compiled = {
    steps = {
        {
            id = 945,
            motion = "214+MP+HP",
            expected_combo = 2,
            damage_at_step = 600,
            has_hit = true,
            has_contact = true,
        },
    },
    stats = {
        damage = 600,
        max_combo = 2,
        unresolved_anchors = 0,
        block_contacts = 0,
    },
}
local function legacy_owner_equivalent(expected_id, observed_id)
    return CharacterRules.find_recording_absorb_owner(
        legacy_owner_rules,
        nil,
        observed_id
    ) == expected_id
end
local legacy_owner_evaluation = transcriber.evaluate(
    legacy_owner_source,
    legacy_owner_compiled,
    {
        input_source = "timeline",
        raw_inputs = { 96, 0 },
        input_completed = true,
        action_ids_equivalent = function() return false end,
        source_action_ids_equivalent = legacy_owner_equivalent,
    }
)
assert(legacy_owner_evaluation.ok == true
        and legacy_owner_evaluation.source_action_match == true,
    "an explicit recording owner may bridge only the old derived source comparison")
assert(legacy_owner_equivalent(945, 944) == false
        and legacy_owner_equivalent(944, 946) == false,
    "recording-owner compatibility must be one-way and fail closed for unrelated Actions")
local legacy_owner_candidate = assert(transcriber.build_candidate(
    legacy_owner_source,
    legacy_owner_compiled,
    {
        schema = 2,
        product_id = "sf6cc",
        product_version = "1.0.4",
        json_id = "xt.combo_trial",
        json_version = "2",
    },
    "2026-08-01T00:00:00+08:00",
    {
        input_source = "timeline",
        relative_raw_inputs = { 96, 0 },
    }
))
assert(legacy_owner_candidate[1].id == 945,
    "a bridged legacy owner must compile to the observed runtime child Action")

local legacy_pc_candidate = assert(transcriber.build_candidate(
    {
        {
            id = 606,
            motion = "HP",
            counter_type = 2,
            expected_combo = 1,
            damage_at_step = 1080,
            has_hit = true,
            has_contact = true,
            combo_stats = { damage = 1080, hit_type = "PC" },
            timeline = { "1f : HP", "1f : 5" },
            _xt_meta = { schema = 2 },
        },
    },
    {
        steps = {
            {
                id = 606,
                motion = "HP",
                expected_combo = 1,
                damage_at_step = 1080,
                has_hit = true,
                has_contact = true,
            },
        },
        stats = { damage = 1080, drive_used = 0, super_used = 0 },
    },
    {
        schema = 2,
        product_id = "sf6cc",
        product_version = "1.0.4",
        json_id = "xt.combo_trial",
        json_version = "2",
    },
    "2026-08-02T00:00:00+08:00",
    {
        input_source = "timeline",
        relative_raw_inputs = { 64, 0 },
    }
))
assert(legacy_pc_candidate[1].dummy_counter_type == 2
        and legacy_pc_candidate[1]._xt_meta.dummy_counter_type == 2
        and legacy_pc_candidate[1]._xt_meta.environment.dummy_counter_type == 2
        and legacy_pc_candidate[1].combo_stats.hit_type == "PC"
        and legacy_pc_candidate[1].counter_type == nil,
    "candidate construction must persist a legacy punish-counter policy before deleting derived step fields")
require("func/ComboTrials/TrainingEnvironment").normalize_counter_policy(
    legacy_pc_candidate,
    false
)
assert(legacy_pc_candidate[1].dummy_counter_type == 2
        and legacy_pc_candidate[1].combo_stats.hit_type == "PC",
    "strict later normalization must retain the candidate's canonical punish-counter policy")
local real_child_verified = transcriber.verify_candidate(
    legacy_owner_candidate,
    legacy_owner_compiled,
    {
        raw_inputs = { 96, 0 },
        input_source = "relative_raw_inputs",
        input_completed = true,
    }
)
assert(real_child_verified.ok == true,
    "the generated real child Action must verify against the same runtime ID")
local owner_instead_of_child = transcriber.deep_copy(legacy_owner_compiled)
owner_instead_of_child.steps[1].id = 944
local owner_instead_of_child_verified = transcriber.verify_candidate(
    legacy_owner_candidate,
    owner_instead_of_child,
    {
        raw_inputs = { 96, 0 },
        input_source = "relative_raw_inputs",
        input_completed = true,
    }
)
assert(owner_instead_of_child_verified.ok == false
        and table.concat(owner_instead_of_child_verified.reasons, ","):match(
            "raw_replay_action_id_mismatch"
        ),
    "raw replay must reject the old owner when the candidate captured its real child")
local strict_owner_verification = transcriber.verify_candidate(
    legacy_owner_source,
    legacy_owner_compiled,
    {
        raw_inputs = { 96, 0 },
        input_source = "raw_inputs",
        input_completed = true,
        source_action_ids_equivalent = legacy_owner_equivalent,
    }
)
assert(strict_owner_verification.ok == false
        and table.concat(strict_owner_verification.reasons, ","):match(
            "raw_replay_action_id_mismatch"
        ),
    "the legacy owner bridge must not weaken generated candidate raw replay IDs")
end
for _, pair in ipairs({ { 970, 971 }, { 971, 970 }, { 972, 973 }, { 973, 972 } }) do
    local rule = CharacterRules.get_match_rule(
        HONDA_ACTION_VARIANT_FIXTURES,
        nil,
        "EHonda",
        pair[1]
    )
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
do
local missing_health_scene_source = {
    {
        id = 1216,
        motion = "236236+P",
        expected_hp = 10000,
        recorded_by = 0,
        scene_state = {
            schema = "xt.combo_trial.scene.v1",
            recorded_by = 0,
            players = {
                p1 = { fighter_id = 12, unique = { stock_0_012 = 0 } },
                p2 = { fighter_id = 1 },
            },
        },
    },
}
local prepared_missing_health, missing_health_adjustments =
    transcriber.prepare_capture_sequence(missing_health_scene_source)
local prepared_missing_health_roles =
    SceneState.resolve_roles(prepared_missing_health[1], 0)
assert(#missing_health_adjustments == 1
        and missing_health_adjustments[1].from == nil
        and missing_health_adjustments[1].to == 10000
        and SceneState.resources(prepared_missing_health_roles.actor).hp == 10000
        and SceneState.resources(prepared_missing_health_roles.actor).heal_hp == 10000
        and missing_health_scene_source[1].scene_state.players.p1.resources == nil,
    "stable legacy expected_hp must materialize a missing actor resource block on the transcription copy")
local leaked_health_evaluation = transcriber.evaluate(
    missing_health_scene_source,
    {
        steps = missing_health_scene_source,
        stats = {
            damage = 0,
            max_combo = 0,
            unresolved_anchors = 0,
            block_contacts = 0,
            actor_hp = 2000,
        },
    },
    {
        input_source = "timeline",
        raw_inputs = { 16, 0 },
        input_completed = true,
    }
)
assert(leaked_health_evaluation.ok == false
        and leaked_health_evaluation.reasons[1]
            == "actor_hp_mismatch:expected=10000:observed=2000",
    "a leaked training-menu HP value must fail before it can rewrite a self-consistent candidate")
end

do
local legacy_meter_source = {
    {
        id = 740,
        motion = "RAW DR",
        recorded_by = 0,
        combo_stats = {
            damage = 5800,
            drive_used = 60000,
            super_used = 14800,
        },
        scene_state = {
            schema = "xt.combo_trial.scene.v1",
            recorded_by = 0,
            players = {
                p1 = { fighter_id = 12, unique = { stock_0_012 = 2 } },
                p2 = { fighter_id = 1 },
            },
        },
    },
}
local prepared_meter, meter_adjustments =
    transcriber.prepare_capture_sequence(legacy_meter_source)
local prepared_meter_actor =
    SceneState.resolve_roles(prepared_meter[1], 0).actor.state
assert(#meter_adjustments == 3
        and meter_adjustments[1].field
            == "scene_state.actor.resources.drive"
        and meter_adjustments[1].reason
            == "legacy_combo_usage_requires_full_drive"
        and meter_adjustments[2].field
            == "scene_state.actor.status.burnout"
        and meter_adjustments[3].field
            == "scene_state.actor.resources.super"
        and prepared_meter_actor.resources.drive == 60000
        and prepared_meter_actor.resources.super == 30000
        and prepared_meter_actor.status.burnout == false
        and prepared_meter_actor.unique.stock_0_012 == 2
        and legacy_meter_source[1].scene_state.players.p1.resources == nil
        and legacy_meter_source[1].scene_state.players.p1.status == nil,
    "legacy meter-consuming routes must materialize full active gauges only on the transcription copy")

local prepared_meter_again, repeated_meter_adjustments =
    transcriber.prepare_capture_sequence(prepared_meter)
assert(#repeated_meter_adjustments == 0
        and prepared_meter_again[1].scene_state.players.p1.resources.drive == 60000
        and prepared_meter_again[1].scene_state.players.p1.resources.super == 30000,
    "legacy full-gauge reconstruction must be idempotent")

local low_usage_meter_source = transcriber.deep_copy(legacy_meter_source)
low_usage_meter_source[1].combo_stats.drive_used = 10000
low_usage_meter_source[1].combo_stats.super_used = 6900
local prepared_low_usage_meter, low_usage_meter_adjustments =
    transcriber.prepare_capture_sequence(low_usage_meter_source)
assert(#low_usage_meter_adjustments == 3
        and prepared_low_usage_meter[1].scene_state.players.p1.resources.drive == 60000
        and prepared_low_usage_meter[1].scene_state.players.p1.resources.super == 30000,
    "lower legacy meter consumption must still restore the recorder's full-gauge default")

local p2_meter_source = transcriber.deep_copy(legacy_meter_source)
p2_meter_source[1].recorded_by = 1
p2_meter_source[1].scene_state.recorded_by = 1
p2_meter_source[1].scene_state.players.p1 = { fighter_id = 1 }
p2_meter_source[1].scene_state.players.p2 = {
    fighter_id = 12,
    unique = { stock_0_012 = 2 },
}
local prepared_p2_meter, p2_meter_adjustments =
    transcriber.prepare_capture_sequence(p2_meter_source)
assert(#p2_meter_adjustments == 3
        and prepared_p2_meter[1].scene_state.players.p1.resources == nil
        and prepared_p2_meter[1].scene_state.players.p2.resources.drive == 60000
        and prepared_p2_meter[1].scene_state.players.p2.resources.super == 30000,
    "legacy gauge reconstruction must follow recorded_by and repair only the actor side")

local authoritative_meter_source = transcriber.deep_copy(legacy_meter_source)
authoritative_meter_source[1].scene_state.schema = "xt.combo_trial.scene.v2"
local prepared_authoritative_meter, authoritative_meter_adjustments =
    transcriber.prepare_capture_sequence(authoritative_meter_source)
assert(#authoritative_meter_adjustments == 0
        and prepared_authoritative_meter[1].scene_state.players.p1.resources == nil,
    "a V2 scene must never receive inferred attacker gauges")

local explicit_legacy_meter_source = transcriber.deep_copy(legacy_meter_source)
explicit_legacy_meter_source[1].scene_state.players.p1.resources = {
    drive = 25000,
    super = 20000,
}
explicit_legacy_meter_source[1].scene_state.players.p1.status = { burnout = false }
local prepared_explicit_meter, explicit_meter_adjustments =
    transcriber.prepare_capture_sequence(explicit_legacy_meter_source)
assert(#explicit_meter_adjustments == 0
        and prepared_explicit_meter[1].scene_state.players.p1.resources.drive == 25000
        and prepared_explicit_meter[1].scene_state.players.p1.resources.super == 20000,
    "explicit legacy attacker gauges must outrank inferred full-gauge defaults")

local explicit_zero_meter_source = transcriber.deep_copy(legacy_meter_source)
explicit_zero_meter_source[1].scene_state.players.p1.resources = {
    drive = 0,
    super = 0,
}
explicit_zero_meter_source[1].scene_state.players.p1.status = { burnout = false }
local prepared_zero_meter, zero_meter_adjustments =
    transcriber.prepare_capture_sequence(explicit_zero_meter_source)
assert(#zero_meter_adjustments == 0
        and prepared_zero_meter[1].scene_state.players.p1.resources.drive == 0
        and prepared_zero_meter[1].scene_state.players.p1.resources.super == 0,
    "explicit legacy zero gauges must not be mistaken for missing values")

local explicit_burnout_source = transcriber.deep_copy(legacy_meter_source)
explicit_burnout_source[1].combo_stats.super_used = 0
explicit_burnout_source[1].scene_state.players.p1.status = { burnout = true }
local prepared_burnout_meter, burnout_meter_adjustments =
    transcriber.prepare_capture_sequence(explicit_burnout_source)
assert(#burnout_meter_adjustments == 0
        and prepared_burnout_meter[1].scene_state.players.p1.resources.drive == nil
        and prepared_burnout_meter[1].scene_state.players.p1.status.burnout == true,
    "an explicit legacy burnout state must block inferred active Drive")

local invalid_meter_source = transcriber.deep_copy(legacy_meter_source)
invalid_meter_source[1].combo_stats.drive_used = 60001
invalid_meter_source[1].combo_stats.super_used = 30001
local prepared_invalid_meter, invalid_meter_adjustments =
    transcriber.prepare_capture_sequence(invalid_meter_source)
assert(#invalid_meter_adjustments == 0
        and next(prepared_invalid_meter[1].scene_state.players.p1.resources) == nil,
    "out-of-range legacy meter telemetry must not become an inferred scene")
end

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

do
local legacy_step_counter_source = {
    {
        id = 606,
        motion = "HP",
        counter_type = 2,
        expected_combo = 1,
        damage_at_step = 1080,
        has_hit = true,
        has_contact = true,
    },
}
local prepared_step_counter, step_counter_adjustments =
    transcriber.prepare_capture_sequence(legacy_step_counter_source)
assert(#step_counter_adjustments == 1
        and step_counter_adjustments[1].reason
            == "legacy_counter_policy_canonicalized:legacy_step"
        and prepared_step_counter[1].dummy_counter_type == 2
        and prepared_step_counter[1]._xt_meta.environment.dummy_counter_type == 2
        and legacy_step_counter_source[1].dummy_counter_type == nil,
    "the capture copy must persist a legacy step-level punish counter before derived fields are removed")

local bulk_default_counter_source = {
    {
        id = 606,
        motion = "HP",
        counter_type = 2,
        dummy_counter_type = 0,
        expected_combo = 1,
        damage_at_step = 1080,
        has_hit = true,
        has_contact = true,
        combo_stats = { damage = 1080, hit_type = "PC" },
        _xt_meta = {
            dummy_counter_type = 0,
            environment = { dummy_counter_type = 0 },
        },
    },
}
local prepared_bulk_counter, bulk_counter_adjustments =
    transcriber.prepare_capture_sequence(bulk_default_counter_source)
assert(#bulk_counter_adjustments == 1
        and bulk_counter_adjustments[1].reason
            == "legacy_counter_policy_canonicalized:legacy_consensus"
        and bulk_counter_adjustments[1].from == 0
        and prepared_bulk_counter[1].dummy_counter_type == 2
        and prepared_bulk_counter[1]._xt_meta.environment.dummy_counter_type == 2,
    "agreeing legacy counter facts must override bulk-filled NORMAL mirrors")

local stale_stats_only = transcriber.deep_copy(bulk_default_counter_source)
stale_stats_only[1].counter_type = nil
local prepared_stale_stats, stale_stats_adjustments =
    transcriber.prepare_capture_sequence(stale_stats_only)
assert(#stale_stats_adjustments == 0
        and prepared_stale_stats[1].dummy_counter_type == 0,
    "one stale legacy counter field must not override an explicit NORMAL policy")
end

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
local honda_transcription_rules = CharacterRules.build_transcription_rules(
    ACTION_EVENT_FIXTURES.EHonda,
    {}
)
local prepared_honda_buff, honda_buff_adjustments =
    transcriber.prepare_capture_sequence(
        honda_legacy_buff_source,
        honda_transcription_rules
    )
local prepared_honda_roles = SceneState.resolve_roles(prepared_honda_buff[1], 0)
assert(#honda_buff_adjustments == 1
    and honda_buff_adjustments[1].field
        == "scene_state.actor.unique.stock_0_020"
    and honda_buff_adjustments[1].reason
        == "source_action_requires_unique_resource"
    and prepared_honda_roles.actor.state.unique.stock_0_020 == 1
    and honda_legacy_buff_source[1].scene_state.players.p1.unique.stock_0_020 == 0,
    "an enhanced Honda Action must repair missing initial Sumo Spirit on the copied scene")
local honda_buff_causes = transcriber.suspected_causes(
    honda_legacy_buff_source,
    honda_transcription_rules
)
assert(table.concat(honda_buff_causes, ","):match(
        "actor_character_resource_required"
    ),
    "enhanced Honda Actions must diagnose a missing unique resource")

local honda_runtime_buff_source = transcriber.deep_copy(honda_legacy_buff_source)
honda_runtime_buff_source[1].id = 970
honda_runtime_buff_source[1].scene_state.players.p1.unique.stock_0_020 = 0
honda_runtime_buff_source[2] = { id = 926, motion = "214+HP", expected_hp = 10500 }
local prepared_runtime_buff, runtime_buff_adjustments =
    transcriber.prepare_capture_sequence(
        honda_runtime_buff_source,
        honda_transcription_rules
    )
assert(#runtime_buff_adjustments == 0
    and prepared_runtime_buff[1].scene_state.players.p1.unique.stock_0_020 == 0,
    "a replay that establishes Honda stock before the enhanced Action must retain stock zero")

do
local legacy_wall_stun_source = {
    {
        id = 855,
        motion = "DI",
        expected_combo = 1,
        damage_at_step = 800,
        has_hit = true,
        has_contact = true,
        has_piyo = true,
        piyo_frame = 149,
        recorded_by = 0,
        dummy_guard_type = 2,
        scene_state = {
            schema = "xt.combo_trial.scene.v2",
            recorded_by = 0,
            players = {
                p1 = {
                    resources = { drive = 60000 },
                    status = { burnout = false },
                },
                p2 = {
                    resources = { drive = 60000 },
                    status = { burnout = false },
                },
            },
        },
        _xt_meta = {
            dummy_guard_type = 2,
            environment = { dummy_guard_type = 2 },
        },
    },
}
local prepared_wall_stun, wall_stun_adjustments =
    transcriber.prepare_capture_sequence(legacy_wall_stun_source)
assert(#wall_stun_adjustments == 3
        and prepared_wall_stun[1].scene_state.players.p2.resources.drive == 0
        and prepared_wall_stun[1].scene_state.players.p2.status.burnout == true
        and prepared_wall_stun[1].dummy_guard_type == 3
        and legacy_wall_stun_source[1].scene_state.players.p2.resources.drive == 60000
        and legacy_wall_stun_source[1].scene_state.players.p2.status.burnout == false,
    "runtime-proven opening wall stun must repair burnout and Guard All only on the copied pseudo-V2 scene")
local alternate_di_id_source = transcriber.deep_copy(legacy_wall_stun_source)
alternate_di_id_source[1].id = 9999
local prepared_alternate_di, alternate_di_adjustments =
    transcriber.prepare_capture_sequence(alternate_di_id_source)
assert(#alternate_di_adjustments == 3
        and prepared_alternate_di[1].scene_state.players.p2.resources.drive == 0,
    "wall-stun repair must follow recorded DI facts instead of hardcoded Action IDs")
local prepared_wall_stun_again, repeated_wall_stun_adjustments =
    transcriber.prepare_capture_sequence(prepared_wall_stun)
assert(#repeated_wall_stun_adjustments == 0
        and prepared_wall_stun_again[1].scene_state.players.p2.resources.drive == 0
        and prepared_wall_stun_again[1].scene_state.players.p2.status.burnout == true,
    "legacy wall-stun scene repair must be idempotent")

local blocked_wall_stun_source = transcriber.deep_copy(legacy_wall_stun_source)
blocked_wall_stun_source[1].has_hit = false
blocked_wall_stun_source[1].has_contact = false
blocked_wall_stun_source[1].expected_combo = 0
local prepared_blocked_wall_stun, blocked_wall_stun_adjustments =
    transcriber.prepare_capture_sequence(blocked_wall_stun_source)
assert(#blocked_wall_stun_adjustments == 3
        and prepared_blocked_wall_stun[1].dummy_guard_type == 3
        and prepared_blocked_wall_stun[1]._xt_meta.dummy_guard_type == 3
        and prepared_blocked_wall_stun[1]._xt_meta.environment.dummy_guard_type == 3
        and blocked_wall_stun_source[1].dummy_guard_type == 2,
    "a runtime-proven blocked wall stun must restore Guard All on the copied environment")

local ordinary_di_source = transcriber.deep_copy(legacy_wall_stun_source)
ordinary_di_source[1].has_piyo = false
local prepared_ordinary_di, ordinary_di_adjustments =
    transcriber.prepare_capture_sequence(ordinary_di_source)
assert(#ordinary_di_adjustments == 0
        and prepared_ordinary_di[1].scene_state.players.p2.resources.drive == 60000,
    "an ordinary opening DI must never infer defender burnout")
local incomplete_piyo_source = transcriber.deep_copy(legacy_wall_stun_source)
incomplete_piyo_source[1].piyo_frame = nil
local prepared_incomplete_piyo, incomplete_piyo_adjustments =
    transcriber.prepare_capture_sequence(incomplete_piyo_source)
assert(#incomplete_piyo_adjustments == 0
        and prepared_incomplete_piyo[1].scene_state.players.p2.resources.drive == 60000,
    "a legacy piyo flag without its runtime frame must not rewrite the scene")
local p2_recorded_stun = transcriber.deep_copy(legacy_wall_stun_source)
p2_recorded_stun[1].recorded_by = 1
p2_recorded_stun[1].scene_state.recorded_by = 1
local prepared_p2_stun, p2_stun_adjustments =
    transcriber.prepare_capture_sequence(p2_recorded_stun)
assert(#p2_stun_adjustments == 0
        and prepared_p2_stun[1].scene_state.players.p1.resources.drive == 60000,
    "the old P2-only stun detector must not infer roles for a P2 recording")
local authoritative_v2_stun = transcriber.deep_copy(legacy_wall_stun_source)
authoritative_v2_stun[1].scene_state.players.p2.status.stunned = false
authoritative_v2_stun[1].scene_state.players.p2.status.stance = "standing"
authoritative_v2_stun[1].snapshot_gauges = {
    defender_drive = 0,
    defender_burnout = true,
}
local prepared_authoritative_stun, authoritative_stun_adjustments =
    transcriber.prepare_capture_sequence(authoritative_v2_stun)
assert(#authoritative_stun_adjustments == 0
        and prepared_authoritative_stun[1].scene_state.players.p2.resources.drive == 60000,
    "a complete live-captured V2 scene must outrank inferred legacy stun state")
end

do
local wall_stun_outcome_source = {
    {
        id = 855,
        motion = "DI",
        expected_combo = 1,
        damage_at_step = 800,
        expected_hp = 10000,
        has_hit = true,
        has_contact = true,
        has_piyo = true,
        piyo_frame = 149,
        recorded_by = 0,
        combo_stats = { damage = 3060, drive_used = 10000, super_used = 0 },
        scene_state = {
            schema = "xt.combo_trial.scene.v1",
            recorded_by = 0,
            players = {
                p1 = { fighter_id = 12 },
                p2 = { fighter_id = 1 },
            },
        },
    },
    { id = 900, motion = "214+LP", expected_combo = 1, damage_at_step = 800, expected_hp = 10000, has_hit = true, has_contact = true },
    { id = 606, motion = "HP", expected_combo = 2, damage_at_step = 1520, expected_hp = 10000, has_hit = true, has_contact = true },
    { id = 929, motion = "236+HK", expected_combo = 5, damage_at_step = 2360, expected_hp = 10000, has_hit = true, has_contact = true },
    { id = 941, motion = "623+HP", expected_combo = 7, damage_at_step = 3060, expected_hp = 10000, has_hit = true, has_contact = true },
}
local prepared_wall_stun_outcome, wall_stun_outcome_adjustments =
    transcriber.prepare_capture_sequence(wall_stun_outcome_source)
local wall_stun_runtime_steps = {
    { id = 855, motion = "DI", expected_combo = 0, damage_at_step = 200, expected_hp = 10000, has_hit = true, has_contact = true, delay_from_prev = 0 },
    { id = 900, motion = "214+LP", expected_combo = 0, damage_at_step = 200, expected_hp = 10000, has_hit = true, has_contact = true, delay_from_prev = 160 },
    { id = 606, motion = "HP", expected_combo = 1, damage_at_step = 920, expected_hp = 10000, has_hit = true, has_contact = true, delay_from_prev = 30 },
    { id = 929, motion = "236+HK", expected_combo = 4, damage_at_step = 1760, expected_hp = 10000, has_hit = true, has_contact = true, delay_from_prev = 20 },
    { id = 941, motion = "623+HP", expected_combo = 6, damage_at_step = 2460, expected_hp = 10000, has_hit = true, has_contact = true, delay_from_prev = 20 },
}
local wall_stun_compiled = {
    steps = wall_stun_runtime_steps,
    stats = {
        damage = 2460,
        max_combo = 6,
        block_contacts = 0,
        drive_used = 10000,
        super_used = 0,
        actor_hp = 10000,
        unresolved_anchors = 0,
        fallback_motion_actions = 0,
        unresolved_motion_actions = 0,
        resolver_error_actions = 0,
        unconfirmed_hp_loss = 0,
        passive_damage_ticks = 0,
        passive_damage_total = 0,
    },
}
local wall_stun_outcome_evaluation = transcriber.evaluate(
    prepared_wall_stun_outcome,
    wall_stun_compiled,
    {
        input_source = "timeline",
        raw_inputs = { 64 | 512, 0, 16, 0, 64, 0, 512, 0, 64, 0 },
        input_completed = true,
        allow_legacy_outcome_rebuild = true,
        environment_adjustments = wall_stun_outcome_adjustments,
        verify_environment = true,
        environment_observed = { dummy_guard_type = 3 },
    }
)
assert(wall_stun_outcome_evaluation.ok == true
        and wall_stun_outcome_evaluation.blocked_wall_stun_shift.damage_shift == 600
        and table.concat(wall_stun_outcome_evaluation.advisories, ","):find(
            "source_blocked_wall_stun_combo_rebuilt:expected=7:observed=6",
            1,
            true
        ) ~= nil,
    "an exact blocked wall-stun trace may correct the legacy recorder's constant one-hit offset once")
local wall_stun_without_proof = transcriber.evaluate(
    prepared_wall_stun_outcome,
    wall_stun_compiled,
    {
        input_source = "timeline",
        raw_inputs = { 64 | 512, 0, 16, 0, 64, 0, 512, 0, 64, 0 },
        input_completed = true,
        allow_legacy_outcome_rebuild = true,
        verify_environment = true,
        environment_observed = { dummy_guard_type = 3 },
    }
)
assert(wall_stun_without_proof.ok == false,
    "the same combo regression must fail without a recorded legacy wall-stun scene adjustment")
end

-- A legacy file can contain both a correct timeline and a screen-absolute raw
-- stream. Conversion must discard the latter so old WTT falls back to timeline.
source[1].raw_inputs = { 8, 0 }
local candidate = assert(transcriber.build_candidate(source, result, {
    schema = 2,
    product_id = "sf6cc",
    product_version = "1.0.4",
    json_id = "xt.combo_trial",
    json_version = "2",
}, "2026-07-30T00:00:00+08:00", {
    input_source = "timeline",
    relative_raw_inputs = { 0, 2, 18, 18, 2, 0 },
    environment_adjustments = oki_adjustments,
}))
assert(candidate[1].id == 600 and candidate[1].motion == "2+LP",
    "candidate steps must come from the new runtime compiler")
assert(candidate[1].timeline[2] == "1f : 2+LP",
    "the input truth must be copied without rewriting")
assert(candidate[1].raw_inputs == nil
    and #candidate[1].relative_raw_inputs == 6
    and candidate[1].relative_raw_inputs[3] == 18,
    "timeline transcription must emit only a facing-portable raw input stream")
assert(candidate[1]._xt_meta.transcription.input_stream_origin
        == "captured_timeline_replay"
    and candidate[1]._xt_meta.transcription.portable_input.encoding
        == "facing_relative_v1",
    "candidate metadata must disclose how portable raw input was obtained")
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
    relative_raw_inputs = { 16 },
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
    raw_inputs = candidate[1].relative_raw_inputs,
    input_source = "relative_raw_inputs",
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
    raw_inputs = candidate[1].relative_raw_inputs,
    input_source = "relative_raw_inputs",
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
        raw_inputs = honda_variant_candidate[1].relative_raw_inputs,
        input_source = "relative_raw_inputs",
        input_completed = true,
        action_ids_equivalent = function(expected_id, observed_id)
            local rule = CharacterRules.get_match_rule(
                HONDA_ACTION_VARIANT_FIXTURES,
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

do
local audit_paths = {
    "TrainingComboTrials_data\\CustomCombos\\Ingrid\\A.json",
    "TrainingComboTrials_data\\CustomCombos\\Ingrid\\B.json",
    "TrainingComboTrials_data\\CustomCombos\\Ingrid\\C.json",
}
local audit_retry = transcriber.new_run(
    "Ingrid",
    audit_paths,
    "2026-08-03T02:18:09+08:00",
    { scope = "audit_failures" }
)
audit_retry.active = false
audit_retry.items = {
    {
        source_file = audit_paths[1],
        status = "passed",
        raw_replay_verified = true,
        validation_revision = transcriber.VALIDATION_REVISION,
    },
    {
        source_file = audit_paths[2],
        status = "failed",
        raw_replay_verified = false,
        validation_revision = transcriber.VALIDATION_REVISION,
    },
}
audit_retry.passed = 1
audit_retry.failed = 1
local audit_report = transcriber.report(audit_retry)
assert(#audit_report.source_paths == 3,
    "audit-failure reports must persist their original target subset")
local audit_resume = assert(transcriber.resume_run(audit_report, "Ingrid", {
    audit_paths[1],
    audit_paths[2],
    audit_paths[3],
    "TrainingComboTrials_data\\CustomCombos\\Ingrid\\Unrelated.json",
}, "2026-08-03T02:30:00+08:00"))
assert(audit_resume.transcription_scope == "audit_failures"
    and #audit_resume.paths == 1
    and audit_resume.paths[1]:match("C%.json$")
    and #audit_resume.source_paths == 3,
    "audit-failure resume must continue only the original unprocessed subset")

local repair_retry = transcriber.failure_retry_run({
    character = "Ingrid",
    transcription_scope = "audit_failures",
    items = {
        {
            source_file = audit_paths[1],
            candidate_file = "Candidates/Ingrid/A.json",
            status = "passed",
            raw_replay_verified = true,
        },
        {
            source_file = audit_paths[2],
            candidate_file = "Candidates/Ingrid/B.json",
            status = "passed",
            raw_replay_verified = true,
        },
    },
}, "Ingrid", { audit_paths[1] }, "2026-08-03T02:35:00+08:00")
assert(#repair_retry.items == 1
        and repair_retry.items[1].source_file == audit_paths[2]
        and #repair_retry.paths == 1
        and repair_retry.total == 2,
    "retrying a stale pass must not retain its obsolete report item")
end

do
local single_run = transcriber.new_run(
    "Ken",
    { "TrainingComboTrials_data\\CustomCombos\\Ken\\A.json" },
    "2026-08-01T12:30:00+08:00",
    {
        scope = "current",
        requested_path = "TrainingComboTrials_data\\CustomCombos\\Ken\\A.json",
    }
)
single_run.active = false
local single_report = transcriber.report(single_run)
assert(single_report.transcription_scope == "current"
    and single_report.requested_path:match("A%.json$")
    and transcriber.resume_info(single_report, "Ken", {
        "TrainingComboTrials_data\\CustomCombos\\Ken\\A.json",
        "TrainingComboTrials_data\\CustomCombos\\Ken\\B.json",
    }) == nil,
    "single transcription reports must round-trip scope without offering a character-wide resume")

local single_retry = transcriber.failure_retry_run({
    character = "Ken",
    transcription_scope = "current",
    requested_path = single_report.requested_path,
    items = {
        {
            source_file = single_report.requested_path,
            status = "failed",
            raw_replay_verified = false,
        },
    },
}, "Ken", { single_report.requested_path }, "2026-08-01T12:35:00+08:00")
single_retry.active = false
assert(single_retry.transcription_scope == "current"
    and single_retry.requested_path == single_report.requested_path
    and transcriber.resume_info(single_retry, "Ken", {
        single_report.requested_path,
        "TrainingComboTrials_data\\CustomCombos\\Ken\\B.json",
    }) == nil,
    "retrying a single transcription must not become a character-wide resumable run")
end

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
        transcription_scope = "current",
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
do
local latest_full_path = transcriber.select_latest_report(
    report_paths,
    function(path) return reports_by_path[path] end,
    transcriber.REPORT_SCHEMA,
    function(report)
        return report.transcription_scope == nil
            or report.transcription_scope == "all"
    end
)
assert(latest_full_path == report_paths[2],
    "single reports must not hide the latest resumable character-wide report")
end

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

function test_data_driven_recent_regressions()
    local jamie_transient = new_character_rule_session("Jamie")
    jamie_transient.events = {
        {
            id = 512,
            frame = 100,
            expected_combo = 0,
            damage_at_step = 0,
            has_hit = false,
            has_contact = false,
            anchor = { kind = "button_press", pressed_buttons = 32 },
        },
        {
            id = 628,
            frame = 101,
            expected_combo = 1,
            damage_at_step = 600,
            has_hit = true,
            has_contact = true,
            anchor = { kind = "button_press", pressed_buttons = 32 },
        },
    }
    jamie_transient.current_damage = 600
    jamie_transient.max_combo = 1
    local jamie_transient_result = compiler.finalize(jamie_transient, {
        motion_resolver = function(action_id)
            if action_id == 512 then return "MP", "strict_route" end
            if action_id == 628 then return "2+MP", "strict_route" end
            return nil, "action_id_missing"
        end,
    })
    assert(#jamie_transient_result.steps == 1
            and jamie_transient_result.steps[1].id == 628
            and jamie_transient_result.trace.suppressed_events[1].id == 512
            and jamie_transient_result.trace.suppressed_events[1].reason
                == "character_transient_input_precursor",
        "Jamie transient input mappings must come from injected exception data")

    local runtime_transient = ActionMatcher.classify_runtime_transition({
        expected_step = { id = 628 },
        actual_action_id = 512,
        input_anchor_kind = "button_press",
        input_truth_mode = true,
        action_event_rules = jamie_transient.action_event_rules,
    })
    assert(runtime_transient.ignored == true
            and runtime_transient.reason == "transient_input_precursor",
        "live validation must consume the same injected transient mapping")

    local timeline_runtime_transient = ActionMatcher.classify_runtime_transition({
        expected_step = { id = 628 },
        actual_action_id = 512,
        input_anchor_kind = "button_press",
        input_truth_mode = false,
        action_event_rules = jamie_transient.action_event_rules,
    })
    assert(timeline_runtime_transient.ignored == true
            and timeline_runtime_transient.reason == "transient_input_precursor",
        "configured transient mappings must also protect legacy timeline playback")

    local jamie_release_tail = new_character_rule_session("Jamie")
    jamie_release_tail.events = {
        {
            id = 652,
            frame = 100,
            expected_combo = 1,
            damage_at_step = 800,
            has_hit = true,
            has_contact = true,
            anchor = { kind = "button_press", pressed_buttons = 64 },
        },
        {
            id = 657,
            frame = 140,
            expected_combo = 0,
            damage_at_step = 800,
            has_hit = false,
            has_contact = false,
            anchor = { kind = "button_release", released_buttons = 64 },
        },
    }
    jamie_release_tail.current_damage = 800
    jamie_release_tail.max_combo = 1
    local jamie_release_result = compiler.finalize(jamie_release_tail, {
        motion_resolver = function(action_id)
            if action_id == 652 then return "j.HP", "strict_route" end
            if action_id == 657 then return "7+HK", "runtime_verified_override" end
            return nil, "action_id_missing"
        end,
    })
    assert(#jamie_release_result.steps == 1
            and jamie_release_result.steps[1].id == 652
            and jamie_release_result.trace.suppressed_events[1].id == 657
            and jamie_release_result.trace.suppressed_events[1].reason
                == "character_action_event_suppression",
        "Jamie release tails must be suppressed only by injected exception data")

    local late_tail = new_character_rule_session("Jamie")
    late_tail.events = transcriber.deep_copy(jamie_release_tail.events)
    late_tail.events[2].frame = 165
    late_tail.current_damage = 800
    late_tail.max_combo = 1
    local late_tail_result = compiler.finalize(late_tail, {
        motion_resolver = function(action_id)
            if action_id == 652 then return "j.HP", "strict_route" end
            if action_id == 657 then return "7+HK", "runtime_verified_override" end
            return nil, "action_id_missing"
        end,
    })
    assert(#late_tail_result.steps == 2,
        "a mapped release tail outside its JSON window must remain visible")

    local dash_jitter = compiler.new({ character = "Ryu", frame = 0 })
    dash_jitter.events = {
        {
            id = 17,
            frame = 100,
            anchor = { kind = "double_tap", direction = "6" },
        },
        {
            id = 17,
            frame = 101,
            anchor = { kind = "double_tap", direction = "6" },
        },
    }
    local dash_result = compiler.finalize(dash_jitter, {
        motion_resolver = function(action_id)
            if action_id == 17 then return "66", "strict_route" end
            return nil, "action_id_missing"
        end,
    })
    assert(#dash_result.steps == 1
            and dash_result.trace.suppressed_events[1].reason
                == "redundant_dash_transition",
        "a same-Action double-tap jitter must not create a second Dash step")

    local long_delay_candidate = {
        {
            id = 600,
            motion = "LP",
            expected_combo = 1,
            damage_at_step = 500,
            has_hit = true,
            has_contact = true,
            relative_raw_inputs = { 16, 0, 32, 0 },
            combo_stats = { damage = 1000, drive_used = 0, super_used = 0 },
        },
        {
            id = 601,
            motion = "MP",
            expected_combo = 2,
            damage_at_step = 1000,
            has_hit = true,
            has_contact = true,
            delay_from_prev = 700,
        },
    }
    local long_delay_compiled = {
        steps = transcriber.deep_copy(long_delay_candidate),
        stats = {
            damage = 1000,
            max_combo = 2,
            unresolved_anchors = 0,
            block_contacts = 0,
            drive_used = 0,
            super_used = 0,
        },
    }
    long_delay_compiled.steps[2].delay_from_prev = 711
    local long_delay_runtime = {
        raw_inputs = long_delay_candidate[1].relative_raw_inputs,
        input_source = "relative_raw_inputs",
        input_completed = true,
        timed_out = false,
        timing_tolerance = 2,
    }
    assert(transcriber.verify_candidate(
            long_delay_candidate,
            long_delay_compiled,
            long_delay_runtime
        ).ok == true,
        "a 700-frame delay must accept the documented 1.5 percent boundary")
    long_delay_compiled.steps[2].delay_from_prev = 712
    local outside_long_delay = transcriber.verify_candidate(
        long_delay_candidate,
        long_delay_compiled,
        long_delay_runtime
    )
    assert(outside_long_delay.ok == false
            and table.concat(outside_long_delay.reasons, ","):match(
                "raw_replay_action_timing_mismatch"
            ),
        "a 700-frame delay must reject drift beyond the 1.5 percent boundary")
end

test_data_driven_recent_regressions()
test_data_driven_recent_regressions = nil

print("combo action event compiler tests passed")
