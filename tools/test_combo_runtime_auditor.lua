package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local RuntimeAuditor = require("func/ComboTrials/RuntimeAuditor")

local function resolved_command_display(total_steps, suppressed_step_count, character, mode)
    total_steps = total_steps or 1
    suppressed_step_count = suppressed_step_count or 0
    character = character or "Ryu"
    mode = mode or "classic"
    return {
        ok = true,
        status = "resolved",
        map_available = true,
        map_status = "loaded",
        mode = mode,
        character = character,
        total_steps = total_steps,
        resolved_step_count = total_steps - suppressed_step_count,
        preserved_step_count = 0,
        suppressed_step_count = suppressed_step_count,
        unresolved_count = 0,
        unresolved = {},
    }
end

local selected = RuntimeAuditor.select_single_path({
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\A.json",
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\B.json",
}, "trainingcombotrials_data/customcombos/ryu/B.JSON")
assert(#selected == 1 and selected[1]:match("B%.json$"),
    "single audit must resolve the loaded combo without depending on slash or case")
assert(#RuntimeAuditor.select_single_path({ "A.json" }, "B.json") == 0,
    "single audit must not escape the current character's installed file list")

local candidate = {
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        damage_at_step = 300,
        delay_from_prev = 0,
        raw_inputs = { 16, 0 },
        combo_stats = {
            damage = 300,
            drive_used = 0,
            super_used = 0,
        },
    },
}

local compiled = {
    steps = {
        {
            id = 600,
            motion = "LP",
            expected_combo = 1,
            damage_at_step = 300,
            delay_from_prev = 0,
        },
    },
    stats = {
        damage = 300,
        max_combo = 1,
        block_contacts = 0,
        drive_used = 0,
        super_used = 0,
        unresolved_anchors = 0,
    },
}

local passed = RuntimeAuditor.evaluate(candidate, compiled, {
    raw_inputs = candidate[1].raw_inputs,
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
    character = "Ryu",
    command_display_validation = resolved_command_display(),
    trial_completion = {
        completed = true,
        current_step = 2,
        total_steps = 1,
    },
})
assert(passed.ok == true,
    "runtime audit must accept an installed combo that reproduces its Action truth")

local relative_candidate = {
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        damage_at_step = 300,
        delay_from_prev = 0,
        relative_raw_inputs = { 16, 0 },
        combo_stats = {
            damage = 300,
            drive_used = 0,
            super_used = 0,
        },
    },
}
local relative_passed = RuntimeAuditor.evaluate(relative_candidate, compiled, {
    raw_inputs = relative_candidate[1].relative_raw_inputs,
    input_source = "relative_raw_inputs",
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
    character = "Ryu",
    command_display_validation = resolved_command_display(),
})
assert(relative_passed.ok == true,
    "runtime audit must accept facing-relative input truth")

local timeline_candidate = {
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        damage_at_step = 300,
        delay_from_prev = 0,
        timeline = { "1f : LP", "1f : 5" },
        combo_stats = {
            damage = 300,
            drive_used = 0,
            super_used = 0,
        },
    },
}
local timeline_passed = RuntimeAuditor.evaluate(timeline_candidate, compiled, {
    replay_inputs = { 16, 0 },
    input_source = "timeline",
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
    character = "Ryu",
    command_display_validation = resolved_command_display(),
})
assert(timeline_passed.ok == true
    and timeline_passed.input_source == "timeline"
    and timeline_passed.action_comparison.strict == false,
    "runtime audit must validate timeline-only installed combos without conversion")

local timeline_trace_drift = RuntimeAuditor.evaluate(timeline_candidate, {
    steps = {
        {
            id = 601,
            motion = "MP",
            expected_combo = 0,
            damage_at_step = 300,
            delay_from_prev = 3,
        },
    },
    stats = compiled.stats,
}, {
    replay_inputs = { 16, 0 },
    input_source = "timeline",
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
    character = "Ryu",
    command_display_validation = resolved_command_display(),
})
assert(timeline_trace_drift.ok == true
    and #timeline_trace_drift.reasons == 0
    and timeline_trace_drift.action_comparison.strict == false
    and timeline_trace_drift.action_comparison.mismatch_count >= 2
    and table.concat(timeline_trace_drift.advisories, ",")
        :match("replay_action_id_mismatch"),
    "legacy timeline trace drift must remain diagnostic when player-visible validation passes")

local guarded_timeline_candidate = {
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        damage_at_step = 300,
        delay_from_prev = 0,
        timeline = { "1f : LP", "1f : 5" },
        dummy_guard_type = 2,
        combo_stats = {
            damage = 800,
            drive_used = 0,
            super_used = 0,
        },
    },
    {
        id = 17,
        motion = "66",
        expected_combo = 0,
        damage_at_step = 300,
        delay_from_prev = 40,
        has_hit = false,
    },
    {
        id = 603,
        motion = "MP",
        expected_combo = 2,
        damage_at_step = 800,
        delay_from_prev = 20,
        has_hit = true,
    },
}
local guarded_timeline_compiled = {
    steps = {
        {
            id = 600,
            motion = "LP",
            expected_combo = 1,
            damage_at_step = 300,
            delay_from_prev = 0,
            frame = 10,
            first_contact_frame = 12,
            has_contact = true,
            has_hit = true,
        },
        {
            id = 17,
            motion = "66",
            expected_combo = 0,
            damage_at_step = 300,
            delay_from_prev = 40,
            frame = 50,
            has_contact = false,
            has_hit = false,
        },
        {
            id = 603,
            motion = "MP",
            expected_combo = 0,
            damage_at_step = 300,
            delay_from_prev = 20,
            frame = 70,
            has_contact = true,
            has_hit = false,
            was_blocked = true,
            hit_result = "block",
        },
        {
            id = 648,
            motion = "6+HK",
            expected_combo = 0,
            damage_at_step = 300,
            delay_from_prev = 12,
            frame = 82,
            has_contact = false,
            has_hit = false,
        },
    },
    stats = {
        damage = 300,
        max_combo = 1,
        block_contacts = 1,
        drive_used = 0,
        super_used = 0,
        unresolved_anchors = 0,
    },
    trace = {
        combo_reset_frames = { 60 },
        projected_events = {
            {
                id = 600,
                frame = 10,
                first_contact_frame = 12,
                has_contact = true,
                has_hit = true,
            },
            {
                id = 17,
                frame = 50,
                has_contact = false,
                has_hit = false,
            },
            {
                id = 603,
                frame = 70,
                has_contact = true,
                has_hit = false,
                was_blocked = true,
                hit_result = "block",
            },
            {
                id = 648,
                frame = 82,
                has_contact = false,
                has_hit = false,
            },
        },
    },
}
local guarded_timeline_passed = RuntimeAuditor.evaluate(
    guarded_timeline_candidate,
    guarded_timeline_compiled,
    {
        replay_inputs = { 16, 0 },
        input_source = "timeline",
        input_completed = true,
        timing_tolerance = 2,
        trial_completed = true,
        character = "Ryu",
        command_display_validation = resolved_command_display(3),
    }
)
local guarded_advisories = table.concat(
    guarded_timeline_passed.advisories or {},
    ","
)
assert(guarded_timeline_passed.ok == true
    and guarded_advisories:match("timeline_guarded_followup_block")
    and guarded_advisories:match("timeline_guarded_followup_damage")
    and guarded_advisories:match("timeline_guarded_followup_combo"),
    "timeline audit must accept a proven post-reset guarded follow-up without weakening continuous routes")

