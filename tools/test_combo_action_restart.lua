local detector = dofile("autorun/func/ComboTrials/ActionRestartDetector.lua")

assert(detector.normalize_input_direction_bits(4, true) == 4,
    "P1-side physical right must remain relative forward")
assert(detector.normalize_input_direction_bits(8, false) == 4,
    "P2-side physical left must normalize to the same relative forward bit")
assert(detector.normalize_input_direction_bits(8, true) == 8,
    "P1-side physical left must remain relative back")
assert(detector.normalize_input_direction_bits(4, false) == 8,
    "P2-side physical right must normalize to the same relative back bit")

local started, reason = detector.detect(17, 3, 17, 18)
assert(started == true and reason == "act_frame_rewind",
    "a repeated 66 must create a new action instance even when frame 0/1 was not sampled")

started, reason = detector.detect(18, 4.5, 18, 21)
assert(started == true and reason == "act_frame_rewind",
    "a repeated 44 must create a new action instance even when frame 0/1 was not sampled")

started, reason = detector.detect(17, 19, 17, 18)
assert(started == false and reason == "no_new_action",
    "a normally advancing dash must not be duplicated")

started, reason = detector.detect(900, 3, 900, 18)
assert(started == true and reason == "act_frame_rewind",
    "a same-ID ActionFrame rewind is a game-owned new Action instance")

started, reason = detector.detect(900, 19, 900, 18, nil, nil, 32)
assert(started == false and reason == "no_new_action",
    "an attack edge without ActionFrame rewind must not duplicate an Action")

local replay_dash_residue = detector.evaluate_replay_dash_retrigger_residue({
    replay_active = true,
    previous_id = 18,
    expected_id = 37,
    actual_id = 18,
    previous_action_instance = 93,
    candidate_action_instance = 94,
    input_anchor_kind = "double_tap",
    frames_since_previous = 7,
    expected_delay = 29,
    timing_tolerance = 2,
})
assert(replay_dash_residue.ignored == true
        and replay_dash_residue.reason == "replayed_previous_dash_retrigger_residue",
    "automatic replay should ignore an early fresh-instance dash residue before a different step")

local manual_dash_retrigger = detector.evaluate_replay_dash_retrigger_residue({
    replay_active = false,
    previous_id = 17,
    expected_id = 975,
    actual_id = 17,
    previous_action_instance = 188,
    candidate_action_instance = 189,
    input_anchor_kind = "double_tap",
    frames_since_previous = 11,
    expected_delay = 38,
})
assert(manual_dash_retrigger.ignored == false
        and manual_dash_retrigger.reason == "not_automatic_replay",
    "manual trial validation must keep treating an extra dash input as a real action")

local expected_dash_repeat = detector.evaluate_replay_dash_retrigger_residue({
    replay_active = true,
    previous_id = 17,
    expected_id = 17,
    actual_id = 17,
    previous_action_instance = 20,
    candidate_action_instance = 21,
    input_anchor_kind = "double_tap",
    frames_since_previous = 20,
    expected_delay = 30,
})
assert(expected_dash_repeat.ignored == false
        and expected_dash_repeat.reason == "sequence_expects_same_dash",
    "a recorded consecutive dash must still consume its own fresh Action instance")

local on_time_dash_retrigger = detector.evaluate_replay_dash_retrigger_residue({
    replay_active = true,
    previous_id = 17,
    expected_id = 975,
    actual_id = 17,
    previous_action_instance = 30,
    candidate_action_instance = 31,
    input_anchor_kind = "double_tap",
    frames_since_previous = 36,
    expected_delay = 38,
    timing_tolerance = 2,
})
assert(on_time_dash_retrigger.ignored == false
        and on_time_dash_retrigger.reason == "next_step_window_reached",
    "dash retriggers at the next step window must remain visible to strict validation")

started, reason = detector.detect(904, 61, 904, 60, nil, nil, 32 | 64, true)
assert(started == false and reason == "no_new_action",
    "expected input and contact context must not synthesize an advancing same-ID Action")

started, reason = detector.detect(902, 24, 902, 23, nil, nil, 128, false)
assert(started == false and reason == "no_new_action",
    "A.K.I. 214HP input during the same advancing Action 902 must not create another step")

started, reason = detector.detect(902, 61, 902, 60, nil, nil, 128, false)
assert(started == false and reason == "no_new_action",
    "a later hit or repeated HP input in the same 2-hit Action 902 must remain one action instance")