local pre_reset_block_compiled = RuntimeAuditor.evaluate(
    guarded_timeline_candidate,
    {
        steps = guarded_timeline_compiled.steps,
        stats = guarded_timeline_compiled.stats,
        trace = {
            combo_reset_frames = { 80 },
            projected_events = guarded_timeline_compiled.trace.projected_events,
        },
    },
    {
        replay_inputs = { 16, 0 },
        input_source = "timeline",
        input_completed = true,
        timing_tolerance = 2,
        trial_completed = true,
        character = "Ryu",
        command_display_validation = resolved_command_display(3),
    }
)
assert(pre_reset_block_compiled.ok == false
    and table.concat(pre_reset_block_compiled.reasons, ",")
        :match("replay_unexpected_block_before_combo_completion"),
    "a block that occurs before the runtime reset must remain a strict failure")

local continuous_guard_break_failed = RuntimeAuditor.evaluate({
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        damage_at_step = 300,
        delay_from_prev = 0,
        timeline = { "1f : LP", "1f : 5" },
        dummy_guard_type = 2,
        combo_stats = { damage = 800, drive_used = 0, super_used = 0 },
        has_hit = true,
    },
    {
        id = 603,
        motion = "MP",
        expected_combo = 2,
        damage_at_step = 800,
        delay_from_prev = 50,
        has_hit = true,
    },
}, {
    steps = {
        {
            id = 600,
            motion = "LP",
            expected_combo = 1,
            damage_at_step = 300,
            delay_from_prev = 0,
            frame = 10,
            first_contact_frame = 12,
            has_contact = true,
            has_hit = true,
        },
        {
            id = 603,
            motion = "MP",
            expected_combo = 0,
            damage_at_step = 300,
            delay_from_prev = 50,
            frame = 60,
            first_contact_frame = 62,
            has_contact = true,
            has_hit = false,
            was_blocked = true,
            hit_result = "block",
        },
    },
    stats = {
        damage = 300,
        max_combo = 1,
        block_contacts = 1,
        drive_used = 0,
        super_used = 0,
        unresolved_anchors = 0,
        unresolved_motion_actions = 0,
    },
    trace = {
        combo_reset_frames = { 40 },
        projected_events = {
            {
                id = 600,
                frame = 10,
                first_contact_frame = 12,
                has_contact = true,
                has_hit = true,
            },
            {
                id = 603,
                frame = 60,
                first_contact_frame = 62,
                has_contact = true,
                has_hit = false,
                was_blocked = true,
                hit_result = "block",
            },
        },
    },
}, {
    replay_inputs = { 16, 0 },
    input_source = "timeline",
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
    character = "Ryu",
    command_display_validation = resolved_command_display(2),
})
assert(continuous_guard_break_failed.ok == false
    and table.concat(continuous_guard_break_failed.reasons, ",")
        :match("replay_unexpected_block_before_combo_completion"),
    "a continuous authored combo must not become a guarded-followup pass merely because guard-after-first-hit exposed its break")

local combo_count_drift_candidate = {
    {
        id = 600,
        motion = "LP",
        expected_combo = 2,
        damage_at_step = 300,
        delay_from_prev = 0,
        timeline = { "1f : LP", "1f : 5" },
        combo_stats = {
            damage = 300,
            drive_used = 0,
            super_used = 0,
        },
    },
}
local combo_count_drift_compiled = {
    steps = {
        {
            id = 600,
            motion = "LP",
            expected_combo = 4,
            damage_at_step = 300,
            delay_from_prev = 0,
            has_contact = true,
            has_hit = true,
        },
    },
    stats = {
        damage = 300,
        max_combo = 4,
        block_contacts = 0,
        drive_used = 0,
        super_used = 0,
        unresolved_anchors = 0,
    },
}
local combo_count_drift_passed = RuntimeAuditor.evaluate(
    combo_count_drift_candidate,
    combo_count_drift_compiled,
    {
        replay_inputs = { 16, 0 },
        input_source = "timeline",
        input_completed = true,
        timing_tolerance = 2,
        trial_completed = true,
        character = "Ryu",
        command_display_validation = resolved_command_display(),
    }
)
assert(combo_count_drift_passed.ok == true
    and table.concat(combo_count_drift_passed.advisories, ",")
        :match("timeline_combo_count_drift"),
    "timeline-only combo-count drift may be advisory when damage and contacts still match")

local raw_combo_count_drift_failed = RuntimeAuditor.evaluate(
    combo_count_drift_candidate,
    combo_count_drift_compiled,
    {
        raw_inputs = { 16, 0 },
        input_source = "raw_inputs",
        input_completed = true,
        timing_tolerance = 2,
        trial_completed = true,
        character = "Ryu",
        command_display_validation = resolved_command_display(),
    }
)
assert(raw_combo_count_drift_failed.ok == false
    and table.concat(raw_combo_count_drift_failed.reasons, ",")
        :match("replay_combo_count_mismatch"),
    "raw replay combo counts must remain strict")

local coupled_timeline_drift_candidate = {
    {
        id = 600,
        motion = "LP",
        expected_combo = 2,
        damage_at_step = 300,
        delay_from_prev = 0,
        timeline = { "1f : LP", "1f : 5" },
        has_hit = true,
        has_contact = true,
        combo_stats = { damage = 300, drive_used = 0, super_used = 0 },
    },
}
local coupled_timeline_drift_compiled = {
    steps = {
        {
            id = 600,
            motion = "LP",
            expected_combo = 4,
            damage_at_step = 500,
            delay_from_prev = 0,
            has_contact = true,
            has_hit = true,
        },
    },
    stats = {
        damage = 500,
        max_combo = 4,
        block_contacts = 0,
        drive_used = 0,
        super_used = 0,
        unresolved_anchors = 0,
        unresolved_motion_actions = 0,
        resolver_error_actions = 0,
    },
}
local coupled_timeline_drift_passed = RuntimeAuditor.evaluate(
    coupled_timeline_drift_candidate,
    coupled_timeline_drift_compiled,
    {
        replay_inputs = { 16, 0 },
        input_source = "timeline",
        input_completed = true,
        timing_tolerance = 2,
        trial_completed = true,
        character = "Ryu",
        command_display_validation = resolved_command_display(),
    }
)
local coupled_timeline_advisories = table.concat(
    coupled_timeline_drift_passed.advisories or {},
    ","
)
assert(coupled_timeline_drift_passed.ok == true
    and coupled_timeline_advisories:match("timeline_damage_combo_drift")
    and coupled_timeline_advisories:match("timeline_combo_count_drift"),
    "a completed legacy timeline may retain coupled damage and hit-count drift when exact Action and contact truth still match")

local coupled_raw_drift_failed = RuntimeAuditor.evaluate(
    coupled_timeline_drift_candidate,
    coupled_timeline_drift_compiled,
    {
        raw_inputs = { 16, 0 },
        input_source = "raw_inputs",
        input_completed = true,
        timing_tolerance = 2,
        trial_completed = true,
        character = "Ryu",
        command_display_validation = resolved_command_display(),
    }
)
assert(coupled_raw_drift_failed.ok == false
    and table.concat(coupled_raw_drift_failed.reasons, ",")
        :match("replay_damage_mismatch")
    and table.concat(coupled_raw_drift_failed.reasons, ",")
        :match("replay_combo_count_mismatch"),
    "coupled outcome drift must remain strict for raw recordings")

local timeline_drive_drift_candidate = {
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        damage_at_step = 300,
        delay_from_prev = 0,
        timeline = { "1f : LP", "1f : 5" },
        has_hit = true,
        has_contact = true,
        combo_stats = { damage = 300, drive_used = 10000, super_used = 0 },
    },
}
local timeline_drive_drift_compiled = {
    steps = {
        {
            id = 600,
            motion = "LP",
            expected_combo = 1,
            damage_at_step = 300,
            delay_from_prev = 0,
            has_contact = true,
            has_hit = true,
        },
    },
    stats = {
        damage = 300,
        max_combo = 1,
        block_contacts = 0,
        drive_used = 12000,
        super_used = 0,
        unresolved_anchors = 0,
        unresolved_motion_actions = 0,
        resolver_error_actions = 0,
    },
}
local timeline_drive_drift_passed = RuntimeAuditor.evaluate(
    timeline_drive_drift_candidate,
    timeline_drive_drift_compiled,
    {
        replay_inputs = { 16, 0 },
        input_source = "timeline",
        input_completed = true,
        timing_tolerance = 2,
        trial_completed = true,
        character = "Ryu",
        command_display_validation = resolved_command_display(),
    }
)
assert(timeline_drive_drift_passed.ok == true
    and table.concat(timeline_drive_drift_passed.advisories, ",")
        :match("timeline_drive_consumption_drift"),
    "legacy timeline drive accounting may be advisory when the exact route and outcome still match")

local raw_drive_drift_failed = RuntimeAuditor.evaluate(
    timeline_drive_drift_candidate,
    timeline_drive_drift_compiled,
    {
        raw_inputs = { 16, 0 },
        input_source = "raw_inputs",
        input_completed = true,
        timing_tolerance = 2,
        trial_completed = true,
        character = "Ryu",
        command_display_validation = resolved_command_display(),
    }
)
assert(raw_drive_drift_failed.ok == false
    and table.concat(raw_drive_drift_failed.reasons, ",")
        :match("replay_drive_consumption_mismatch"),
    "raw drive consumption must remain strict")

local timeline_damage_drift_passed = RuntimeAuditor.evaluate(
    timeline_candidate,
    {
        steps = compiled.steps,
        stats = {
            damage = 200,
            max_combo = 1,
            block_contacts = 0,
            drive_used = 0,
            super_used = 0,
            unresolved_anchors = 0,
        },
    },
    {
        replay_inputs = { 16, 0 },
        input_source = "timeline",
        input_completed = true,
        timing_tolerance = 2,
        trial_completed = true,
        character = "Ryu",
        command_display_validation = resolved_command_display(),
    }
)
assert(timeline_damage_drift_passed.ok == true
    and table.concat(timeline_damage_drift_passed.advisories, ",")
        :match("runtime_version_damage_drift"),
    "a completed timeline route with matching Action and contact truth may retain stale damage as an advisory")

local raw_damage_drift_passed = RuntimeAuditor.evaluate(candidate, {
    steps = compiled.steps,
    stats = {
        damage = 200,
        max_combo = 1,
        block_contacts = 0,
        drive_used = 0,
        super_used = 0,
        unresolved_anchors = 0,
    },
}, {
    raw_inputs = candidate[1].raw_inputs,
    input_source = "raw_inputs",
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
    character = "Ryu",
    command_display_validation = resolved_command_display(),
})
assert(raw_damage_drift_passed.ok == true
    and table.concat(raw_damage_drift_passed.advisories, ",")
        :match("runtime_version_damage_drift"),
    "a strict raw replay may pass compatibility audit when only version damage changed")

local raw_step_damage_drift_passed = RuntimeAuditor.evaluate(candidate, {
    steps = {
        {
            id = 600,
            motion = "LP",
            expected_combo = 1,
            damage_at_step = 200,
            delay_from_prev = 0,
        },
    },
    stats = {
        damage = 200,
        max_combo = 1,
        block_contacts = 0,
        drive_used = 0,
        super_used = 0,
        unresolved_anchors = 0,
    },
}, {
    raw_inputs = candidate[1].raw_inputs,
    input_source = "raw_inputs",
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
    character = "Ryu",
    command_display_validation = resolved_command_display(),
})
assert(raw_step_damage_drift_passed.ok == true
    and table.concat(raw_step_damage_drift_passed.advisories, ",")
        :match("replay_step_damage_mismatch"),
    "verified runtime damage drift must also make per-step damage changes advisory")