started, reason = detector.detect(902, 3, 902, 61, nil, nil, 128, false)
assert(started == true and reason == "act_frame_rewind",
    "a real second 214HP must record from its native ActionFrame restart")

local block_contact = detector.evaluate_block_contact(30, false)
assert(block_contact.active == true and block_contact.started == true,
    "damage_type 30 must create one recording contact when block starts")
block_contact = detector.evaluate_block_contact(30, true)
assert(block_contact.active == true and block_contact.started == false,
    "continued blockstun frames must not create duplicate contacts")
block_contact = detector.evaluate_block_contact(0, true)
assert(block_contact.active == false and block_contact.started == false,
    "leaving blockstun must re-arm the next block contact")

local hit_contact = detector.evaluate_recording_hit_contact({
    current_combo = 1,
    previous_combo = 1,
    current_hp = 8400,
    previous_hp = 9000,
    damage_type = 3,
    hit_stop = 4,
    previous_damage_type = 0,
    previous_hit_stop = 0,
})
assert(hit_contact.accepted == true and hit_contact.reason == "victim_hp_decreased_hit_signal",
    "a second normal hit must create a contact even when combo_cnt remains 1")

hit_contact = detector.evaluate_recording_hit_contact({
    current_combo = 4,
    previous_combo = 4,
    current_hp = 8993,
    previous_hp = 9000,
    damage_type = 0,
    hit_stop = 0
})
assert(hit_contact.accepted == false
        and hit_contact.reason == "hp_decreased_without_hit_signal",
    "A.K.I. poison damage must not confirm a repeated normal candidate")

hit_contact = detector.evaluate_recording_hit_contact({
    current_combo = 4,
    previous_combo = 4,
    current_hp = 8993,
    previous_hp = 9000,
    damage_type = 3,
    hit_stop = 4,
    previous_damage_type = 3,
    previous_hit_stop = 4,
})
assert(hit_contact.accepted == false
        and hit_contact.reason == "hp_decreased_without_new_hit_cycle",
    "A.K.I. poison damage must stay rejected even while a stale hit signal is visible")

for _, stale_delta in ipairs({ 10, 20 }) do
    hit_contact = detector.evaluate_recording_hit_contact({
        current_combo = 4,
        previous_combo = 4,
        current_hp = 9000 - stale_delta,
        previous_hp = 9000,
        damage_type = 3,
        hit_stop = 4,
        previous_damage_type = 3,
        previous_hit_stop = 4,
        contact_candidate = true,
    })
    assert(hit_contact.accepted == false
            and hit_contact.reason == "hp_decreased_without_new_hit_cycle",
        "a 10-20 HP persistent tick must not become contact while the hit signal is unchanged")
end

local contact_state = {}
local first_cycle = detector.observe_recording_contacts(contact_state, {
    frame = 1,
    current_combo = 1,
    previous_combo = 0,
    current_hp = 9000,
    previous_hp = 9500,
    damage_type = 3,
    hit_stop = 4,
})
assert(first_cycle.hit_contact.accepted == true,
    "combo growth must consume the first hit-signal cycle")
local same_cycle_poison = detector.observe_recording_contacts(contact_state, {
    frame = 2,
    current_combo = 1,
    previous_combo = 1,
    current_hp = 8980,
    previous_hp = 9000,
    damage_type = 3,
    hit_stop = 4,
})
local same_cycle_flush = detector.observe_recording_contacts(contact_state, {
    frame = 3,
    current_combo = 1,
    previous_combo = 1,
    current_hp = 8980,
    previous_hp = 8980,
    damage_type = 0,
    hit_stop = 0,
})
assert(same_cycle_poison.hit_contact.accepted == false
        and same_cycle_flush.passive_damage_samples[1].delta == 20,
    "a consumed signal cycle must not turn a later 20 HP tick into a second hit")
local second_cycle = detector.observe_recording_contacts(contact_state, {
    frame = 4,
    current_combo = 1,
    previous_combo = 1,
    current_hp = 8400,
    previous_hp = 8980,
    damage_type = 3,
    hit_stop = 4,
})
assert(second_cycle.hit_contact.accepted == true,
    "a fresh hit-stop cycle must confirm a real second hit when combo count stays at one")

local hp_first_state = {}
local hp_first = detector.observe_recording_contacts(hp_first_state, {
    frame = 1,
    current_combo = 1,
    previous_combo = 1,
    current_hp = 8400,
    previous_hp = 9000,
    damage_type = 0,
    hit_stop = 0,
    contact_candidate = true,
})
assert(hp_first.hit_contact.accepted == false
        and #hp_first.passive_damage_samples == 0,
    "an unattributed HP edge must wait one frame before becoming passive")