do
    local terminal_tail_candidate = {
        {
            id = 1233,
            motion = "236236+K",
            expected_combo = 0,
            damage_at_step = 2450,
            delay_from_prev = 0,
            has_hit = true,
            has_contact = true,
            dummy_guard_type = 3,
            scene_state = {
                recorded_by = 0,
                players = {
                    p1 = { status = { burnout = false } },
                    p2 = { status = { burnout = true } },
                },
            },
            raw_inputs = { 256, 0 },
            combo_stats = {
                damage = 2450,
                drive_used = 60000,
                super_used = 30000,
            },
        },
    }
    local function terminal_tail_compiled(first_sample_frame)
        return {
            steps = {
                {
                    id = 1233,
                    motion = "236236+K",
                    expected_combo = 0,
                    damage_at_step = 1800,
                    delay_from_prev = 0,
                    frame = 40,
                    first_contact_frame = 100,
                    has_hit = true,
                    has_contact = true,
                },
            },
            stats = {
                damage = 1800,
                observed_hp_loss = 2450,
                unconfirmed_hp_loss = 650,
                passive_damage_ticks = 3,
                passive_damage_total = 650,
                passive_damage_max_tick = 300,
                max_combo = 0,
                block_contacts = 0,
                drive_used = 60000,
                super_used = 30000,
                unresolved_anchors = 0,
            },
            trace = {
                last_activity_frame = 200,
                input_bound_events = {
                    {
                        id = 1233,
                        frame = 40,
                        first_contact_frame = 100,
                        damage_at_step = 1800,
                        has_hit = true,
                        has_contact = true,
                    },
                },
                passive_damage_samples = {
                    { frame = first_sample_frame, delta = 300 },
                    { frame = 120, delta = 300 },
                    { frame = 130, delta = 50 },
                },
            },
        }
    end
    local terminal_tail_runtime = {
        raw_inputs = terminal_tail_candidate[1].raw_inputs,
        input_source = "raw_inputs",
        input_completed = true,
        timing_tolerance = 2,
        trial_completed = true,
        character = "Ryu",
        environment_observed = { dummy_guard_type = 3 },
        command_display_validation = resolved_command_display(),
    }
    local terminal_tail_passed = RuntimeAuditor.evaluate(
        terminal_tail_candidate,
        terminal_tail_compiled(110),
        terminal_tail_runtime
    )
    assert(terminal_tail_passed.ok == true
            and table.concat(terminal_tail_passed.advisories, ","):find(
                "burnout_guard_chip_tail:action=1233:count=3:total=650",
                1,
                true
            ) ~= nil,
        "completed terminal multi-hit damage must remain attributed to its proven Action")

    terminal_tail_candidate[1].scene_state.players.p2.status.burnout = false
    local non_burnout_tail_failed = RuntimeAuditor.evaluate(
        terminal_tail_candidate,
        terminal_tail_compiled(110),
        terminal_tail_runtime
    )
    assert(non_burnout_tail_failed.ok == false
            and table.concat(non_burnout_tail_failed.reasons, ","):find(
                "replay_unattributed_damage_tick:max=300:unconfirmed=650",
                1,
                true
            ) ~= nil,
        "large terminal damage must remain strict without recorded defender burnout")
    terminal_tail_candidate[1].scene_state.players.p2.status.burnout = true

    local early_tail_failed = RuntimeAuditor.evaluate(
        terminal_tail_candidate,
        terminal_tail_compiled(99),
        terminal_tail_runtime
    )
    assert(early_tail_failed.ok == false
            and table.concat(early_tail_failed.reasons, ","):find(
                "replay_unattributed_damage_tick:max=300:unconfirmed=650",
                1,
                true
            ) ~= nil,
        "large damage before terminal contact must remain a strict audit failure")
end

local missing_terminal_contact_failed = RuntimeAuditor.evaluate({
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        damage_at_step = 300,
        delay_from_prev = 0,
        has_hit = true,
        has_contact = true,
        raw_inputs = { 16, 0 },
        combo_stats = { damage = 300, drive_used = 0, super_used = 0 },
    },
}, {
    steps = {
        {
            id = 600,
            motion = "LP",
            expected_combo = 1,
            damage_at_step = 200,
            delay_from_prev = 0,
            has_hit = false,
            has_contact = false,
        },
    },
    stats = {
        damage = 200,
        max_combo = 1,
        block_contacts = 0,
        drive_used = 0,
        super_used = 0,
        unresolved_anchors = 0,
    },
}, {
    raw_inputs = { 16, 0 },
    input_source = "raw_inputs",
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
    character = "Ryu",
    command_display_validation = resolved_command_display(),
})
assert(missing_terminal_contact_failed.ok == false
    and table.concat(missing_terminal_contact_failed.reasons, ",")
        :match("replay_terminal_expected_contact_missing"),
    "damage drift must remain strict when the recorded terminal contact disappeared")

compiled.steps[1].id = 601
local failed = RuntimeAuditor.evaluate(candidate, compiled, {
    raw_inputs = candidate[1].raw_inputs,
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
    character = "Ryu",
    command_display_validation = resolved_command_display(),
})
assert(failed.ok == false
    and table.concat(failed.reasons, ","):match("replay_action_id_mismatch"),
    "runtime audit must reject a different runtime Action ID")

compiled.steps[1].id = 600
local ui_incomplete = RuntimeAuditor.evaluate(candidate, compiled, {
    raw_inputs = candidate[1].raw_inputs,
    input_source = "timeline",
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = false,
    character = "Ryu",
    command_display_validation = resolved_command_display(),
    trial_completion = {
        completed = false,
        current_step = 1,
        total_steps = 1,
    },
})
assert(ui_incomplete.ok == false
    and ui_incomplete.reasons[#ui_incomplete.reasons]
        == "runtime_trial_not_completed",
    "timeline runtime audit must reject an exact replay when the training UI does not finish")

local strict_raw_ui_incomplete = RuntimeAuditor.evaluate(candidate, compiled, {
    raw_inputs = candidate[1].raw_inputs,
    input_source = "raw_inputs",
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = false,
    character = "Ryu",
    command_display_validation = resolved_command_display(),
    trial_completion = {
        completed = false,
        current_step = 1,
        total_steps = 1,
    },
})
assert(strict_raw_ui_incomplete.ok == true
        and strict_raw_ui_incomplete.trial_completion.effective_completed == true
        and strict_raw_ui_incomplete.trial_completion.completion_source
            == "strict_raw_replay",
    "strict raw Action and outcome truth must survive a training UI completion false negative")

local restored_timeline_candidate = {
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        damage_at_step = 300,
        delay_from_prev = 0,
        has_hit = true,
        has_contact = true,
        raw_inputs = { 16, 0 },
        combo_stats = {
            damage = 1000,
            drive_used = 10000,
            super_used = 20000,
        },
        _xt_meta = {
            transcription = {
                source_input = "timeline",
                raw_replay_verified = true,
                source_advisories = {
                    "source_damage_rebuilt:expected=800:observed=1000",
                    "source_segmented_combo_count_rebuilt:expected=5:observed=3",
                },
            },
        },
    },
    {
        id = 601,
        motion = "MP",
        expected_combo = 2,
        damage_at_step = 500,
        delay_from_prev = 10,
        has_hit = true,
        has_contact = true,
    },
    {
        id = 500,
        motion = "DRC",
        expected_combo = 0,
        damage_at_step = 500,
        delay_from_prev = 10,
        has_hit = false,
        has_contact = false,
    },
    {
        id = 602,
        motion = "HP",
        expected_combo = 1,
        damage_at_step = 700,
        delay_from_prev = 10,
        has_hit = true,
        has_contact = true,
    },
    {
        id = 603,
        motion = "236+P",
        expected_combo = 3,
        damage_at_step = 1000,
        delay_from_prev = 10,
        has_hit = true,
        has_contact = true,
    },
}
local restored_timeline_compiled = {
    steps = {
        {
            id = 600,
            motion = "LP",
            expected_combo = 1,
            damage_at_step = 300,
            delay_from_prev = 0,
            has_hit = true,
            has_contact = true,
        },
        {
            id = 601,
            motion = "MP",
            expected_combo = 2,
            damage_at_step = 500,
            delay_from_prev = 10,
            has_hit = true,
            has_contact = true,
        },
        {
            id = 500,
            motion = "DRC",
            expected_combo = 0,
            damage_at_step = 500,
            delay_from_prev = 10,
            has_hit = false,
            has_contact = false,
        },
        {
            id = 602,
            motion = "HP",
            expected_combo = 3,
            damage_at_step = 600,
            delay_from_prev = 10,
            has_hit = true,
            has_contact = true,
        },
        {
            id = 603,
            motion = "236+P",
            expected_combo = 5,
            damage_at_step = 800,
            delay_from_prev = 10,
            has_hit = true,
            has_contact = true,
        },
    },
    stats = {
        damage = 800,
        max_combo = 5,
        block_contacts = 0,
        drive_used = 10000,
        super_used = 20000,
        unresolved_anchors = 0,
        unresolved_motion_actions = 0,
        resolver_error_actions = 0,
    },
    trace = {
        projected_events = {
            { frame = 10, first_contact_frame = 11 },
            { frame = 20, first_contact_frame = 21 },
            { frame = 30 },
            { frame = 40, first_contact_frame = 41 },
            { frame = 50, first_contact_frame = 51 },
        },
        combo_reset_frames = { 90 },
    },
}
local restored_timeline_passed = RuntimeAuditor.evaluate(
    restored_timeline_candidate,
    restored_timeline_compiled,
    {
        raw_inputs = restored_timeline_candidate[1].raw_inputs,
        input_source = "raw_inputs",
        input_completed = true,
        timing_tolerance = 2,
        trial_completed = false,
        character = "Ryu",
        command_display_validation = resolved_command_display(5),
        trial_completion = {
            completed = false,
            current_step = 4,
            total_steps = 5,
        },
    }
)
local restored_advisories = table.concat(
    restored_timeline_passed.advisories or {},
    ","
)
assert(restored_timeline_passed.ok == true
        and restored_timeline_passed.trial_completion.effective_completed == true
        and restored_timeline_passed.trial_completion.completion_source
            == "strict_raw_replay"
        and restored_advisories:match("transcription_source_damage_restored")
        and restored_advisories:match("transcription_source_combo_restored")
        and restored_advisories:match("replay_step_combo_mismatch")
        and restored_advisories:match("replay_step_damage_mismatch"),
    "a complete raw replay may restore the exact pre-transcription outcome recorded in provenance")

local incomplete_restored_compiled = RuntimeAuditor.evaluate(
    restored_timeline_candidate,
    {
        steps = restored_timeline_compiled.steps,
        stats = {
            damage = 800,
            max_combo = 5,
            block_contacts = 0,
            drive_used = 10000,
            super_used = 0,
            unresolved_anchors = 0,
            unresolved_motion_actions = 0,
            resolver_error_actions = 0,
        },
        trace = restored_timeline_compiled.trace,
    },
    {
        raw_inputs = restored_timeline_candidate[1].raw_inputs,
        input_source = "raw_inputs",
        input_completed = true,
        timing_tolerance = 2,
        trial_completed = false,
        character = "Ryu",
        command_display_validation = resolved_command_display(5),
        trial_completion = {
            completed = false,
            current_step = 4,
            total_steps = 5,
        },
    }
)
assert(incomplete_restored_compiled.ok == false
        and table.concat(incomplete_restored_compiled.reasons, ",")
            :match("replay_super_consumption_mismatch")
        and table.concat(incomplete_restored_compiled.reasons, ",")
            :match("runtime_trial_not_completed"),
    "restored provenance must not hide a missing terminal resource cost")

local timed_out_strict_raw = RuntimeAuditor.evaluate(candidate, compiled, {
    raw_inputs = candidate[1].raw_inputs,
    input_source = "raw_inputs",
    input_completed = true,
    timed_out = true,
    timing_tolerance = 2,
    trial_completed = false,
    character = "Ryu",
    command_display_validation = resolved_command_display(),
    trial_completion = {
        completed = false,
        current_step = 1,
        total_steps = 1,
    },
})
assert(timed_out_strict_raw.ok == false
        and timed_out_strict_raw.reasons[#timed_out_strict_raw.reasons]
            == "runtime_trial_not_completed",
    "a timed-out raw replay must not infer completion from partial runtime truth")

local display_validation_missing = RuntimeAuditor.evaluate(candidate, compiled, {
    raw_inputs = candidate[1].raw_inputs,
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
    character = "Ryu",
})
assert(display_validation_missing.ok == false
    and display_validation_missing.reasons[#display_validation_missing.reasons]
        == "runtime_command_display_validation_missing"
    and display_validation_missing.command_display_validation.status == "missing",
    "runtime audit must fail closed when structured command-display validation is absent")

local display_validation_failed = RuntimeAuditor.evaluate(candidate, compiled, {
    raw_inputs = candidate[1].raw_inputs,
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
    character = "Ryu",
    command_display_validation = {
        ok = false,
        status = "validator_error",
        map_available = false,
        map_status = "validator_error",
        mode = "classic",
        character = "Ryu",
        total_steps = 1,
        resolved_step_count = 1,
        preserved_step_count = 0,
        suppressed_step_count = 0,
        unresolved_count = 0,
        unresolved = {},
    },
})
assert(display_validation_failed.ok == false
    and display_validation_failed.reasons[#display_validation_failed.reasons]
        == "runtime_command_display_validation_invalid:ok",
    "runtime audit must reject a display validator that did not complete successfully")

local unresolved_display = RuntimeAuditor.evaluate(candidate, compiled, {
    raw_inputs = candidate[1].raw_inputs,
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
    character = "Ryu",
    command_display_validation = {
        ok = false,
        status = "unresolved_action_commands",
        map_available = true,
        map_status = "loaded",
        mode = "classic",
        character = "Ryu",
        total_steps = 1,
        resolved_step_count = 0,
        preserved_step_count = 0,
        suppressed_step_count = 0,
        unresolved_count = 1,
        unresolved = {
            {
                step_index = 1,
                action_id = 600,
                status = "action_id_missing",
                derivation = "input_derived_contact",
            },
        },
    },
})
assert(unresolved_display.ok == false
    and unresolved_display.reasons[#unresolved_display.reasons]
        == "runtime_command_display_unresolved:count=1"
    and unresolved_display.command_display_validation.unresolved_count == 1
    and unresolved_display.command_display_validation.unresolved[1].action_id == 600
    and unresolved_display.command_display_validation.actual_unresolved_count == 1,
    "runtime audit must reject and retain every unresolved command-display entry")

local suppressed_display = RuntimeAuditor.validate_command_display_payload(
    resolved_command_display(3, 1)
)
assert(suppressed_display.ok == true,
    "suppressed renderer-only steps must count toward a complete display payload")
assert(RuntimeAuditor.validate_command_display_payload(
        resolved_command_display(1, 0, "AKI"),
        { expected_total_steps = 1, expected_character = "A.K.I." }
    ).ok == true
    and RuntimeAuditor.validate_command_display_payload(
        resolved_command_display(1, 0, "MBison"),
        { expected_total_steps = 1, expected_character = "M. Bison" }
    ).ok == true,
    "character context comparison must normalize punctuation and spacing")

local total_context_mismatch = RuntimeAuditor.evaluate(candidate, compiled, {
    raw_inputs = candidate[1].raw_inputs,
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
    character = "Ryu",
    command_display_validation = resolved_command_display(2),
})
assert(total_context_mismatch.ok == false
    and total_context_mismatch.reasons[#total_context_mismatch.reasons]
        == "runtime_command_display_validation_invalid:total_steps_context",
    "runtime audit must compare display totals with the sequence being audited")

local character_context_mismatch = RuntimeAuditor.evaluate(candidate, compiled, {
    raw_inputs = candidate[1].raw_inputs,
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
    character = "Ryu",
    command_display_validation = resolved_command_display(1, 0, "Ken"),
})
assert(character_context_mismatch.ok == false
    and character_context_mismatch.reasons[#character_context_mismatch.reasons]
        == "runtime_command_display_validation_invalid:character_context",
    "runtime audit must bind command validation to the current run character")

local character_context_missing = RuntimeAuditor.evaluate(candidate, compiled, {
    raw_inputs = candidate[1].raw_inputs,
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
    command_display_validation = resolved_command_display(),
})
assert(character_context_missing.ok == false
    and character_context_missing.reasons[#character_context_missing.reasons]
        == "runtime_command_display_validation_invalid:expected_character",
    "runtime audit must fail closed when its current character context is absent")

local malformed_display_cases = {
    {
        name = "partial ok payload",
        payload = { ok = true, unresolved = {} },
        reason = "runtime_command_display_validation_invalid:total_steps",
    },
    {
        name = "actual unresolved hidden by declared zero",
        payload = {
            ok = true,
            status = "resolved",
            map_available = true,
            total_steps = 1,
            resolved_step_count = 1,
            preserved_step_count = 0,
            suppressed_step_count = 0,
            unresolved_count = 0,
            unresolved = { { action_id = 999 } },
        },
        reason = "runtime_command_display_validation_invalid:unresolved_count_mismatch",
    },
    {
        name = "declared unresolved hidden by empty list",
        payload = {
            ok = true,
            status = "resolved",
            map_available = true,
            total_steps = 1,
            resolved_step_count = 1,
            preserved_step_count = 0,
            suppressed_step_count = 0,
            unresolved_count = 1,
            unresolved = {},
        },
        reason = "runtime_command_display_validation_invalid:unresolved_count_mismatch",
    },
    {
        name = "negative count",
        payload = {
            ok = true,
            status = "resolved",
            map_available = true,
            total_steps = 1,
            resolved_step_count = -1,
            preserved_step_count = 0,
            suppressed_step_count = 0,
            unresolved_count = 0,
            unresolved = {},
        },
        reason = "runtime_command_display_validation_invalid:resolved_step_count",
    },
    {
        name = "fractional count",
        payload = {
            ok = true,
            status = "resolved",
            map_available = true,
            total_steps = 1,
            resolved_step_count = 0.5,
            preserved_step_count = 0,
            suppressed_step_count = 0,
            unresolved_count = 0,
            unresolved = {},
        },
        reason = "runtime_command_display_validation_invalid:resolved_step_count",
    },
    {
        name = "empty sequence",
        payload = resolved_command_display(0),
        reason = "runtime_command_display_validation_invalid:total_steps_empty",
    },
    {
        name = "preserved unresolved fallback",
        payload = {
            ok = true,
            status = "resolved",
            map_available = true,
            total_steps = 1,
            resolved_step_count = 0,
            preserved_step_count = 1,
            suppressed_step_count = 0,
            unresolved_count = 0,
            unresolved = {},
        },
        reason = "runtime_command_display_validation_invalid:preserved_steps",
    },
    {
        name = "unaccounted step",
        payload = {
            ok = true,
            status = "resolved",
            map_available = true,
            total_steps = 2,
            resolved_step_count = 1,
            preserved_step_count = 0,
            suppressed_step_count = 0,
            unresolved_count = 0,
            unresolved = {},
        },
        reason = "runtime_command_display_validation_invalid:step_count_mismatch",
    },
    {
        name = "non-resolved status",
        payload = {
            ok = true,
            status = "unresolved_action_commands",
            map_available = true,
            total_steps = 1,
            resolved_step_count = 1,
            preserved_step_count = 0,
            suppressed_step_count = 0,
            unresolved_count = 0,
            unresolved = {},
        },
        reason = "runtime_command_display_validation_invalid:status",
    },
    {
        name = "map unavailable",
        payload = {
            ok = true,
            status = "resolved",
            map_available = false,
            total_steps = 1,
            resolved_step_count = 1,
            preserved_step_count = 0,
            suppressed_step_count = 0,
            unresolved_count = 0,
            unresolved = {},
        },
        reason = "runtime_command_display_validation_invalid:map_available",
    },
    {
        name = "map status not loaded",
        payload = resolved_command_display(),
        map_status = "map_unavailable",
        reason = "runtime_command_display_validation_invalid:map_status",
    },
    {
        name = "invalid display mode",
        payload = resolved_command_display(),
        mode = "hybrid",
        reason = "runtime_command_display_validation_invalid:mode",
    },
    {
        name = "missing map status",
        payload = resolved_command_display(),
        omit_map_status = true,
        reason = "runtime_command_display_validation_invalid:map_status",
    },
    {
        name = "missing display mode",
        payload = resolved_command_display(),
        omit_mode = true,
        reason = "runtime_command_display_validation_invalid:mode",
    },
    {
        name = "missing character",
        payload = resolved_command_display(),
        omit_character = true,
        reason = "runtime_command_display_validation_invalid:character",
    },
}
for _, case in ipairs(malformed_display_cases) do
    if case.omit_map_status then
        case.payload.map_status = nil
    else
        case.payload.map_status = case.map_status
            or case.payload.map_status or "loaded"
    end
    if case.omit_mode then
        case.payload.mode = nil
    else
        case.payload.mode = case.mode or case.payload.mode or "classic"
    end
    if case.omit_character then
        case.payload.character = nil
    else
        case.payload.character = case.payload.character or "Ryu"
    end
    local result = RuntimeAuditor.validate_command_display_payload(case.payload)
    assert(result.ok == false and result.reason == case.reason,
        case.name .. " must fail closed with a stable reason")
end

local persisted_null_display = resolved_command_display()
persisted_null_display.unresolved = nil
persisted_null_display.actual_unresolved_count = 0
local live_null_result = RuntimeAuditor.validate_command_display_payload(
    persisted_null_display,
    { expected_total_steps = 1, expected_character = "Ryu" }
)
assert(live_null_result.ok == false
    and live_null_result.reason
        == "runtime_command_display_validation_invalid:unresolved",
    "live display validation must still reject unresolved=nil")

local persisted_null_item = {
    source_file = "PersistedNull.json",
    status = "passed",
    validation_revision = RuntimeAuditor.VALIDATION_REVISION,
    command_display_validation = persisted_null_display,
    trial_completion = { total_steps = 1 },
}
local persisted_null_state, persisted_null_reason =
    RuntimeAuditor.classify_report_item(persisted_null_item, {
        character = "Ryu",
    })
assert(persisted_null_state == "passed"
    and persisted_null_reason == nil
    and persisted_null_item.command_display_validation.unresolved == nil,
    "report classification must recover a proven persisted empty unresolved table without mutation")

local persisted_null_fail_closed_cases = {
    {
        name = "missing actual unresolved count",
        mutate = function(payload) payload.actual_unresolved_count = nil end,
        reason = "runtime_command_display_validation_invalid:unresolved",
    },
    {
        name = "nonzero declared unresolved count",
        mutate = function(payload)
            payload.unresolved_count = 1
            payload.resolved_step_count = 0
        end,
        reason = "runtime_command_display_validation_invalid:unresolved",
    },
    {
        name = "nonzero actual unresolved count",
        mutate = function(payload) payload.actual_unresolved_count = 1 end,
        reason = "runtime_command_display_validation_invalid:unresolved",
    },
    {
        name = "unsuccessful persisted validation",
        mutate = function(payload) payload.ok = false end,
        reason = "runtime_command_display_validation_invalid:unresolved",
    },
    {
        name = "non-resolved persisted validation",
        mutate = function(payload) payload.status = "validator_error" end,
        reason = "runtime_command_display_validation_invalid:unresolved",
    },
    {
        name = "incomplete persisted validation",
        mutate = function(payload) payload.total_steps = nil end,
        reason = "runtime_command_display_validation_invalid:total_steps",
    },
}
for _, case in ipairs(persisted_null_fail_closed_cases) do
    local payload = resolved_command_display()
    payload.unresolved = nil
    payload.actual_unresolved_count = 0
    case.mutate(payload)
    local state, reason = RuntimeAuditor.classify_report_item({
        source_file = case.name .. ".json",
        status = "passed",
        validation_revision = RuntimeAuditor.VALIDATION_REVISION,
        command_display_validation = payload,
        trial_completion = { total_steps = 1 },
    }, { character = "Ryu" })
    assert(state == "stale" and reason == case.reason,
        case.name .. " must fail closed during persisted report classification")
end

local run = RuntimeAuditor.new_run("Ryu", { "A.json" }, "2026-07-30T00:00:00+08:00")
assert(run.mode == "runtime_audit",
    "runtime audit runs must remain distinguishable from transcription isolation")
run.active = false
run.index = 1
run.passed = 1
run.items = {
    {
        source_file = "A.json",
        source_name = "A.json",
        status = "passed",
        replay_verified = true,
        raw_replay_verified = true,
    },
}
local report = RuntimeAuditor.report(run)
assert(report.schema == RuntimeAuditor.REPORT_SCHEMA
    and report.verifier.input
        == "relative_raw_inputs_or_raw_inputs_or_timeline"
    and report.verifier.input_priority[1] == "relative_raw_inputs"
    and report.verifier.input_priority[3] == "timeline"
    and report.verifier.action_truth
        == "runtime_action_id_or_verified_command_owner"
    and report.verifier.replay_action_trace
        == "compiled.trace.observed_actions"
    and report.verifier.step_trace_policy.timeline
        == "advisory_with_training_ui_completion_required"
    and report.verifier.raw_outcome_policy.transcribed_timeline_restore
        == "advisory_only_when_provenance_original_outcome_exact_actions_contacts_resources_and_terminal_match"
    and report.verifier.compatible_validation_revisions[35]
        == "monotonic_timeline_outcome_relaxation"
    and report.verifier.compatible_validation_revisions[40]
        == "contextual_internal_phase_damage_and_input_projection"
    and report.verifier.compatible_validation_revisions[41]
        == "strict_training_ui_completion_requirement"
    and report.verifier.raw_action_trace
        == "compiled.trace.observed_actions"
    and report.verifier.command_display.source
        == "runtime.command_display_validation"
    and report.verifier.command_display.required == true
    and report.verifier.command_display.pass_condition
        == "strict_resolved_step_count_invariants"
    and report.verifier.completion_policy.timeline
        == "training_ui_required"
    and report.verifier.completion_policy.relative_raw_inputs
        == "training_ui_or_strict_replay",
    "runtime audit reports must disclose their truth source and validation policy")

local single_run = RuntimeAuditor.new_run(
    "Ryu",
    { "B.json" },
    "2026-07-30T00:00:00+08:00",
    { scope = "current", requested_path = "B.json" }
)
local single_report = RuntimeAuditor.report(single_run)
assert(single_report.audit_scope == "current"
    and single_report.requested_path == "B.json"
    and single_report.total == 1,
    "single audit reports must disclose their narrow scope")

local revision_29_report = {
    passed = 28,
    failed = 0,
    items = {
        {
            source_file = "OldA.json",
            status = "passed",
            validation_revision = 29,
        },
        {
            source_file = "OldB.json",
            status = "passed",
            validation_revision = 29,
        },
    },
}
local refreshed_old, refreshed_old_counts =
    RuntimeAuditor.recompute_loaded_report_state(revision_29_report)
assert(refreshed_old_counts.passed == 0
    and refreshed_old_counts.failed == 0
    and refreshed_old_counts.stale == 2
    and refreshed_old.passed == 0
    and refreshed_old.failed == 0
    and refreshed_old.stale == 2
    and refreshed_old.persisted_counts.passed == 28
    and revision_29_report.items[1].effective_audit_status == nil,
    "revision 29 reports must be recomputed as stale without mutating loaded JSON")

local revision_30_report = {
    passed = 1,
    failed = 0,
    items = {
        {
            source_file = "OldRev30.json",
            status = "passed",
            validation_revision = 30,
            command_display_validation = resolved_command_display(),
        },
    },
}
local refreshed_30, refreshed_30_counts =
    RuntimeAuditor.recompute_loaded_report_state(revision_30_report)
assert(RuntimeAuditor.VALIDATION_REVISION == 47
    and RuntimeAuditor.COMPATIBLE_VALIDATION_REVISIONS[46]
        == "timeline_transcription_source_outcome_restore"
    and refreshed_30_counts.stale == 1
    and refreshed_30.passed == 0,
    "revision 30 reports must be stale after the strict invariant revision")

local revision_35_report = {
    character = "Ryu",
    passed = 1,
    failed = 1,
    items = {
        {
            source_file = "Rev35Passed.json",
            status = "passed",
            validation_revision = 35,
            command_display_validation = resolved_command_display(),
            trial_completion = { total_steps = 1 },
        },
        {
            source_file = "Rev35Failed.json",
            status = "failed",
            validation_revision = 35,
            command_display_validation = resolved_command_display(),
            trial_completion = { total_steps = 1 },
        },
    },
}
local refreshed_35, refreshed_35_counts =
    RuntimeAuditor.recompute_loaded_report_state(revision_35_report)
local revision_35_retry_paths, revision_35_retry_counts =
    RuntimeAuditor.retry_source_paths(refreshed_35)
assert(refreshed_35_counts.passed == 1
    and refreshed_35_counts.failed == 1
    and refreshed_35_counts.stale == 0
    and #revision_35_retry_paths == 1
    and revision_35_retry_paths[1] == "Rev35Failed.json"
    and revision_35_retry_counts.failed == 1
    and revision_35_retry_counts.stale == 0,
    "revision 35 must retain its failed-only queue across compatible relaxations")

local revision_36_report = {
    character = "CViper",
    passed = 7,
    failed = 1,
    items = {
        {
            source_file = "Passed.json",
            status = "passed",
            validation_revision = 36,
            command_display_validation = resolved_command_display(1, 0, "CViper"),
            trial_completion = { total_steps = 1 },
        },
        {
            source_file = "Failed.json",
            status = "failed",
            validation_revision = 36,
            command_display_validation = resolved_command_display(1, 0, "CViper"),
            trial_completion = { total_steps = 1 },
        },
    },
}
local refreshed_36, refreshed_36_counts =
    RuntimeAuditor.recompute_loaded_report_state(revision_36_report)
local revision_36_retry_paths, revision_36_retry_counts =
    RuntimeAuditor.retry_source_paths(refreshed_36)
assert(refreshed_36_counts.passed == 1
        and refreshed_36_counts.failed == 1
        and refreshed_36_counts.stale == 0
        and #revision_36_retry_paths == 1
        and revision_36_retry_paths[1] == "Failed.json"
        and revision_36_retry_counts.failed == 1
        and revision_36_retry_counts.stale == 0,
    "revision 36 passes must remain valid while quick-successor failures retry")

local current_damaged_report = {
    character = "Ryu",
    passed = 3,
    failed = 1,
    items = {
        {
            source_file = "Good.json",
            status = "passed",
            validation_revision = RuntimeAuditor.VALIDATION_REVISION,
            command_display_validation = resolved_command_display(),
            trial_completion = { total_steps = 1 },
        },
        {
            source_file = "Damaged.json",
            status = "passed",
            validation_revision = RuntimeAuditor.VALIDATION_REVISION,
            command_display_validation = {
                ok = true,
                status = "resolved",
                map_available = true,
                map_status = "loaded",
                mode = "classic",
                character = "Ryu",
                total_steps = 2,
                resolved_step_count = 2,
                preserved_step_count = 0,
                suppressed_step_count = 0,
                unresolved_count = 0,
                unresolved = {},
            },
            trial_completion = { total_steps = 1 },
        },
        {
            source_file = "MissingValidation.json",
            status = "passed",
            validation_revision = RuntimeAuditor.VALIDATION_REVISION,
            trial_completion = { total_steps = 1 },
        },
        {
            source_file = "Failed.json",
            status = "failed",
            validation_revision = RuntimeAuditor.VALIDATION_REVISION,
            command_display_validation = resolved_command_display(),
            trial_completion = { total_steps = 1 },
        },
    },
}
local refreshed_current, refreshed_current_counts =
    RuntimeAuditor.recompute_loaded_report_state(current_damaged_report)
assert(refreshed_current_counts.passed == 1
    and refreshed_current_counts.failed == 1
    and refreshed_current_counts.stale == 2
    and refreshed_current.items[2].effective_audit_status == "stale"
    and refreshed_current.items[2].effective_audit_reason
        == "runtime_command_display_validation_invalid:total_steps_context"
    and refreshed_current.items[3].effective_audit_status == "stale"
    and refreshed_current.items[3].effective_audit_reason
        == "runtime_command_display_validation_missing",
    "a damaged current-revision pass must become stale, not a trusted pass")
local damaged_retry_paths, damaged_retry_counts =
    RuntimeAuditor.retry_source_paths(refreshed_current)
local damaged_failed_paths = RuntimeAuditor.failed_source_paths(refreshed_current)
assert(#damaged_retry_paths == 3
    and damaged_retry_counts.failed == 1
    and damaged_retry_counts.stale == 2
    and #damaged_failed_paths == 1
    and damaged_failed_paths[1] == "Failed.json",
    "stale passes must enter re-audit only and never transcription failure selection")

local wrong_character_report = {
    character = "Ryu",
    items = {
        {
            source_file = "WrongCharacter.json",
            status = "passed",
            validation_revision = RuntimeAuditor.VALIDATION_REVISION,
            command_display_validation = resolved_command_display(1, 0, "Ken"),
            trial_completion = { total_steps = 1 },
        },
    },
}
local refreshed_wrong_character, wrong_character_counts =
    RuntimeAuditor.recompute_loaded_report_state(wrong_character_report)
assert(wrong_character_counts.stale == 1
    and refreshed_wrong_character.items[1].effective_audit_reason
        == "runtime_command_display_validation_invalid:character_context",
    "loaded reports must bind persisted display validation to the report character")

local retry_paths, retry_counts = RuntimeAuditor.retry_source_paths({
    character = "Ryu",
    items = {
        {
            source_file = "A.json",
            status = "passed",
            validation_revision = RuntimeAuditor.VALIDATION_REVISION,
            command_display_validation = resolved_command_display(),
            trial_completion = { total_steps = 1 },
        },
        {
            source_file = "B.json",
            status = "passed",
            validation_revision = 42,
        },
        {
            source_file = "C.json",
            status = "failed",
            validation_revision = RuntimeAuditor.VALIDATION_REVISION,
            command_display_validation = resolved_command_display(),
            trial_completion = { total_steps = 1 },
        },
    },
})
assert(#retry_paths == 2
    and retry_paths[1] == "B.json"
    and retry_paths[2] == "C.json"
    and retry_counts.stale == 1
    and retry_counts.failed == 1,
    "retry selection must include stale passes without requeueing current passes")
local failed_paths = RuntimeAuditor.failed_source_paths({
    character = "Ryu",
    items = {
        {
            source_file = "A.json",
            status = "passed",
            validation_revision = 42,
        },
        {
            source_file = "B.json",
            status = "failed",
            validation_revision = RuntimeAuditor.VALIDATION_REVISION,
            command_display_validation = resolved_command_display(),
            trial_completion = { total_steps = 1 },
        },
        {
            source_file = "b.JSON",
            status = "failed",
            validation_revision = RuntimeAuditor.VALIDATION_REVISION,
            command_display_validation = resolved_command_display(),
            trial_completion = { total_steps = 1 },
        },
    },
})
assert(#failed_paths == 1 and failed_paths[1] == "B.json",
    "audit-to-transcription selection must exclude stale passes and deduplicate failures")

print("combo runtime auditor tests passed")