local hp_first_signal = detector.observe_recording_contacts(hp_first_state, {
    frame = 2,
    current_combo = 1,
    previous_combo = 1,
    current_hp = 8400,
    previous_hp = 8400,
    damage_type = 3,
    hit_stop = 4,
    contact_candidate = true,
})
assert(hp_first_signal.hit_contact.accepted == true
        and hp_first_signal.hit_damage_confirmed == true
        and #hp_first_signal.passive_damage_samples == 0,
    "a hit signal one frame after HP must recover the real same-combo contact")

for _, persistent_delta in ipairs({ 10, 20 }) do
    local current_small_state = {}
    local current_small = detector.observe_recording_contacts(
        current_small_state,
        {
            frame = 1,
            current_combo = 1,
            previous_combo = 1,
            current_hp = 9000 - persistent_delta,
            previous_hp = 9000,
            damage_type = 3,
            hit_stop = 4,
            contact_candidate = true,
        }
    )
    assert(current_small.hit_contact.accepted == false
            and current_small.hit_damage_confirmed == false
            and current_small.passive_damage_samples[1].delta
                == persistent_delta,
        "a fresh hit edge must not attribute a supported persistent-damage tick")

    local pending_small_state = {}
    detector.observe_recording_contacts(pending_small_state, {
        frame = 1,
        current_combo = 1,
        previous_combo = 1,
        current_hp = 9000 - persistent_delta,
        previous_hp = 9000,
        damage_type = 0,
        hit_stop = 0,
        contact_candidate = true,
    })
    local pending_small = detector.observe_recording_contacts(
        pending_small_state,
        {
            frame = 2,
            current_combo = 1,
            previous_combo = 1,
            current_hp = 9000 - persistent_delta,
            previous_hp = 9000 - persistent_delta,
            damage_type = 3,
            hit_stop = 4,
            contact_candidate = true,
        }
    )
    assert(pending_small.hit_contact.accepted == false
            and pending_small.hit_damage_confirmed == false
            and pending_small.passive_damage_samples[1].delta
                == persistent_delta,
        "a 10-20 HP early tick must not bind to a next-frame hit signal")
end

local signal_small_then_hit_state = {}
local signal_small_tick = detector.observe_recording_contacts(
    signal_small_then_hit_state,
    {
        frame = 1,
        current_combo = 1,
        previous_combo = 1,
        current_hp = 9993,
        previous_hp = 10000,
        damage_type = 3,
        hit_stop = 4,
        contact_candidate = true,
    }
)
local signal_then_real_hit = detector.observe_recording_contacts(
    signal_small_then_hit_state,
    {
        frame = 2,
        current_combo = 1,
        previous_combo = 1,
        current_hp = 9693,
        previous_hp = 9993,
        damage_type = 3,
        hit_stop = 4,
        contact_candidate = true,
    }
)
assert(signal_small_tick.hit_contact.accepted == false
        and signal_small_tick.passive_damage_samples[1].delta == 7
        and signal_then_real_hit.hit_contact.accepted == true
        and signal_then_real_hit.hit_damage_confirmed == true,
    "a small DOT on a fresh signal must not consume the next-frame real same-combo hit")

local signal_clear_then_hit_state = {}
detector.observe_recording_contacts(signal_clear_then_hit_state, {
    frame = 1,
    current_combo = 1,
    previous_combo = 1,
    current_hp = 10000,
    previous_hp = 10000,
    damage_type = 3,
    hit_stop = 4,
    contact_candidate = true,
})
local signal_clear_then_hit = detector.observe_recording_contacts(
    signal_clear_then_hit_state,
    {
        frame = 2,
        current_combo = 1,
        previous_combo = 1,
        current_hp = 9700,
        previous_hp = 10000,
        damage_type = 0,
        hit_stop = 0,
        contact_candidate = true,
    }
)
assert(signal_clear_then_hit.hit_contact.accepted == true
        and signal_clear_then_hit.hit_damage_confirmed == true,
    "a next-frame HP update must consume a pending hit cycle after its signal clears")

local poison_before_hit_state = {}
detector.observe_recording_contacts(poison_before_hit_state, {
    frame = 1,
    current_combo = 0,
    previous_combo = 0,
    current_hp = 9993,
    previous_hp = 10000,
    damage_type = 0,
    hit_stop = 0,
})
local poison_before_hit_signal = detector.observe_recording_contacts(
    poison_before_hit_state,
    {
        frame = 2,
        current_combo = 1,
        previous_combo = 0,
        current_hp = 9993,
        previous_hp = 9993,
        damage_type = 3,
        hit_stop = 4,
        contact_candidate = true,
    }
)
local poison_before_real_damage = detector.observe_recording_contacts(
    poison_before_hit_state,
    {
        frame = 3,
        current_combo = 1,
        previous_combo = 1,
        current_hp = 9693,
        previous_hp = 9993,
        damage_type = 3,
        hit_stop = 4,
        contact_candidate = false,
    }
)
assert(poison_before_hit_signal.hit_contact.accepted == true
        and poison_before_hit_signal.passive_damage_samples[1].delta == 7
        and poison_before_real_damage.hit_damage_confirmed == true
        and #poison_before_real_damage.passive_damage_samples == 0,
    "poison before a combo edge must stay passive while the next-frame real damage is confirmed")

for _, combo_growth in ipairs({ false, true }) do
    local hp_then_poison_state = {}
    detector.observe_recording_contacts(hp_then_poison_state, {
        frame = 1,
        current_combo = combo_growth and 0 or 1,
        previous_combo = combo_growth and 0 or 1,
        current_hp = 9700,
        previous_hp = 10000,
        damage_type = 0,
        hit_stop = 0,
        contact_candidate = true,
    })
    local hp_then_poison = detector.observe_recording_contacts(
        hp_then_poison_state,
        {
            frame = 2,
            current_combo = 1,
            previous_combo = combo_growth and 0 or 1,
            current_hp = 9693,
            previous_hp = 9700,
            damage_type = 3,
            hit_stop = 4,
            contact_candidate = true,
        }
    )
    assert(hp_then_poison.hit_contact.accepted == true
            and hp_then_poison.hit_damage_confirmed == true
            and hp_then_poison.passive_damage_samples[1].delta == 7,
        "a large HP-first hit must bind to the next signal while its concurrent poison tick stays passive")
end

local settling_hit_state = {}
detector.observe_recording_contacts(settling_hit_state, {
    frame = 1,
    current_combo = 1,
    previous_combo = 1,
    current_hp = 9000,
    previous_hp = 9000,
    damage_type = 0,
    hit_stop = 0,
})
local settling_hit = detector.observe_recording_contacts(settling_hit_state, {
    frame = 2,
    current_combo = 1,
    previous_combo = 1,
    current_hp = 8400,
    previous_hp = 9000,
    damage_type = 3,
    hit_stop = 1,
    contact_candidate = true,
})
assert(settling_hit.hit_contact.accepted == true,
    "the first edge of a same-combo hit must be accepted")
local settling_poison = detector.observe_recording_contacts(settling_hit_state, {
    frame = 3,
    current_combo = 1,
    previous_combo = 1,
    current_hp = 8380,
    previous_hp = 8400,
    damage_type = 3,
    hit_stop = 4,
    contact_candidate = true,
})
local settling_flush = detector.observe_recording_contacts(settling_hit_state, {
    frame = 4,
    current_combo = 1,
    previous_combo = 1,
    current_hp = 8380,
    previous_hp = 8380,
    damage_type = 3,
    hit_stop = 4,
    contact_candidate = true,
})
assert(settling_poison.hit_contact.accepted == false
        and settling_poison.hit_damage_confirmed == false
        and settling_flush.passive_damage_samples[1].delta == 20,
    "a hit-stop value settling upward must not reopen a consumed hit cycle")

local no_candidate_state = {}
detector.observe_recording_contacts(no_candidate_state, {
    frame = 1,
    current_combo = 1,
    previous_combo = 1,
    current_hp = 9000,
    previous_hp = 9000,
    damage_type = 0,
    hit_stop = 0,
})
local no_candidate_hit = detector.observe_recording_contacts(no_candidate_state, {
    frame = 2,
    current_combo = 1,
    previous_combo = 1,
    current_hp = 8400,
    previous_hp = 9000,
    damage_type = 3,
    hit_stop = 4,
    contact_candidate = false,
})
local next_event_poison = detector.observe_recording_contacts(no_candidate_state, {
    frame = 3,
    current_combo = 1,
    previous_combo = 1,
    current_hp = 8380,
    previous_hp = 8400,
    damage_type = 3,
    hit_stop = 4,
    contact_candidate = true,
})
local next_event_flush = detector.observe_recording_contacts(no_candidate_state, {
    frame = 4,
    current_combo = 1,
    previous_combo = 1,
    current_hp = 8380,
    previous_hp = 8380,
    damage_type = 3,
    hit_stop = 4,
    contact_candidate = true,
})
assert(no_candidate_hit.hit_contact.accepted == false
        and no_candidate_hit.hit_damage_confirmed == true
        and next_event_poison.hit_contact.accepted == false
        and next_event_flush.passive_damage_samples[1].delta == 20,
    "a fresh hit cycle must be consumed even when the current Action already owns contact")

local block_cycle_state = {}
local first_block_cycle = detector.observe_recording_contacts(block_cycle_state, {
    frame = 1,
    current_combo = 0,
    previous_combo = 0,
    current_hp = 9000,
    previous_hp = 9000,
    damage_type = 30,
    hit_stop = 4,
})
assert(first_block_cycle.block_contact.started == true
        and first_block_cycle.block_damage_confirmed == false,
    "a real block signal must create contact even before HP updates")
local delayed_chip = detector.observe_recording_contacts(block_cycle_state, {
    frame = 2,
    current_combo = 0,
    previous_combo = 0,
    current_hp = 8900,
    previous_hp = 9000,
    damage_type = 30,
    hit_stop = 4,
})
assert(delayed_chip.block_contact.started == false
        and delayed_chip.block_damage_confirmed == true,
    "the first HP update in a fresh block cycle must confirm chip once")
detector.observe_recording_contacts(block_cycle_state, {
    frame = 3,
    current_combo = 0,
    previous_combo = 0,
    current_hp = 8900,
    previous_hp = 8900,
    damage_type = 30,
    hit_stop = 0,
})
local second_block_cycle = detector.observe_recording_contacts(block_cycle_state, {
    frame = 4,
    current_combo = 0,
    previous_combo = 0,
    current_hp = 8800,
    previous_hp = 8900,
    damage_type = 30,
    hit_stop = 4,
})
assert(second_block_cycle.block_contact.started == true
        and second_block_cycle.block_damage_confirmed == true,
    "a renewed block hit-stop edge must create and consume a second block cycle")

local block_hp_first_state = {}
detector.observe_recording_contacts(block_hp_first_state, {
    frame = 1,
    current_combo = 0,
    previous_combo = 0,
    current_hp = 8900,
    previous_hp = 9000,
    damage_type = 0,
    hit_stop = 0,
})
local block_hp_first = detector.observe_recording_contacts(block_hp_first_state, {
    frame = 2,
    current_combo = 0,
    previous_combo = 0,
    current_hp = 8900,
    previous_hp = 8900,
    damage_type = 30,
    hit_stop = 4,
})
assert(block_hp_first.block_contact.started == true
        and block_hp_first.block_damage_confirmed == true
        and #block_hp_first.passive_damage_samples == 0,
    "a block signal one frame after HP must recover the block chip")

for _, persistent_delta in ipairs({ 10, 20 }) do
    local current_block_small_state = {}
    local current_block_small = detector.observe_recording_contacts(
        current_block_small_state,
        {
            frame = 1,
            current_combo = 0,
            previous_combo = 0,
            current_hp = 9000 - persistent_delta,
            previous_hp = 9000,
            damage_type = 30,
            hit_stop = 4,
        }
    )
    assert(current_block_small.block_contact.started == true
            and current_block_small.block_damage_confirmed == false
            and current_block_small.passive_damage_samples[1].delta
                == persistent_delta,
        "a fresh block edge must not attribute a supported persistent-damage tick as chip")

    local pending_block_small_state = {}
    detector.observe_recording_contacts(pending_block_small_state, {
        frame = 1,
        current_combo = 0,
        previous_combo = 0,
        current_hp = 9000 - persistent_delta,
        previous_hp = 9000,
        damage_type = 0,
        hit_stop = 0,
    })
    local pending_block_small = detector.observe_recording_contacts(
        pending_block_small_state,
        {
            frame = 2,
            current_combo = 0,
            previous_combo = 0,
            current_hp = 9000 - persistent_delta,
            previous_hp = 9000 - persistent_delta,
            damage_type = 30,
            hit_stop = 4,
        }
    )
    assert(pending_block_small.block_damage_confirmed == false
            and pending_block_small.passive_damage_samples[1].delta
                == persistent_delta,
        "a 10-20 HP early tick must not bind to a next-frame block signal")
end


local signal_small_then_block_state = {}
local signal_small_block_tick = detector.observe_recording_contacts(
    signal_small_then_block_state,
    {
        frame = 1,
        current_combo = 0,
        previous_combo = 0,
        current_hp = 9993,
        previous_hp = 10000,
        damage_type = 30,
        hit_stop = 4,
    }
)
local signal_then_real_chip = detector.observe_recording_contacts(
    signal_small_then_block_state,
    {
        frame = 2,
        current_combo = 0,
        previous_combo = 0,
        current_hp = 9893,
        previous_hp = 9993,
        damage_type = 30,
        hit_stop = 4,
    }
)
assert(signal_small_block_tick.block_contact.started == true
        and signal_small_block_tick.block_damage_confirmed == false
        and signal_small_block_tick.passive_damage_samples[1].delta == 7
        and signal_then_real_chip.block_damage_confirmed == true,
    "a small DOT on a fresh block signal must not consume next-frame real chip")

local signal_clear_then_block_state = {}
local signal_clear_block_start = detector.observe_recording_contacts(
    signal_clear_then_block_state,
    {
        frame = 1,
        current_combo = 0,
        previous_combo = 0,
        current_hp = 10000,
        previous_hp = 10000,
        damage_type = 30,
        hit_stop = 4,
    }
)
local signal_clear_then_block = detector.observe_recording_contacts(
    signal_clear_then_block_state,
    {
        frame = 2,
        current_combo = 0,
        previous_combo = 0,
        current_hp = 9900,
        previous_hp = 10000,
        damage_type = 0,
        hit_stop = 0,
    }
)
assert(signal_clear_block_start.block_contact.started == true
        and signal_clear_then_block.block_damage_confirmed == true,
    "a next-frame HP update must consume a pending block cycle after its signal clears")

local conflicting_fields_state = {}
local conflicting_fields = detector.observe_recording_contacts(
    conflicting_fields_state,
    {
        frame = 1,
        current_combo = 1,
        previous_combo = 0,
        current_hp = 9700,
        previous_hp = 10000,
        damage_type = 30,
        hit_stop = 4,
        contact_candidate = true,
    }
)
assert(conflicting_fields.hit_contact.accepted == true
        and conflicting_fields.block_contact.started == false
        and conflicting_fields.block_damage_confirmed == false,
    "combo growth must win over a stale block type so one sample cannot be hit and block")

local cross_frame_conflict_state = {}
detector.observe_recording_contacts(cross_frame_conflict_state, {
    frame = 1,
    current_combo = 1,
    previous_combo = 0,
    current_hp = 10000,
    previous_hp = 10000,
    damage_type = 3,
    hit_stop = 4,
    contact_candidate = true,
})
local cross_frame_conflict = detector.observe_recording_contacts(
    cross_frame_conflict_state,
    {
        frame = 2,
        current_combo = 1,
        previous_combo = 1,
        current_hp = 9700,
        previous_hp = 10000,
        damage_type = 30,
        hit_stop = 4,
        contact_candidate = false,
    }
)
assert(cross_frame_conflict.hit_damage_confirmed == true
        and cross_frame_conflict.block_contact.active == false
        and cross_frame_conflict.block_contact.started == false
        and cross_frame_conflict.block_damage_confirmed == false,
    "a pending combo-hit HP update must win over a next-frame stale block type")

local poison_before_block_state = {}
detector.observe_recording_contacts(poison_before_block_state, {
    frame = 1,
    current_combo = 0,
    previous_combo = 0,
    current_hp = 9993,
    previous_hp = 10000,
    damage_type = 0,
    hit_stop = 0,
})
local poison_before_block_signal = detector.observe_recording_contacts(
    poison_before_block_state,
    {
        frame = 2,
        current_combo = 0,
        previous_combo = 0,
        current_hp = 9993,
        previous_hp = 9993,
        damage_type = 30,
        hit_stop = 4,
    }
)
local poison_before_block_damage = detector.observe_recording_contacts(
    poison_before_block_state,
    {
        frame = 3,
        current_combo = 0,
        previous_combo = 0,
        current_hp = 9693,
        previous_hp = 9993,
        damage_type = 30,
        hit_stop = 4,
    }
)
assert(poison_before_block_signal.passive_damage_samples[1].delta == 7
        and poison_before_block_damage.block_damage_confirmed == true
        and #poison_before_block_damage.passive_damage_samples == 0,
    "poison before a block edge must stay passive while next-frame real chip is confirmed")

local block_hp_then_poison_state = {}
detector.observe_recording_contacts(block_hp_then_poison_state, {
    frame = 1,
    current_combo = 0,
    previous_combo = 0,
    current_hp = 9700,
    previous_hp = 10000,
    damage_type = 0,
    hit_stop = 0,
})
local block_hp_then_poison = detector.observe_recording_contacts(
    block_hp_then_poison_state,
    {
        frame = 2,
        current_combo = 0,
        previous_combo = 0,
        current_hp = 9693,
        previous_hp = 9700,
        damage_type = 30,
        hit_stop = 4,
    }
)
assert(block_hp_then_poison.block_damage_confirmed == true
        and block_hp_then_poison.passive_damage_samples[1].delta == 7,
    "a large HP-first block chip must bind while its concurrent poison tick stays passive")

local type_first_block_state = {}
local type_first_block = detector.observe_recording_contacts(type_first_block_state, {
    frame = 1,
    current_combo = 0,
    previous_combo = 0,
    current_hp = 9000,
    previous_hp = 9000,
    damage_type = 30,
    hit_stop = 0,
})
local type_first_hitstop = detector.observe_recording_contacts(type_first_block_state, {
    frame = 2,
    current_combo = 0,
    previous_combo = 0,
    current_hp = 9000,
    previous_hp = 9000,
    damage_type = 30,
    hit_stop = 4,
})
assert(type_first_block.block_contact.started == true
        and type_first_hitstop.block_contact.started == false,
    "type-first then hit-stop block fields must emit only one contact cycle")

local hitstop_first_block_state = {}
local hitstop_first = detector.observe_recording_contacts(hitstop_first_block_state, {
    frame = 1,
    current_combo = 0,
    previous_combo = 0,
    current_hp = 9000,
    previous_hp = 9000,
    damage_type = 0,
    hit_stop = 4,
})
local hitstop_then_type = detector.observe_recording_contacts(hitstop_first_block_state, {
    frame = 2,
    current_combo = 0,
    previous_combo = 0,
    current_hp = 9000,
    previous_hp = 9000,
    damage_type = 30,
    hit_stop = 4,
})
assert(hitstop_first.block_contact.started == false
        and hitstop_then_type.block_contact.started == true,
    "hit-stop-first then type block fields must emit one contact when type arrives")

hit_contact = detector.evaluate_recording_hit_contact({
    current_combo = 4,
    previous_combo = 4,
    current_hp = 8993,
    previous_hp = 9000,
    damage_type = 3,
    hit_stop = 0
})
assert(hit_contact.accepted == false
        and hit_contact.reason == "hp_decreased_without_hit_signal",
    "an HP decrease without victim hit stop must not become a recording contact")

hit_contact = detector.evaluate_recording_hit_contact({
    current_combo = 1,
    previous_combo = 1,
    current_hp = 9000,
    previous_hp = 9000
})
assert(hit_contact.accepted == false and hit_contact.reason == "no_new_hit_contact",
    "an unchanged HP value must not confirm a repeated move that never came out")

hit_contact = detector.evaluate_recording_hit_contact({
    current_combo = 1,
    previous_combo = 0,
    current_hp = 9000,
    previous_hp = 9000
})
assert(hit_contact.accepted == true and hit_contact.reason == "combo_increased",
    "the existing combo counter hit edge must remain valid")

hit_contact = detector.evaluate_recording_hit_contact({
    current_combo = 1,
    previous_combo = 1,
    current_hp = 10000,
    previous_hp = 9000
})
assert(hit_contact.accepted == false and hit_contact.reason == "no_new_hit_contact",
    "training-mode HP refill must not look like a hit")

hit_contact = detector.evaluate_recording_hit_contact({
    current_combo = 1,
    previous_combo = 1,
    current_hp = 8900,
    previous_hp = 9000,
    blocked = true
})
assert(hit_contact.accepted == false and hit_contact.reason == "blocked_hp_decrease",
    "chip damage on block must stay a single block contact")

started, reason = detector.detect(900, 19, 900, 18, nil, nil, 4)
assert(started == false and reason == "no_new_action",
    "a direction-only edge must not create a same-ID Action without rewind")

started, reason = detector.detect(900, 1, 900, 18)
assert(started == true and reason == "act_frame_rewind",
    "the existing near-zero same-ID restart behavior must remain intact")

started, reason = detector.detect(18, 20, 17, 20)
assert(started == true and reason == "id_changed",
    "an Action ID transition must remain a new action")

assert(detector.get_repeatable_motion(17) == "66", "Action 17 must stay data-mapped to 66")
assert(detector.get_repeatable_motion(18) == "44", "Action 18 must stay data-mapped to 44")
assert(detector.get_repeatable_motion(900) == nil, "character actions must not be hardcoded")

local function collect_pairs(directions)
    local state = {}
    local pairs = {}
    for index, direction in ipairs(directions) do
        local pair = detector.observe_dash_direction_edge(state, direction, index * 3)
        if pair then table.insert(pairs, pair) end
    end
    return pairs, state
end

local pairs = collect_pairs({ "6", "6", "6", "6" })
assert(#pairs == 2, "6666 must produce two non-overlapping 66 commands")

pairs = collect_pairs({ "6", "6", "6", "6", "6", "6" })
assert(#pairs == 3, "666666 must produce three non-overlapping 66 commands")
pairs = collect_pairs({ "6", "6", "6", "6", "6" })
assert(#pairs == 2, "an odd rapid 66666 stream must keep two full 66 commands and one pending tap")

pairs = collect_pairs({ "4", "4", "6", "6", "4", "4", "6", "6" })
assert(#pairs == 4, "44664466 must preserve all four commands")

local stale_state = {}
assert(detector.observe_dash_direction_edge(stale_state, "6", 1) == nil)
assert(detector.observe_dash_direction_edge(stale_state, "6", 20) == nil,
    "two stale taps must not create a dash command")

local function press_pair(state, direction, first_frame)
    assert(detector.observe_dash_direction_edge(state, direction, first_frame) == nil)
    return assert(detector.observe_dash_direction_edge(state, direction, first_frame + 2))
end

local p1_state = {}
press_pair(p1_state, "6", 10)
started, reason = detector.detect(17, 1, 1, 20, p1_state, 12)
assert(started == true and reason == "id_changed",
    "the first 66 must be recorded from the actual Action 17 transition")
press_pair(p1_state, "6", 16)
started, reason = detector.detect(17, 30, 17, 29, p1_state, 18)
assert(started == false and reason == "no_new_action",
    "a second double tap must not synthesize Action 17 while ActionFrame advances")

local p2_state = {}
press_pair(p2_state, "4", 30)
started, reason = detector.detect(17, 1, 1, 20, p2_state, 32)
assert(started == true and reason == "id_changed",
    "the opposite-side forward dash must use the actual Action 17 transition")
press_pair(p2_state, "4", 36)
started, reason = detector.detect(17, 40, 17, 39, p2_state, 38)
assert(started == false and reason == "no_new_action",
    "opposite-side input must not synthesize a repeated Action 17")

press_pair(p2_state, "6", 42)
started, reason = detector.detect(17, 45, 17, 44, p2_state, 44)
assert(started == false and reason == "no_new_action",
    "a direction pair without Action transition must remain input only")
started, reason = detector.detect(18, 1, 17, 45, p2_state, 45)
assert(started == true and reason == "id_changed",
    "the real Action 18 transition must remain visible")
press_pair(p2_state, "6", 48)
started, reason = detector.detect(18, 50, 18, 49, p2_state, 50)
assert(started == false and reason == "no_new_action",
    "a repeated back-dash input must wait for native ActionFrame rewind")

press_pair(p1_state, "4", 22)
started, reason = detector.detect(17, 45, 17, 44, p1_state, 24)
assert(started == false and reason == "no_new_action",
    "an opposite pair must wait for the real Action ID instead of duplicating the old dash")
started, reason = detector.detect(18, 1, 17, 45, p1_state, 25)
assert(started == true and reason == "id_changed",
    "the following Action 18 transition must create the back dash")
press_pair(p1_state, "4", 28)
started, reason = detector.detect(18, 50, 18, 49, p1_state, 30)
assert(started == false and reason == "no_new_action",
    "a direction pair alone must not repeat the back dash")

local queued_state = {}
press_pair(queued_state, "6", 60)
press_pair(queued_state, "6", 64)
started, reason = detector.detect(17, 1, 1, 20, queued_state, 66)
assert(started == true and reason == "id_changed",
    "ultra-fast input must still record the first actual Action 17 transition")
started, reason = detector.detect(17, 3, 17, 2, queued_state, 67)
assert(started == false and reason == "no_new_action",
    "queued double taps must not create a third 66 without native rewind")
started, reason = detector.detect(17, 0, 17, 3, queued_state, 68)
assert(started == true and reason == "act_frame_rewind",
    "the actual second 66 must be recorded when ActionFrame rewinds")

print("combo action restart tests passed")
