-- Pure helpers for batch-transcribing input-driven combo recordings.
-- Runtime playback, file I/O and UI scheduling are owned by the main script.

local Transcriber = {
    name = "ComboTrials.Transcriber",
    REPORT_SCHEMA = "sf6cc.combo_transcription_report.v1",
    VALIDATION_REVISION = 38,
    OUTPUT_ROOT = "TrainingComboTrials_data/TranscribedCandidates",
    REPORT_ROOT = "TrainingComboTrials_data/TranscriptionReports",
}

local PERSISTENT_DAMAGE_MIN_TICKS = 3
local MAX_DRIVE_GAUGE = 60000
local SUPER_GAUGE_PER_LEVEL = 10000
local MAX_SUPER_GAUGE = 30000
local ActionRestartDetector = require("func/ComboTrials/ActionRestartDetector")
-- Legacy outcome correction intentionally recognizes only the known small
-- poison-tick range. Larger unconfirmed losses remain telemetry but are not
-- strong enough to rewrite an authored combo count.
local PERSISTENT_DAMAGE_MAX_TICK =
    ActionRestartDetector.PERSISTENT_DAMAGE_MAX_TICK

local function report_time_key(path, report)
    local report_times = {
        type(report) == "table" and report.finished_at or nil,
        type(report) == "table" and report.started_at or nil,
    }
    for index = 1, 2 do
        local value = report_times[index]
        local year, month, day, hour, minute, second =
            tostring(value or ""):match(
                "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)"
            )
        if year then
            return year .. month .. day .. hour .. minute .. second
        end
    end

    local latest_stamp = nil
    for stamp in tostring(path or ""):gmatch("(%d%d%d%d%d%d%d%d_%d%d%d%d%d%d)") do
        latest_stamp = stamp
    end
    return latest_stamp and latest_stamp:gsub("_", "") or ""
end

-- Report variants use different filename infixes (single/failure_retry/etc.),
-- so lexical path order is not chronological. Select by persisted report time
-- and use the path only as a deterministic tie-breaker.
function Transcriber.select_latest_report(paths, loader, expected_schema, predicate)
    if type(paths) ~= "table" or type(loader) ~= "function" then return nil end
    local best_path, best_report, best_key = nil, nil, nil
    for _, path in ipairs(paths) do
        local ok, report = pcall(loader, path)
        if ok and type(report) == "table"
            and (expected_schema == nil or report.schema == expected_schema)
            and type(report.items) == "table"
            and (type(predicate) ~= "function" or predicate(report) == true) then
            local key = report_time_key(path, report)
            if best_report == nil or key > best_key
                or (key == best_key and tostring(path) > tostring(best_path)) then
                best_path = path
                best_report = report
                best_key = key
            end
        end
    end
    return best_path, best_report
end

local Validator = require("func/ComboTrials/Validator")
local SceneState = require("func/ComboTrials/SceneState")
local TrainingEnvironment = require("func/ComboTrials/TrainingEnvironment")
local RawInputCodec = require("func/ComboTrials/RawInputCodec")

local DERIVED_STEP_KEYS = {
    actual_combo = true,
    action_instance = true,
    counter_type = true,
    damage_at_step = true,
    delay_from_prev = true,
    display_only = true,
    dual_threshold = true,
    expected_combo = true,
    expected_hp = true,
    facing_left = true,
    group_id = true,
    has_contact = true,
    has_hit = true,
    hit_result = true,
    hold_frames = true,
    hold_partial_check = true,
    id = true,
    is_holdable = true,
    is_projectile_hit = true,
    motion = true,
    motion_aliases = true,
    validation_role = true,
    was_blocked = true,
}

local function deep_copy(value, seen)
    local value_type = type(value)
    if value_type ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local output = {}
    seen[value] = output
    for key, child in pairs(value) do
        output[deep_copy(key, seen)] = deep_copy(child, seen)
    end
    return output
end

local function first_step(sequence)
    return type(sequence) == "table" and type(sequence[1]) == "table"
        and sequence[1] or {}
end

local function expected_outcome(sequence)
    local first = first_step(sequence)
    local stats = type(first.combo_stats) == "table" and first.combo_stats or {}
    local expected_damage = tonumber(stats.damage) or 0
    local expected_combo = 0
    local expected_blocks = 0
    local max_step_damage = 0
    for _, step in ipairs(type(sequence) == "table" and sequence or {}) do
        expected_combo = math.max(expected_combo, tonumber(step.expected_combo) or 0)
        max_step_damage = math.max(max_step_damage, tonumber(step.damage_at_step) or 0)
        if step.hit_result == "block" or step.was_blocked == true then
            expected_blocks = expected_blocks + 1
        end
    end
    return {
        damage = math.max(expected_damage, max_step_damage),
        max_combo = expected_combo,
        block_contacts = expected_blocks,
        drive_used = tonumber(stats.drive_used) or 0,
        super_used = tonumber(stats.super_used) or 0,
    }
end

-- Early recorders sampled the Super gauge again after the combo had already
-- earned meter. Their derived `super_used` can therefore be a partial value
-- such as 6900 for an SA1 or 17000 for an SA2. Current runtime truth measures
-- initial minus minimum gauge and produces the real whole-level cost. This
-- helper deliberately recognizes only the next exact whole level; canonical
-- source values and larger jumps remain strict failures.
local function is_legacy_partial_super_usage(expected_value, observed_value)
    local expected = tonumber(expected_value)
    local observed = tonumber(observed_value)
    if expected == nil or observed == nil then return false end
    expected = math.floor(expected + 0.5)
    observed = math.floor(observed + 0.5)
    if expected <= 0 or expected >= MAX_SUPER_GAUGE
        or expected % SUPER_GAUGE_PER_LEVEL == 0 then
        return false
    end
    local whole_level_cost = math.ceil(expected / SUPER_GAUGE_PER_LEVEL)
        * SUPER_GAUGE_PER_LEVEL
    return observed == whole_level_cost
end

local function expected_hit_reconnect_reason(sequence)
    local max_combo_before = 0
    local reset_pending = false
    local damage_at_reset = 0
    local zero_combo_contact_damage = nil
    for _, step in ipairs(type(sequence) == "table" and sequence or {}) do
        if type(step) == "table" then
            local combo = math.max(0, tonumber(step.expected_combo) or 0)
            local damage = math.max(0, tonumber(step.damage_at_step) or 0)
            local expects_contact =
                step.has_hit == true or step.has_contact == true
            if combo == 0 and damage > 0 and expects_contact then
                zero_combo_contact_damage = math.max(
                    tonumber(zero_combo_contact_damage) or 0,
                    damage
                )
            elseif combo > 0 and zero_combo_contact_damage ~= nil
                and damage > zero_combo_contact_damage
                and expects_contact then
                return "expected_hit_after_zero_combo_contact"
            end
            if max_combo_before > 0 and combo == 0 then
                reset_pending = true
                damage_at_reset = math.max(damage_at_reset, damage)
            elseif combo > 0 then
                if reset_pending
                    and combo < max_combo_before
                    and damage > damage_at_reset
                    and expects_contact then
                    return "expected_hit_reconnect_after_combo_reset"
                end
                if combo >= max_combo_before then
                    reset_pending = false
                    damage_at_reset = 0
                end
                max_combo_before = math.max(max_combo_before, combo)
            end
        end
    end
    return nil
end

-- Poison damage made one legacy recorder carry the previous string's combo
-- count across a real reset. It could also attribute a multi-hit follow-up to
-- the preceding Action, so the source count may temporarily lead the runtime
-- count before both meet again. Correcting that source is safe only when each
-- runtime segment starts and ends on the authored cumulative count, no source
-- contact ever trails runtime truth, and all segment peaks reconstruct the
-- authored total exactly. Sample-level reset frames avoid mistaking non-contact
-- cancels (whose V2 expected_combo is zero) for a real combo break.
local function observed_segmented_combo_structure(
    sequence,
    compiled,
    source_action_match,
    expected_max_combo,
    observed_max_combo
)
    if source_action_match ~= true or type(sequence) ~= "table"
        or type(compiled) ~= "table" then
        return nil
    end
    local steps = type(compiled.steps) == "table" and compiled.steps or {}
    local trace = type(compiled.trace) == "table" and compiled.trace or {}
    local events = type(trace.projected_events) == "table"
        and trace.projected_events or {}
    local reset_frames = type(trace.combo_reset_frames) == "table"
        and trace.combo_reset_frames or {}
    if #sequence == 0 or #sequence ~= #steps or #events ~= #steps
        or #reset_frames == 0 then
        return nil
    end

    local completed_combo = 0
    local active_peak = 0
    local segment_peaks = {}
    local windows = {}
    local pending_reset_frame = nil
    local reset_index = 1
    local previous_contact_frame = nil
    local contact_count = 0
    local segment_first_contact = true
    local segment_last_source_combo = nil
    local attribution_lead_steps = 0
    local max_attribution_lead = 0
    local previous_source_row_combo = 0

    for index, event in ipairs(events) do
        local step = steps[index]
        local source = sequence[index]
        local combo = math.max(0, tonumber(step and step.expected_combo) or 0)
        local contact = type(step) == "table"
            and (step.has_hit == true or step.has_contact == true)
            and combo > 0
        local source_row_combo = tonumber(
            type(source) == "table" and source.expected_combo
        )
        -- A temporary lead is only an attribution shift when the runtime row
        -- still made contact. If the source count rises on an Action that the
        -- runtime proves did not connect, accepting a later catch-up could hide
        -- a genuinely missed authored hit.
        if not contact and source_row_combo ~= nil
            and source_row_combo > previous_source_row_combo then
            return nil
        end
        if source_row_combo ~= nil then
            previous_source_row_combo = source_row_combo
        end
        if contact then
            local contact_frame = tonumber(event.first_contact_frame)
                or tonumber(event.frame)
            if contact_frame == nil then return nil end
            while reset_index <= #reset_frames
                and (tonumber(reset_frames[reset_index]) or math.huge)
                    <= contact_frame do
                local reset_frame = tonumber(reset_frames[reset_index])
                if reset_frame ~= nil
                    and active_peak > 0
                    and (previous_contact_frame == nil
                        or reset_frame > previous_contact_frame) then
                    if segment_last_source_combo
                        ~= completed_combo + active_peak then
                        return nil
                    end
                    segment_peaks[#segment_peaks + 1] = active_peak
                    completed_combo = completed_combo + active_peak
                    active_peak = 0
                    pending_reset_frame = reset_frame
                    segment_first_contact = true
                    segment_last_source_combo = nil
                end
                reset_index = reset_index + 1
            end

            if active_peak > 0 and combo < active_peak then
                return nil
            end

            local source_combo = source_row_combo
            local reconstructed_combo = completed_combo + combo
            if source_combo == nil or source_combo < reconstructed_combo
                or (segment_first_contact
                    and source_combo ~= reconstructed_combo)
                or (segment_last_source_combo ~= nil
                    and source_combo < segment_last_source_combo) then
                return nil
            end
            local attribution_lead = source_combo - reconstructed_combo
            if attribution_lead > 0 then
                attribution_lead_steps = attribution_lead_steps + 1
                max_attribution_lead = math.max(
                    max_attribution_lead,
                    attribution_lead
                )
            end
            if pending_reset_frame ~= nil then
                windows[#windows + 1] = {
                    reset_frame = pending_reset_frame,
                    reconnect_frame = contact_frame,
                }
                pending_reset_frame = nil
            end
            active_peak = math.max(active_peak, combo)
            segment_first_contact = false
            segment_last_source_combo = source_combo
            previous_contact_frame = contact_frame
            contact_count = contact_count + 1
        end
    end

    if active_peak > 0 then
        if segment_last_source_combo ~= completed_combo + active_peak then
            return nil
        end
        segment_peaks[#segment_peaks + 1] = active_peak
        completed_combo = completed_combo + active_peak
    end
    if #segment_peaks < 2 or #windows ~= #segment_peaks - 1
        or contact_count < 2
        or completed_combo ~= math.max(0, tonumber(expected_max_combo) or 0) then
        return nil
    end
    local largest_segment = 0
    for _, peak in ipairs(segment_peaks) do
        largest_segment = math.max(largest_segment, peak)
    end
    if largest_segment ~= math.max(0, tonumber(observed_max_combo) or 0) then
        return nil
    end
    return {
        reason = "observed_hit_reconnect_after_combo_reset",
        segment_peaks = segment_peaks,
        reconstructed_combo = completed_combo,
        windows = windows,
        attribution_lead_steps = attribution_lead_steps,
        max_attribution_lead = max_attribution_lead,
    }
end

local function has_persistent_damage_evidence(stats, trace, structure)
    stats = type(stats) == "table" and stats or {}
    trace = type(trace) == "table" and trace or {}
    local ticks = math.max(0, tonumber(stats.passive_damage_ticks) or 0)
    local total = math.max(0, tonumber(stats.passive_damage_total) or 0)
    local max_tick = math.max(0, tonumber(stats.passive_damage_max_tick) or 0)
    if ticks < PERSISTENT_DAMAGE_MIN_TICKS or total <= 0 or max_tick <= 0
        or type(structure) ~= "table"
        or type(structure.windows) ~= "table"
        or #structure.windows == 0 then
        return false, {}
    end
    local samples = type(trace.passive_damage_samples) == "table"
        and trace.passive_damage_samples or {}
    local window_ticks = {}
    for window_index, window in ipairs(structure.windows) do
        local reset_frame = tonumber(window.reset_frame)
        local reconnect_frame = tonumber(window.reconnect_frame)
        if reset_frame == nil or reconnect_frame == nil
            or reconnect_frame < reset_frame then
            return false, window_ticks
        end
        local count = 0
        for _, sample in ipairs(samples) do
            local sample_frame = tonumber(type(sample) == "table" and sample.frame)
            local delta = tonumber(type(sample) == "table" and sample.delta)
            if sample_frame ~= nil and delta ~= nil
                and sample_frame >= reset_frame
                and sample_frame <= reconnect_frame then
                if delta <= 0 or delta > PERSISTENT_DAMAGE_MAX_TICK then
                    return false, window_ticks
                end
                count = count + 1
            end
        end
        window_ticks[window_index] = count
        if count < PERSISTENT_DAMAGE_MIN_TICKS then
            return false, window_ticks
        end
    end
    return true, window_ticks
end

local function set_prepared_environment_field(first, field_name, value)
    first[field_name] = value
    first._xt_meta = type(first._xt_meta) == "table" and first._xt_meta or {}
    first._xt_meta[field_name] = value
    first._xt_meta.environment =
        type(first._xt_meta.environment) == "table"
            and first._xt_meta.environment or {}
    first._xt_meta.environment[field_name] = value
end

local function stable_legacy_actor_hp(sequence)
    local stable = nil
    for _, step in ipairs(type(sequence) == "table" and sequence or {}) do
        local hp = tonumber(type(step) == "table" and step.expected_hp)
        if hp ~= nil then
            hp = math.max(0, math.floor(hp + 0.5))
            if stable ~= nil and hp ~= stable then return nil end
            stable = hp
        end
    end
    return stable
end

local function ensure_prepared_actor_state(first)
    first.scene_state = type(first.scene_state) == "table"
        and first.scene_state or {}
    local scene = first.scene_state
    scene.recorded_by = tonumber(first.recorded_by or scene.recorded_by) == 1
        and 1 or 0
    scene.players = type(scene.players) == "table" and scene.players or {}
    local actor_side = scene.recorded_by == 1 and "p2" or "p1"
    scene.players[actor_side] = type(scene.players[actor_side]) == "table"
        and scene.players[actor_side] or {}
    return scene, scene.players[actor_side]
end

local function prepare_stable_legacy_actor_hp(first, sequence, adjustments)
    local legacy_hp = stable_legacy_actor_hp(sequence)
    if legacy_hp == nil or legacy_hp <= 0 then return end

    -- V1 portable scenes often retained fighter/unique state but omitted the
    -- resource block entirely. In that format, expected_hp repeated on every
    -- Action is the only persisted truth for the attacking player's starting
    -- health. Materialize only that one resource on the in-memory transcription
    -- copy so a prior low-health training-menu setting cannot leak into the next
    -- file. Do not promote the partial scene to V2: the other V2 fields were not
    -- actually recorded.
    local _, actor_state = ensure_prepared_actor_state(first)
    actor_state.resources = type(actor_state.resources) == "table"
        and actor_state.resources or {}
    local actor_resources = actor_state.resources
    local scene_hp = tonumber(actor_resources and actor_resources.hp)
    if scene_hp == legacy_hp then return end

    -- Older V2 recorders stored the real attacking HP in expected_hp but wrote
    -- a generic 10000 into scene_state. Characters do not all have 10000 max
    -- HP, so a threshold-only repair misses exact CA boundaries such as E.
    -- Honda's 2625/10500. A value repeated on every Action is stable runtime
    -- evidence. During transcription only, repair the copied scene from it;
    -- the original JSON remains untouched.
    actor_resources.hp = legacy_hp
    if actor_resources.heal_hp ~= nil or scene_hp == nil then
        actor_resources.heal_hp = legacy_hp
    end
    adjustments[#adjustments + 1] = {
        field = "scene_state.actor.resources.hp",
        from = scene_hp,
        to = legacy_hp,
        reason = "stable_legacy_expected_hp",
    }
end

local function prepare_legacy_actor_gauges(first, adjustments)
    local scene = type(first.scene_state) == "table" and first.scene_state or nil
    -- A complete V2 recording owns its exact starting gauges, including an
    -- intentionally low value. Gauge synthesis is only a compatibility repair
    -- for older portable scenes that never recorded attacker Drive or Super.
    if type(scene) == "table" and scene.schema == SceneState.SCHEMA_V2 then return end

    local stats = type(first.combo_stats) == "table" and first.combo_stats or {}
    local drive_used = math.max(0, tonumber(stats.drive_used) or 0)
    local super_used = math.max(0, tonumber(stats.super_used) or 0)
    if drive_used <= 0 and super_used <= 0 then return end

    local _, actor_state = ensure_prepared_actor_state(first)
    actor_state.resources = type(actor_state.resources) == "table"
        and actor_state.resources or {}
    local resources = actor_state.resources

    -- Legacy combo_stats records how much meter the authored route consumed,
    -- not the exact starting amount. The recorder's historical default was a
    -- full gauge. Reconstruct that default instead of using the current menu's
    -- partly depleted gauge, which otherwise makes DRC/OD/SA Actions disappear
    -- depending on which combo ran immediately before this file.
    local status = type(actor_state.status) == "table" and actor_state.status or nil
    if drive_used > 0 and drive_used <= MAX_DRIVE_GAUGE
        and resources.drive == nil
        and not (status and status.burnout == true) then
        resources.drive = MAX_DRIVE_GAUGE
        adjustments[#adjustments + 1] = {
            field = "scene_state.actor.resources.drive",
            from = nil,
            to = MAX_DRIVE_GAUGE,
            reason = "legacy_combo_usage_requires_full_drive",
        }
        if status == nil then
            status = {}
            actor_state.status = status
        end
        if status.burnout == nil then
            status.burnout = false
            adjustments[#adjustments + 1] = {
                field = "scene_state.actor.status.burnout",
                from = nil,
                to = false,
                reason = "legacy_combo_usage_requires_active_drive",
            }
        end
    end

    if super_used > 0 and super_used <= MAX_SUPER_GAUGE
        and resources.super == nil then
        resources.super = MAX_SUPER_GAUGE
        adjustments[#adjustments + 1] = {
            field = "scene_state.actor.resources.super",
            from = nil,
            to = MAX_SUPER_GAUGE,
            reason = "legacy_combo_usage_requires_full_super",
        }
    end
end

local function prepare_legacy_counter_policy(first, sequence, adjustments)
    local counter_type, source =
        TrainingEnvironment.resolve_counter_policy(sequence, true)
    if source ~= "legacy_combo_stats" and source ~= "legacy_step" then return end

    set_prepared_environment_field(first, "dummy_counter_type", counter_type)
    adjustments[#adjustments + 1] = {
        field = "dummy_counter_type",
        from = nil,
        to = counter_type,
        reason = "legacy_counter_policy_canonicalized:" .. source,
    }
end

local LEGACY_UNIQUE_ACTION_REQUIREMENTS = {
    [20] = {
        resource_id = "stock_0_020",
        value = 1,
        -- [Shoulder Stance] Hundred Hand Slap Actions. These cannot occur
        -- without E. Honda's stored Sumo Spirit stock.
        required_action_ids = {
            [925] = true,
            [926] = true,
            [927] = true,
            [928] = true,
            [929] = true,
        },
        -- 22K establishes the stock during the replay, so a later enhanced
        -- Action does not prove that stock was required at frame zero.
        producer_action_ids = {
            [970] = true,
            [971] = true,
        },
    },
}

local function required_initial_unique_rule(first, sequence)
    local roles = SceneState.resolve_roles(first, 0)
    local actor_state = roles and roles.actor and roles.actor.state or nil
    local fighter_id = tonumber(type(actor_state) == "table" and actor_state.fighter_id)
    local rule = fighter_id and LEGACY_UNIQUE_ACTION_REQUIREMENTS[fighter_id] or nil
    if type(rule) ~= "table" then return nil, nil end

    local produced = false
    for _, step in ipairs(type(sequence) == "table" and sequence or {}) do
        local action_id = tonumber(type(step) == "table" and step.id)
        if action_id and rule.producer_action_ids[action_id] then produced = true end
        if action_id and rule.required_action_ids[action_id] and not produced then
            return rule, actor_state
        end
    end
    return nil, actor_state
end

local function prepare_legacy_unique_state(first, sequence, adjustments)
    local rule, actor_state = required_initial_unique_rule(first, sequence)
    if type(rule) ~= "table" or type(actor_state) ~= "table" then return end
    actor_state.unique = type(actor_state.unique) == "table"
        and actor_state.unique or {}
    local old_value = tonumber(actor_state.unique[rule.resource_id])
    if old_value ~= nil and old_value >= rule.value then return end

    actor_state.unique[rule.resource_id] = rule.value
    adjustments[#adjustments + 1] = {
        field = "scene_state.actor.unique." .. rule.resource_id,
        from = old_value,
        to = rule.value,
        reason = "source_action_requires_unique_resource",
    }
end

local function prepare_legacy_wall_stun_scene(first, adjustments)
    local piyo_frame = tonumber(first.piyo_frame)
    local scene = type(first.scene_state) == "table" and first.scene_state or nil
    local recorded_by = tonumber(first.recorded_by
        or (type(scene) == "table" and scene.recorded_by))
    local action_id = tonumber(first.id)
    local motion = tostring(first.motion or ""):upper():gsub("%s+", "")
    if first.has_piyo ~= true or piyo_frame == nil or piyo_frame <= 0
        or recorded_by ~= 0
        or (action_id ~= 854 and action_id ~= 855)
        or motion ~= "DI" then
        return
    end

    local snapshot = type(first.snapshot_gauges) == "table"
        and first.snapshot_gauges or nil
    local snapshot_proves_burnout = snapshot ~= nil
        and tonumber(snapshot.defender_drive) == 0
        and snapshot.defender_burnout == true
    local existing_scene = scene
    local existing_players = type(existing_scene) == "table"
        and type(existing_scene.players) == "table"
        and existing_scene.players or nil
    local existing_defender = existing_players
        and type(existing_players.p2) == "table" and existing_players.p2 or nil
    local existing_resources = type(existing_defender) == "table"
        and type(existing_defender.resources) == "table"
        and existing_defender.resources or nil
    local existing_status = type(existing_defender) == "table"
        and type(existing_defender.status) == "table"
        and existing_defender.status or nil
    local authoritative_v2_scene = type(existing_scene) == "table"
        and existing_scene.schema == SceneState.SCHEMA_V2
        and existing_status ~= nil
        and type(existing_status.stunned) == "boolean"
        and existing_status.stance ~= nil
    local pseudo_v2_defaults = type(existing_scene) == "table"
        and existing_scene.schema == SceneState.SCHEMA_V2
        and tonumber(existing_resources and existing_resources.drive) == 60000
        and existing_status and existing_status.burnout == false
        -- The real V2 recorder writes stunned and stance as well. A status
        -- containing only the default burnout=false is the old bulk-fill
        -- fingerprint, not an authoritative live capture.
        and existing_status.stunned == nil
        and existing_status.stance == nil
    local incomplete_legacy_scene = type(existing_scene) ~= "table"
        or (existing_scene.schema ~= SceneState.SCHEMA_V2
            and (tonumber(existing_resources and existing_resources.drive) == nil
                or type(existing_status and existing_status.burnout) ~= "boolean"))
    if authoritative_v2_scene
        or (not snapshot_proves_burnout
        and not pseudo_v2_defaults
        and not incomplete_legacy_scene) then
        return
    end

    scene = type(existing_scene) == "table" and existing_scene or {}
    first.scene_state = scene
    local old_schema = scene.schema
    if old_schema ~= SceneState.SCHEMA_V2 then
        scene.schema = SceneState.SCHEMA_V2
        adjustments[#adjustments + 1] = {
            field = "scene_state.schema",
            from = old_schema,
            to = SceneState.SCHEMA_V2,
            reason = "recorded_wall_stun_restored",
        }
    end
    scene.recorded_by = 0
    scene.players = type(scene.players) == "table" and scene.players or {}
    local defender = type(scene.players.p2) == "table" and scene.players.p2 or {}
    scene.players.p2 = defender
    defender.resources = type(defender.resources) == "table"
        and defender.resources or {}
    defender.status = type(defender.status) == "table" and defender.status or {}

    local old_drive = tonumber(defender.resources.drive)
    if old_drive ~= 0 then
        defender.resources.drive = 0
        adjustments[#adjustments + 1] = {
            field = "scene_state.defender.resources.drive",
            from = old_drive,
            to = 0,
            reason = "recorded_wall_stun_requires_burnout",
        }
    end
    local old_burnout = defender.status.burnout
    if old_burnout ~= true then
        defender.status.burnout = true
        adjustments[#adjustments + 1] = {
            field = "scene_state.defender.status.burnout",
            from = old_burnout,
            to = true,
            reason = "recorded_wall_stun_requires_burnout",
        }
    end

    -- A DI that produced wall stun necessarily connected on guard. Some old
    -- files mislabeled its chip-damage row as has_hit=true, so that derived bit
    -- cannot decide the menu setting. The bulk migration's generic "after first
    -- hit" default would let the opening DI hit instead; restore Guard All only
    -- for this already-proven legacy wall-stun scene.
    local guard_type, guard_source =
        TrainingEnvironment.resolve_dummy_guard_type(first, nil)
    local inferred_blocked_wall_stun = guard_source == "legacy_blocked_wall_stun"
    if guard_type == TrainingEnvironment.DUMMY_GUARD.AFTER_FIRST_HIT
        or inferred_blocked_wall_stun then
        set_prepared_environment_field(
            first,
            "dummy_guard_type",
            TrainingEnvironment.DUMMY_GUARD.ALL
        )
        adjustments[#adjustments + 1] = {
            field = "dummy_guard_type",
            from = inferred_blocked_wall_stun and nil or guard_type,
            to = TrainingEnvironment.DUMMY_GUARD.ALL,
            reason = "recorded_blocked_wall_stun_requires_guard_all",
        }
    end
end

-- A legacy OKI recording can explicitly expect a second damaging string
-- after its combo counter returned to zero while also carrying "guard after
-- first hit". Those facts cannot both happen under raw input: the defender
-- guards the entire second string. Prepare an in-memory transcription copy
-- with guard disabled, preserve the source file, and persist the derivation
-- in the generated candidate/report.
function Transcriber.prepare_capture_sequence(source_sequence)
    local prepared = deep_copy(source_sequence)
    local first = first_step(prepared)
    local adjustments = {}
    if next(first) == nil then return prepared, adjustments end

    prepare_stable_legacy_actor_hp(first, prepared, adjustments)
    prepare_legacy_actor_gauges(first, adjustments)
    prepare_legacy_counter_policy(first, prepared, adjustments)
    prepare_legacy_unique_state(first, prepared, adjustments)
    prepare_legacy_wall_stun_scene(first, adjustments)
    local expected = expected_outcome(prepared)
    local guard_type =
        TrainingEnvironment.resolve_dummy_guard_type(first, nil)
    local reconnect_reason = expected_hit_reconnect_reason(prepared)
    if expected.block_contacts == 0
        and guard_type == TrainingEnvironment.DUMMY_GUARD.AFTER_FIRST_HIT
        and reconnect_reason ~= nil then
        set_prepared_environment_field(
            first,
            "dummy_guard_type",
            TrainingEnvironment.DUMMY_GUARD.NONE
        )
        set_prepared_environment_field(first, "dummy_guard_switching", false)
        adjustments[#adjustments + 1] = {
            field = "dummy_guard_type",
            from = guard_type,
            to = TrainingEnvironment.DUMMY_GUARD.NONE,
            reason = reconnect_reason,
        }
    end
    return prepared, adjustments
end

local function has_reason_prefix(evaluation, prefix)
    for _, reason in ipairs(
        type(evaluation) == "table" and type(evaluation.reasons) == "table"
            and evaluation.reasons or {}
    ) do
        if tostring(reason):sub(1, #prefix) == prefix then return true end
    end
    return false
end

-- A continuous legacy route does not expose enough static information to
-- distinguish a deliberate pressure tail from an obsolete "guard after first
-- hit" setting. Runtime contact does: when the copied scene applied that guard
-- successfully and it blocks before the recorded combo can finish, retry the
-- same input once with guard disabled. The caller owns the one-retry limit.
function Transcriber.prepare_guard_retry(source_sequence, evaluation)
    local first = first_step(source_sequence)
    local expected = expected_outcome(source_sequence)
    local guard_type = TrainingEnvironment.resolve_dummy_guard_type(first, nil)
    if next(first) == nil
        or type(evaluation) ~= "table"
        or evaluation.ok == true
        or expected.block_contacts > 0
        or guard_type ~= TrainingEnvironment.DUMMY_GUARD.AFTER_FIRST_HIT
        or not has_reason_prefix(
            evaluation,
            "unexpected_block_before_combo_completion:"
        ) then
        return nil, {}
    end

    local prepared = deep_copy(source_sequence)
    local prepared_first = first_step(prepared)
    set_prepared_environment_field(
        prepared_first,
        "dummy_guard_type",
        TrainingEnvironment.DUMMY_GUARD.NONE
    )
    set_prepared_environment_field(prepared_first, "dummy_guard_switching", false)
    return prepared, {
        {
            field = "dummy_guard_type",
            from = guard_type,
            to = TrainingEnvironment.DUMMY_GUARD.NONE,
            reason = "runtime_blocked_before_expected_combo_completion",
        },
    }
end

local ENVIRONMENT_READBACK_FIELDS = {
    "dummy_action_type",
    "dummy_counter_type",
    "dummy_guard_type",
    "dummy_guard_count",
}

local function validate_training_environment(sequence, runtime, reasons)
    if runtime.verify_environment ~= true then return nil end

    local expected =
        TrainingEnvironment.resolve_recorded_settings(first_step(sequence))
    local observed = type(runtime.environment_observed) == "table"
        and runtime.environment_observed or {}
    local validation = {
        expected = {},
        observed = deep_copy(observed),
        mismatches = {},
        matches = true,
    }

    for _, field_name in ipairs(ENVIRONMENT_READBACK_FIELDS) do
        local expected_value = tonumber(expected[field_name])
        if expected_value ~= nil then
            local observed_value = tonumber(observed[field_name])
            validation.expected[field_name] = expected_value
            if observed_value == nil then
                validation.matches = false
                validation.mismatches[#validation.mismatches + 1] = {
                    field = field_name,
                    expected = expected_value,
                    actual = nil,
                }
                reasons[#reasons + 1] =
                    "training_environment_readback_missing:" .. field_name
            elseif observed_value ~= expected_value then
                validation.matches = false
                validation.mismatches[#validation.mismatches + 1] = {
                    field = field_name,
                    expected = expected_value,
                    actual = observed_value,
                }
                reasons[#reasons + 1] = string.format(
                    "training_environment_mismatch:%s:expected=%d:actual=%d",
                    field_name,
                    expected_value,
                    observed_value
                )
            end
        end
    end
    return validation
end

local function expects_terminal_contact(sequence)
    if type(sequence) ~= "table" or #sequence == 0 then return false end
    local terminal = sequence[#sequence]
    if type(terminal) ~= "table" then return false end
    if terminal.has_hit == true or terminal.has_contact == true
        or terminal.hit_result == "block" or terminal.was_blocked == true then
        return true
    end
    local previous = #sequence > 1 and sequence[#sequence - 1] or nil
    local terminal_damage = tonumber(terminal.damage_at_step)
    local previous_damage = tonumber(type(previous) == "table" and previous.damage_at_step)
    return terminal_damage ~= nil and previous_damage ~= nil
        and terminal_damage > previous_damage
end

-- A legacy row may explicitly say "not hit" while its cumulative combo and
-- damage were copied from a contact that completed on the preceding Action.
-- Treat that row as a pressure/setup tail only when runtime proves the entire
-- positive combo before it and the terminal Action adds neither combo nor
-- damage. This keeps the default false field from hiding a genuinely missed
-- terminal hit or a zero-combo damage action such as a throw.
local function observed_terminal_noncontact_proves_delayed_source_counters(
    sequence,
    compiled_steps
)
    if type(sequence) ~= "table" or type(compiled_steps) ~= "table"
        or #sequence < 2 or #sequence ~= #compiled_steps then
        return false
    end
    local source_terminal = sequence[#sequence]
    local observed_terminal = compiled_steps[#compiled_steps]
    local observed_previous = compiled_steps[#compiled_steps - 1]
    if type(source_terminal) ~= "table"
        or type(observed_terminal) ~= "table"
        or type(observed_previous) ~= "table" then
        return false
    end
    local source_explicit_noncontact =
        (source_terminal.has_hit == false
            or source_terminal.has_contact == false)
        and source_terminal.has_hit ~= true
        and source_terminal.has_contact ~= true
        and source_terminal.hit_result ~= "block"
        and source_terminal.was_blocked ~= true
    if not source_explicit_noncontact
        or observed_terminal.has_hit == true
        or observed_terminal.has_contact == true
        or observed_terminal.hit_result == "block"
        or observed_terminal.was_blocked == true
        or math.max(0, tonumber(observed_terminal.expected_combo) or 0) > 0 then
        return false
    end

    local previous_damage = tonumber(observed_previous.damage_at_step)
    local terminal_damage = tonumber(observed_terminal.damage_at_step)
    if previous_damage == nil or terminal_damage == nil
        or previous_damage <= 0 or terminal_damage ~= previous_damage then
        return false
    end

    local source_terminal_combo = tonumber(source_terminal.expected_combo)
    local source_prefix_max = 0
    for index = 1, #sequence - 1 do
        source_prefix_max = math.max(
            source_prefix_max,
            tonumber(type(sequence[index]) == "table"
                and sequence[index].expected_combo) or 0
        )
    end
    if source_terminal_combo == nil
        or source_terminal_combo < source_prefix_max then
        return false
    end

    local expected_max_combo = expected_outcome(sequence).max_combo
    if expected_max_combo <= 0
        or source_terminal_combo ~= expected_max_combo then
        return false
    end
    local observed_prefix_max = 0
    for index = 1, #compiled_steps - 1 do
        observed_prefix_max = math.max(
            observed_prefix_max,
            tonumber(type(compiled_steps[index]) == "table"
                and compiled_steps[index].expected_combo) or 0
        )
    end
    return observed_prefix_max >= expected_max_combo
end

local function terminal_contact_is_required(sequence, compiled_steps)
    if observed_terminal_noncontact_proves_delayed_source_counters(
        sequence,
        compiled_steps
    ) then
        return false
    end
    return expects_terminal_contact(sequence)
end

local function block_before_expected_combo_completion(steps, expected_combo)
    local max_combo_before = 0
    local saw_block = false
    for index, step in ipairs(type(steps) == "table" and steps or {}) do
        if type(step) == "table" then
            if step.hit_result == "block" or step.was_blocked == true then
                saw_block = true
                if max_combo_before < expected_combo then
                    return true, index, tonumber(step.id), max_combo_before
                end
            end
            max_combo_before = math.max(
                max_combo_before,
                tonumber(step.expected_combo) or 0
            )
        end
    end
    return false, nil, nil, max_combo_before, saw_block
end

local function append_unique(target, value)
    for _, existing in ipairs(target) do
        if existing == value then return end
    end
    target[#target + 1] = value
end

local function action_sequence_matches(sequence, compiled_steps, action_ids_equivalent)
    if type(sequence) ~= "table" or type(compiled_steps) ~= "table"
        or #sequence == 0 or #sequence ~= #compiled_steps then
        return false
    end
    for index = 1, #sequence do
        local expected_id = tonumber(sequence[index] and sequence[index].id)
        local observed_id = tonumber(compiled_steps[index] and compiled_steps[index].id)
        if expected_id == nil or observed_id == nil then return false end
        if expected_id ~= observed_id then
            local equivalent = false
            if type(action_ids_equivalent) == "function" then
                local ok, result = pcall(
                    action_ids_equivalent,
                    expected_id,
                    observed_id,
                    index
                )
                equivalent = ok and result == true
            end
            if not equivalent then return false end
        end
    end
    return true
end

local function has_environment_adjustment(runtime, reason)
    for _, adjustment in ipairs(
        type(runtime) == "table"
            and type(runtime.environment_adjustments) == "table"
            and runtime.environment_adjustments or {}
    ) do
        if type(adjustment) == "table" and adjustment.reason == reason then
            return true
        end
    end
    return false
end

-- One legacy recorder counted a wall-stun DI as an 800-damage first hit even
-- though the real game event was a 200-damage blocked contact and the combo
-- began on the next attack. Accept that one-time metadata correction only when
-- the entire runtime trace proves the same exact Action sequence and a constant
-- one-hit/one-damage-offset across every authored step. Generated candidates do
-- not receive environment_adjustments during verification, so the exception
-- cannot make a polluted candidate self-consistent.
local function legacy_blocked_wall_stun_shift(
    sequence,
    compiled,
    runtime,
    expected,
    source_terminal_contact_match
)
    if runtime.allow_legacy_outcome_rebuild ~= true
        or runtime.input_completed ~= true
        or runtime.timed_out == true
        or not has_environment_adjustment(
            runtime,
            "recorded_blocked_wall_stun_requires_guard_all"
        ) then
        return nil
    end

    local first = first_step(sequence)
    local steps = type(compiled) == "table" and compiled.steps or nil
    local stats = type(compiled) == "table" and compiled.stats or nil
    local scene = type(first.scene_state) == "table" and first.scene_state or nil
    local recorded_by = tonumber(first.recorded_by
        or (type(scene) == "table" and scene.recorded_by))
    local action_id = tonumber(first.id)
    local motion = tostring(first.motion or ""):upper():gsub("%s+", "")
    if first.has_piyo ~= true or (tonumber(first.piyo_frame) or 0) <= 0
        or recorded_by ~= 0
        or (action_id ~= 854 and action_id ~= 855)
        or motion ~= "DI"
        or not action_sequence_matches(sequence, steps, nil)
        or source_terminal_contact_match ~= true
        or type(stats) ~= "table" then
        return nil
    end

    local roles = SceneState.resolve_roles(first, 0)
    local defender_resources = roles and SceneState.resources(roles.defender) or nil
    local defender_status = roles and SceneState.status(roles.defender) or nil
    local guard_type = TrainingEnvironment.resolve_dummy_guard_type(first, nil)
    local observed_environment = type(runtime.environment_observed) == "table"
        and runtime.environment_observed or {}
    if tonumber(defender_resources and defender_resources.drive) ~= 0
        or not (type(defender_status) == "table"
            and defender_status.burnout == true)
        or guard_type ~= TrainingEnvironment.DUMMY_GUARD.ALL
        or tonumber(observed_environment.dummy_guard_type)
            ~= TrainingEnvironment.DUMMY_GUARD.ALL then
        return nil
    end

    for _, field_name in ipairs({
        "unresolved_anchors",
        "fallback_motion_actions",
        "unresolved_motion_actions",
        "resolver_error_actions",
        "unconfirmed_hp_loss",
        "passive_damage_ticks",
        "passive_damage_total",
    }) do
        if (tonumber(stats[field_name]) or 0) ~= 0 then return nil end
    end

    local observed_first = steps[1]
    local source_first_damage = tonumber(first.damage_at_step)
    local observed_first_damage = tonumber(
        type(observed_first) == "table" and observed_first.damage_at_step
    )
    if type(observed_first) ~= "table"
        or observed_first.has_contact ~= true
        or (tonumber(observed_first.expected_combo) or 0) ~= 0
        or source_first_damage == nil or observed_first_damage == nil
        or observed_first_damage <= 0
        or observed_first_damage >= source_first_damage then
        return nil
    end

    local damage_shift = nil
    for index = 1, #sequence do
        local source_step = sequence[index]
        local observed_step = steps[index]
        local source_combo = tonumber(source_step and source_step.expected_combo)
        local observed_combo = tonumber(observed_step and observed_step.expected_combo)
        local source_damage = tonumber(source_step and source_step.damage_at_step)
        local observed_damage = tonumber(observed_step and observed_step.damage_at_step)
        if source_combo == nil or observed_combo == nil
            or source_combo - observed_combo ~= 1
            or source_damage == nil or observed_damage == nil then
            return nil
        end
        local step_shift = source_damage - observed_damage
        if step_shift <= 0 then return nil end
        if damage_shift == nil then
            damage_shift = step_shift
        elseif damage_shift ~= step_shift then
            return nil
        end
    end

    local observed_damage = tonumber(stats.damage) or 0
    local observed_combo = tonumber(stats.max_combo) or 0
    local observed_blocks = tonumber(stats.block_contacts) or 0
    if observed_combo ~= expected.max_combo - 1
        or expected.damage - observed_damage ~= damage_shift
        or observed_blocks > 1 then
        return nil
    end
    return {
        damage_shift = damage_shift,
        expected_damage = expected.damage,
        observed_damage = observed_damage,
        expected_combo = expected.max_combo,
        observed_combo = observed_combo,
    }
end

local function action_ids_match(expected_id, observed_id, action_ids_equivalent, index)
    if expected_id == observed_id then return true end
    if type(action_ids_equivalent) ~= "function" then return false end
    local ok, result = pcall(
        action_ids_equivalent,
        expected_id,
        observed_id,
        index
    )
    return ok and result == true
end

-- Some early recorders omitted transient or newly mapped Actions while still
-- preserving every authored Action in order. This weaker relationship is not
-- enough for normal combo acceptance, but it proves that a segmented legacy
-- OKI route was executed in full before its derived counters are rebuilt.
local function action_sequence_is_subsequence(sequence, compiled_steps, action_ids_equivalent)
    if type(sequence) ~= "table" or type(compiled_steps) ~= "table"
        or #sequence == 0 or #compiled_steps == 0 then
        return false
    end

    local observed_index = 1
    for expected_index, expected in ipairs(sequence) do
        local expected_id = tonumber(type(expected) == "table" and expected.id)
        if expected_id == nil then return false end
        local matched = false
        while observed_index <= #compiled_steps do
            local observed_id = tonumber(
                type(compiled_steps[observed_index]) == "table"
                    and compiled_steps[observed_index].id
            )
            if observed_id ~= nil and action_ids_match(
                expected_id,
                observed_id,
                action_ids_equivalent,
                expected_index
            ) then
                matched = true
                observed_index = observed_index + 1
                break
            end
            observed_index = observed_index + 1
        end
        if not matched then return false end
    end
    return true
end

local function normalized_motion(value)
    local motion = tostring(value or ""):upper():gsub("%s+", "")
    return motion ~= "" and motion or nil
end

local function mirrored_motion(value)
    local motion = normalized_motion(value)
    if motion == nil then return nil end
    local mirror = {
        ["1"] = "3",
        ["3"] = "1",
        ["4"] = "6",
        ["6"] = "4",
        ["7"] = "9",
        ["9"] = "7",
    }
    return (motion:gsub("[134679]", mirror))
end

local function legacy_motion_matches(expected_motion, observed_motion)
    local expected = normalized_motion(expected_motion)
    local observed = normalized_motion(observed_motion)
    if expected == nil or observed == nil then return false end
    local mirrored = mirrored_motion(expected)
    -- Same notation with a different Action ID can mean a missing character
    -- resource or buff and must stay a failure. Only an actual left/right
    -- mirror proves the known side-switch representation drift.
    return mirrored ~= expected and mirrored == observed
end

local function is_legacy_derived_step(step)
    local motion = normalized_motion(type(step) == "table" and step.motion)
    return motion ~= nil and motion:sub(1, 1) == ">"
end

-- Old recorders sometimes emitted an internal follow-up as its own ">..."
-- row, while the current Action stream folds that follow-up into the owning
-- Action. They also stored directions before a side switch in the old facing.
-- For segmented legacy routes, compare only authored rows and allow a mirrored
-- motion to prove a changed Action ID. This remains weaker than normal Action
-- matching and is used only together with complete input and terminal contact.
local function legacy_authored_action_sequence_is_subsequence(
    sequence,
    compiled_steps,
    action_ids_equivalent
)
    if type(sequence) ~= "table" or type(compiled_steps) ~= "table"
        or #sequence == 0 or #compiled_steps == 0 then
        return false
    end

    local observed_index = 1
    local authored_count = 0
    for expected_index, expected in ipairs(sequence) do
        if not is_legacy_derived_step(expected) then
            authored_count = authored_count + 1
            local expected_id = tonumber(type(expected) == "table" and expected.id)
            if expected_id == nil then return false end
            local matched = false
            while observed_index <= #compiled_steps do
                local observed = compiled_steps[observed_index]
                local observed_id = tonumber(
                    type(observed) == "table" and observed.id
                )
                if observed_id ~= nil
                    and (action_ids_match(
                            expected_id,
                            observed_id,
                            action_ids_equivalent,
                            expected_index
                        )
                        or legacy_motion_matches(
                            expected.motion,
                            observed.motion
                        )) then
                    matched = true
                    observed_index = observed_index + 1
                    break
                end
                observed_index = observed_index + 1
            end
            if not matched then return false end
        end
    end
    return authored_count > 0
end

local function legacy_action_evidence(compiled, compiled_steps)
    local trace = type(compiled) == "table" and compiled.trace or nil
    local observed_actions = type(trace) == "table"
        and trace.observed_actions or nil
    if type(observed_actions) ~= "table" or #observed_actions == 0 then
        return compiled_steps
    end

    local evidence = deep_copy(observed_actions)
    -- The transition trace contains every real Action, including transient
    -- noncontact states that intentionally receive no command row. Enrich its
    -- input-bound Actions with the resolved motion so a post-side-switch ID can
    -- still be proven by mirrored notation.
    for _, observed in ipairs(evidence) do
        local observed_id = tonumber(type(observed) == "table" and observed.id)
        local observed_frame = tonumber(type(observed) == "table" and observed.frame)
        if observed_id ~= nil then
            local fallback = nil
            for _, step in ipairs(type(compiled_steps) == "table" and compiled_steps or {}) do
                if tonumber(type(step) == "table" and step.id) == observed_id then
                    fallback = fallback or step
                    if observed_frame ~= nil
                        and tonumber(step.frame) == observed_frame then
                        fallback = step
                        break
                    end
                end
            end
            if type(fallback) == "table" then
                observed.motion = fallback.motion
            end
        end
    end
    return evidence
end

local function terminal_action_contact_matches(sequence, compiled_steps, action_ids_equivalent)
    local sequence_length = type(sequence) == "table" and #sequence or 0
    local expected = sequence_length > 0 and sequence[sequence_length] or nil
    local observed = type(compiled_steps) == "table" and compiled_steps[#compiled_steps] or nil
    local expected_id = tonumber(type(expected) == "table" and expected.id)
    local observed_id = tonumber(type(observed) == "table" and observed.id)
    if expected_id == nil or observed_id == nil
        or not action_ids_match(
            expected_id,
            observed_id,
            action_ids_equivalent,
            sequence_length
        ) then
        return false
    end
    if not terminal_contact_is_required(sequence, compiled_steps) then return true end
    return observed.has_hit == true or observed.has_contact == true
        or observed.hit_result == "block" or observed.was_blocked == true
end

local function nonzero_resource(value)
    if type(value) == "boolean" then return value end
    if type(value) == "number" then return value ~= 0 end
    if type(value) ~= "table" then return false end
    for _, child in pairs(value) do
        if nonzero_resource(child) then return true end
    end
    return false
end

local function scene_roles(first)
    local scene = type(first.scene_state) == "table" and first.scene_state or nil
    local players = scene and type(scene.players) == "table" and scene.players or nil
    if not players then return nil, nil end
    local recorded_by = tonumber(first.recorded_by or scene.recorded_by) == 1 and 1 or 0
    return players[recorded_by == 1 and "p2" or "p1"],
        players[recorded_by == 1 and "p1" or "p2"]
end

function Transcriber.suspected_causes(sequence)
    local first = first_step(sequence)
    local causes = {}
    local meta = type(first._xt_meta) == "table" and first._xt_meta or {}
    local environment = type(meta.environment) == "table" and meta.environment or {}
    local snapshot = type(first.snapshot_gauges) == "table" and first.snapshot_gauges or {}
    local actor_scene, defender_scene = scene_roles(first)
    local actor_resources = actor_scene and actor_scene.resources or nil
    local actor_unique = actor_scene and actor_scene.unique or nil
    local defender_status = defender_scene and defender_scene.status or nil

    local counter = tonumber(environment.dummy_counter_type
        or meta.dummy_counter_type or first.dummy_counter_type)
    if counter == 2 then append_unique(causes, "first_hit_punish_counter") end

    local actor_snapshot = type(snapshot.attacker) == "table" and snapshot.attacker or {}
    local legacy_actor_hp = stable_legacy_actor_hp(sequence)
    local actor_hp = tonumber(type(actor_resources) == "table" and actor_resources.hp)
        or tonumber(actor_snapshot.current_hp)
    local actor_max_hp = tonumber(actor_snapshot.max_hp)
    if (actor_hp
            and ((actor_max_hp and actor_hp <= actor_max_hp * 0.25)
                or actor_hp <= 2500))
        or (legacy_actor_hp
            and ((actor_hp and actor_hp > 0
                    and legacy_actor_hp <= actor_hp * 0.25)
                or legacy_actor_hp <= 2500)) then
        append_unique(causes, "actor_low_health")
    end
    local required_unique_rule = required_initial_unique_rule(first, sequence)
    if nonzero_resource(actor_unique) or required_unique_rule ~= nil then
        append_unique(causes, "actor_character_resource_required")
    end

    if (type(defender_status) == "table" and defender_status.burnout == true)
        or (defender_status == nil and snapshot.defender_burnout == true) then
        append_unique(causes, "defender_burnout")
    end
    local victim_snapshot = type(snapshot.victim) == "table" and snapshot.victim or {}
    local victim_hp = tonumber(victim_snapshot.current_hp)
    local victim_heal = tonumber(victim_snapshot.heal_hp)
    local defender_resources = defender_scene and defender_scene.resources or nil
    local scene_victim_hp = tonumber(
        type(defender_resources) == "table" and defender_resources.hp
    )
    if victim_hp and victim_heal and victim_heal > victim_hp
        and (scene_victim_hp == nil or scene_victim_hp == victim_hp) then
        append_unique(causes, "defender_virtual_damage")
    end

    local guard_type = tonumber(first.dummy_guard_type
        or meta.dummy_guard_type or environment.dummy_guard_type)
    local guard_switching = first.dummy_guard_switching
    if guard_switching == nil then guard_switching = meta.dummy_guard_switching end
    if guard_switching == nil then guard_switching = environment.dummy_guard_switching end
    if (guard_type and guard_type ~= 0) or guard_switching == true then
        append_unique(causes, "defender_guard_state_change")
    end
    return causes
end

function Transcriber.evaluate(sequence, compiled, runtime)
    runtime = type(runtime) == "table" and runtime or {}
    compiled = type(compiled) == "table" and compiled or {}
    local stats = type(compiled.stats) == "table" and compiled.stats or {}
    local steps = type(compiled.steps) == "table" and compiled.steps or {}
    local expected = expected_outcome(sequence)
    local expected_actor_hp = stable_legacy_actor_hp(sequence)
    if expected_actor_hp ~= nil then expected.actor_hp = expected_actor_hp end
    local reasons = {}
    local advisories = {}
    -- Old V2 source rows may use an explicitly declared recording owner for a
    -- runtime follow-up Action. Keep that compatibility bridge separate from
    -- current candidate/raw-replay Action equivalence, which remains strict.
    local source_action_ids_equivalent =
        runtime.source_action_ids_equivalent
            or runtime.action_ids_equivalent
    local source_action_match = action_sequence_matches(
        sequence,
        steps,
        source_action_ids_equivalent
    )
    local source_action_subsequence_match = action_sequence_is_subsequence(
        sequence,
        steps,
        source_action_ids_equivalent
    )
    local legacy_evidence_steps = legacy_action_evidence(compiled, steps)
    local legacy_authored_action_subsequence_match =
        legacy_authored_action_sequence_is_subsequence(
            sequence,
            legacy_evidence_steps,
            source_action_ids_equivalent
        )
    local expected_reconnect_reason = expected_hit_reconnect_reason(sequence)
    local source_terminal_contact_match = terminal_action_contact_matches(
        sequence,
        steps,
        source_action_ids_equivalent
    )
    local blocked_wall_stun_shift = legacy_blocked_wall_stun_shift(
        sequence,
        compiled,
        runtime,
        expected,
        source_terminal_contact_match
    )
    local observed_combo_rebuild = observed_segmented_combo_structure(
        sequence,
        compiled,
        source_action_match,
        expected.max_combo,
        stats.max_combo
    )
    local observed_reconnect_reason = observed_combo_rebuild
        and observed_combo_rebuild.reason or nil
    local persistent_damage_evidence, persistent_damage_window_ticks =
        has_persistent_damage_evidence(
            stats,
            compiled.trace,
            observed_combo_rebuild
        )
    local legacy_segmented_outcome = runtime.allow_legacy_outcome_rebuild == true
        and (expected_reconnect_reason ~= nil
            or (observed_combo_rebuild ~= nil
                and persistent_damage_evidence))
        and legacy_authored_action_subsequence_match
        and runtime.input_completed == true
        and runtime.timed_out ~= true
        and source_terminal_contact_match

    if runtime.input_source ~= "raw_inputs"
        and runtime.input_source ~= RawInputCodec.RELATIVE_FIELD
        and runtime.input_source ~= "timeline" then
        reasons[#reasons + 1] = "missing_input_stream"
    end
    if type(runtime.raw_inputs) ~= "table" or #runtime.raw_inputs == 0 then
        reasons[#reasons + 1] = "transcribed_raw_inputs_missing"
    end
    if runtime.input_completed ~= true then reasons[#reasons + 1] = "input_not_completed" end
    if runtime.timed_out == true then reasons[#reasons + 1] = "replay_tail_timeout" end
    if #steps == 0 then reasons[#reasons + 1] = "no_action_steps" end
    local observed_actor_hp = tonumber(stats.actor_hp)
    if expected_actor_hp ~= nil and observed_actor_hp ~= nil
        and math.abs(observed_actor_hp - expected_actor_hp) > 1 then
        reasons[#reasons + 1] = string.format(
            "actor_hp_mismatch:expected=%d:observed=%d",
            expected_actor_hp,
            observed_actor_hp
        )
    end
    local observed_terminal = steps[#steps]
    if source_action_match and terminal_contact_is_required(sequence, steps)
        and type(observed_terminal) == "table"
        and observed_terminal.has_hit ~= true
        and observed_terminal.has_contact ~= true then
        reasons[#reasons + 1] = "terminal_expected_contact_missing"
    end
    local observed_blocks = tonumber(stats.block_contacts) or 0
    if expected.block_contacts == 0 and observed_blocks > 0
        and blocked_wall_stun_shift == nil then
        local blocked_early, block_step, block_action, combo_before, saw_block =
            block_before_expected_combo_completion(steps, expected.max_combo)
        if blocked_early then
            reasons[#reasons + 1] = string.format(
                "unexpected_block_before_combo_completion:"
                    .. "step=%d:action=%s:combo=%d:expected=%d",
                block_step,
                tostring(block_action),
                combo_before,
                expected.max_combo
            )
        elseif not saw_block then
            reasons[#reasons + 1] =
                "unexpected_block_contacts_without_action_evidence"
        end
    end
    local unresolved_anchors = tonumber(stats.unresolved_anchors) or 0
    if unresolved_anchors > 0 then
        -- Raw input is preserved frame-for-frame, so a press that does not
        -- produce an Action is still reproducible evidence rather than a
        -- transcription failure. Actual Actions, outcome and the second raw
        -- replay remain the acceptance boundary.
        advisories[#advisories + 1] = string.format(
            "unbound_input_anchors:%d",
            unresolved_anchors
        )
    end
    local unresolved_motion_actions = tonumber(stats.unresolved_motion_actions)
    if unresolved_motion_actions == nil then
        -- Reports produced before the compiler distinguished safe,
        -- contact-proven input notation from genuinely unresolved Actions
        -- must retain the old strict behavior.
        unresolved_motion_actions = tonumber(stats.fallback_motion_actions) or 0
    end
    if stats.motion_resolver_available == true
        and unresolved_motion_actions > 0 then
        reasons[#reasons + 1] = "unresolved_action_motion"
    end
    local input_derived_motion_actions =
        tonumber(stats.input_derived_motion_actions) or 0
    local input_derived_noncontact_motion_actions =
        tonumber(stats.input_derived_noncontact_motion_actions) or 0
    local input_derived_contact_motion_actions = math.max(
        0,
        input_derived_motion_actions
            - input_derived_noncontact_motion_actions
    )
    if input_derived_contact_motion_actions > 0 then
        advisories[#advisories + 1] = string.format(
            "input_derived_contact_motion:%d",
            input_derived_contact_motion_actions
        )
    end
    if input_derived_noncontact_motion_actions > 0 then
        advisories[#advisories + 1] = string.format(
            "input_derived_noncontact_motion:%d",
            input_derived_noncontact_motion_actions
        )
    end
    local input_refined_motion_actions =
        tonumber(stats.input_refined_motion_actions) or 0
    if input_refined_motion_actions > 0 then
        advisories[#advisories + 1] = string.format(
            "input_refined_followup_motion:%d",
            input_refined_motion_actions
        )
    end
    if legacy_segmented_outcome and not source_action_subsequence_match then
        advisories[#advisories + 1] =
            "source_segmented_action_stream_rebuilt"
    end
    if legacy_segmented_outcome and expected_reconnect_reason == nil
        and observed_reconnect_reason ~= nil then
        advisories[#advisories + 1] =
            "source_combo_reset_rebuilt_from_runtime"
    end
    if legacy_segmented_outcome
        and type(observed_combo_rebuild) == "table"
        and (tonumber(observed_combo_rebuild.attribution_lead_steps) or 0) > 0 then
        advisories[#advisories + 1] = string.format(
            "source_contact_attribution_rebuilt:steps=%d:max_lead=%d",
            tonumber(observed_combo_rebuild.attribution_lead_steps) or 0,
            tonumber(observed_combo_rebuild.max_attribution_lead) or 0
        )
    end
    if (tonumber(stats.resolver_error_actions) or 0) > 0 then
        reasons[#reasons + 1] = "motion_resolver_error"
    end

    -- Never let a candidate become self-consistently polluted after the first
    -- capture dropped real damage. Supported persistent effects are made of
    -- small ticks (currently at most 20 HP); a larger still-unconfirmed sample
    -- means the compiler failed to attribute a real contact and must fail
    -- closed before build_candidate can overwrite the source outcome.
    local unconfirmed_hp_loss = math.max(
        0,
        tonumber(stats.unconfirmed_hp_loss) or 0
    )
    local passive_damage_max_tick = math.max(
        0,
        tonumber(stats.passive_damage_max_tick) or 0
    )
    if unconfirmed_hp_loss > 0
        and passive_damage_max_tick > PERSISTENT_DAMAGE_MAX_TICK then
        reasons[#reasons + 1] = string.format(
            "unattributed_damage_tick:max=%d:unconfirmed=%d",
            passive_damage_max_tick,
            unconfirmed_hp_loss
        )
    end

    local damage_tolerance = math.max(20, math.floor(expected.damage * 0.01 + 0.5))
    local observed_combo = tonumber(stats.max_combo) or 0
    local allow_legacy_damage_drift = runtime.allow_legacy_damage_drift == true
        and source_action_match
        and observed_combo == expected.max_combo
    local observed_damage = tonumber(stats.damage) or 0
    local source_damage_matches = math.abs(observed_damage - expected.damage)
        <= damage_tolerance
    if expected.damage > 0
        and math.abs(observed_damage - expected.damage) > damage_tolerance
        and not allow_legacy_damage_drift then
        if blocked_wall_stun_shift ~= nil then
            advisories[#advisories + 1] = string.format(
                "source_blocked_wall_stun_damage_rebuilt:expected=%d:observed=%d",
                expected.damage,
                observed_damage
            )
        elseif runtime.allow_legacy_outcome_rebuild == true then
            advisories[#advisories + 1] = string.format(
                "source_damage_rebuilt:expected=%d:observed=%d",
                expected.damage,
                observed_damage
            )
        else
            reasons[#reasons + 1] = "damage_mismatch"
        end
    end
    if expected.max_combo > 0 and observed_combo ~= expected.max_combo then
        if blocked_wall_stun_shift ~= nil then
            advisories[#advisories + 1] = string.format(
                "source_blocked_wall_stun_combo_rebuilt:expected=%d:observed=%d",
                expected.max_combo,
                observed_combo
            )
        elseif runtime.allow_legacy_outcome_rebuild == true
            and observed_combo > expected.max_combo then
            advisories[#advisories + 1] = string.format(
                "source_combo_count_rebuilt:expected=%d:observed=%d",
                expected.max_combo,
                observed_combo
            )
        elseif runtime.allow_legacy_outcome_rebuild == true
            and observed_combo < expected.max_combo then
            if legacy_segmented_outcome
                and observed_combo > 0
                and observed_blocks == expected.block_contacts then
                advisories[#advisories + 1] = string.format(
                    "source_segmented_combo_count_rebuilt:expected=%d:observed=%d",
                    expected.max_combo,
                    observed_combo
                )
            else
                reasons[#reasons + 1] = string.format(
                    "combo_count_regressed:expected=%d:observed=%d",
                    expected.max_combo,
                    observed_combo
                )
            end
        else
            reasons[#reasons + 1] = "combo_count_mismatch"
        end
    end
    if expected.block_contacts > 0
        and (tonumber(stats.block_contacts) or 0) == 0 then
        reasons[#reasons + 1] = "block_contact_missing"
    end
    if runtime.compare_drive_usage ~= false
        and expected.drive_used > 0
        and math.abs((tonumber(stats.drive_used) or 0) - expected.drive_used) > 100 then
        reasons[#reasons + 1] = "drive_consumption_mismatch"
    end
    local observed_super_used = tonumber(stats.super_used) or 0
    if expected.super_used > 0
        and math.abs(observed_super_used - expected.super_used) > 100 then
        if legacy_segmented_outcome
            and observed_blocks == expected.block_contacts then
            advisories[#advisories + 1] = string.format(
                "source_segmented_super_usage_rebuilt:expected=%d:observed=%d",
                expected.super_used,
                observed_super_used
            )
        elseif runtime.allow_legacy_outcome_rebuild == true
            and expected.damage > 0
            and expected.max_combo > 0
            and is_legacy_partial_super_usage(
                expected.super_used,
                observed_super_used
            )
            and source_action_match
            and source_terminal_contact_match
            and runtime.input_completed == true
            and runtime.timed_out ~= true
            and source_damage_matches
            and observed_combo == expected.max_combo
            and observed_blocks == expected.block_contacts then
            advisories[#advisories + 1] = string.format(
                "source_partial_super_usage_rebuilt:expected=%d:observed=%d",
                expected.super_used,
                observed_super_used
            )
        else
            reasons[#reasons + 1] = "super_consumption_mismatch"
        end
    end
    local environment_validation =
        validate_training_environment(sequence, runtime, reasons)

    return {
        ok = #reasons == 0,
        reasons = reasons,
        advisories = advisories,
        suspected_causes = #reasons > 0 and Transcriber.suspected_causes(sequence) or {},
        expected = expected,
        observed = deep_copy(stats),
        source_action_match = source_action_match,
        source_action_subsequence_match = source_action_subsequence_match,
        legacy_authored_action_subsequence_match =
            legacy_authored_action_subsequence_match,
        legacy_segmented_outcome = legacy_segmented_outcome,
        expected_reconnect_reason = expected_reconnect_reason,
        observed_reconnect_reason = observed_reconnect_reason,
        persistent_damage_evidence = persistent_damage_evidence,
        persistent_damage_window_ticks = persistent_damage_window_ticks,
        blocked_wall_stun_shift = deep_copy(blocked_wall_stun_shift),
        observed_combo_rebuild = deep_copy(observed_combo_rebuild),
        environment_validation = environment_validation,
    }
end

local function prefix_reasons(reasons, prefix)
    local prefixed = {}
    for _, reason in ipairs(type(reasons) == "table" and reasons or {}) do
        prefixed[#prefixed + 1] = prefix .. tostring(reason)
    end
    return prefixed
end

function Transcriber.verify_candidate(candidate, compiled, runtime)
    runtime = type(runtime) == "table" and runtime or {}
    compiled = type(compiled) == "table" and compiled or {}
    local candidate_first = first_step(candidate)
    local replay_source = runtime.input_source
    if replay_source ~= "raw_inputs"
        and replay_source ~= RawInputCodec.RELATIVE_FIELD then
        replay_source = type(candidate_first.relative_raw_inputs) == "table"
            and #candidate_first.relative_raw_inputs > 0
            and RawInputCodec.RELATIVE_FIELD
            or "raw_inputs"
    end
    local evaluation = Transcriber.evaluate(candidate, compiled, {
        input_source = replay_source,
        raw_inputs = runtime.raw_inputs,
        input_completed = runtime.input_completed,
        timed_out = runtime.timed_out,
        action_ids_equivalent = runtime.action_ids_equivalent,
        verify_environment = runtime.verify_environment,
        environment_observed = runtime.environment_observed,
    })
    local reasons = prefix_reasons(evaluation.reasons, "raw_replay_")
    local expected_steps = type(candidate) == "table" and candidate or {}
    local observed_steps = type(compiled.steps) == "table" and compiled.steps or {}
    local timing_tolerance = math.max(0, tonumber(runtime.timing_tolerance) or 2)

    if #observed_steps ~= #expected_steps then
        reasons[#reasons + 1] = string.format(
            "raw_replay_action_count_mismatch:expected=%d:actual=%d",
            #expected_steps,
            #observed_steps
        )
    end

    for index = 1, math.min(#expected_steps, #observed_steps) do
        local expected = expected_steps[index]
        local observed = observed_steps[index]
        local expected_id = tonumber(expected and expected.id)
        local observed_id = tonumber(observed and observed.id)
        local equivalent = expected_id == observed_id
        if not equivalent and type(runtime.action_ids_equivalent) == "function" then
            local ok, matched = pcall(
                runtime.action_ids_equivalent,
                expected_id,
                observed_id
            )
            equivalent = ok and matched == true
        end
        if not equivalent then
            reasons[#reasons + 1] = string.format(
                "raw_replay_action_id_mismatch:step=%d:expected=%s:actual=%s",
                index,
                tostring(expected_id),
                tostring(observed_id)
            )
        end

        if index > 1 then
            local expected_delay = tonumber(expected and expected.delay_from_prev) or 0
            local observed_delay = tonumber(observed and observed.delay_from_prev) or 0
            if math.abs(observed_delay - expected_delay) > timing_tolerance then
                reasons[#reasons + 1] = string.format(
                    "raw_replay_action_timing_mismatch:step=%d:expected=%d:actual=%d",
                    index,
                    expected_delay,
                    observed_delay
                )
            end
        end

        local expected_combo = tonumber(expected and expected.expected_combo) or 0
        local observed_combo = tonumber(observed and observed.expected_combo) or 0
        if expected_combo ~= observed_combo then
            reasons[#reasons + 1] = string.format(
                "raw_replay_step_combo_mismatch:step=%d:expected=%d:actual=%d",
                index,
                expected_combo,
                observed_combo
            )
        end

        local expected_damage = tonumber(expected and expected.damage_at_step) or 0
        local observed_damage = tonumber(observed and observed.damage_at_step) or 0
        local damage_tolerance = math.max(20, math.floor(expected_damage * 0.01 + 0.5))
        if math.abs(observed_damage - expected_damage) > damage_tolerance then
            reasons[#reasons + 1] = string.format(
                "raw_replay_step_damage_mismatch:step=%d:expected=%d:actual=%d",
                index,
                expected_damage,
                observed_damage
            )
        end
    end

    return {
        ok = #reasons == 0,
        reasons = reasons,
        suspected_causes = #reasons > 0 and Transcriber.suspected_causes(candidate) or {},
        expected = evaluation.expected,
        observed = evaluation.observed,
        environment_validation = evaluation.environment_validation,
        action_comparison = {
            expected_count = #expected_steps,
            observed_count = #observed_steps,
            timing_tolerance = timing_tolerance,
        },
    }
end

function Transcriber.mark_raw_replay_verified(candidate, now)
    local first = first_step(candidate)
    if next(first) == nil then return false end
    first._xt_meta = type(first._xt_meta) == "table" and first._xt_meta or {}
    local transcription = type(first._xt_meta.transcription) == "table"
        and first._xt_meta.transcription or {}
    first._xt_meta.transcription = transcription
    transcription.raw_replay_verified = true
    transcription.raw_replay_verified_at = now
    transcription.validation_revision = Transcriber.VALIDATION_REVISION
    return true
end

function Transcriber.build_candidate(source_sequence, compiled, version_info, now, transcription)
    if type(source_sequence) ~= "table" or type(source_sequence[1]) ~= "table" then
        return nil, "invalid_source_sequence"
    end
    local steps = type(compiled) == "table" and compiled.steps or nil
    if type(steps) ~= "table" or #steps == 0 then return nil, "no_compiled_steps" end

    local payload = deep_copy(source_sequence[1])
    for key in pairs(DERIVED_STEP_KEYS) do payload[key] = nil end
    local candidate = deep_copy(steps)
    Validator.annotate_terminal_pressure_tail(candidate)
    for key, value in pairs(payload) do candidate[1][key] = value end
    local synchronized_legacy_fields =
        SceneState.synchronize_legacy_snapshot(candidate[1])

    local meta = type(candidate[1]._xt_meta) == "table" and candidate[1]._xt_meta or {}
    candidate[1]._xt_meta = meta
    meta.updated_at = now
    if meta.created_at == nil then meta.created_at = now end
    meta.schema = tonumber(version_info and version_info.schema) or meta.schema or 2
    meta.versions = type(meta.versions) == "table" and meta.versions or {}
    meta.versions.game = { id = "sf6" }
    meta.versions.recorder = {
        id = version_info and version_info.product_id or "sf6cc",
        version = version_info and version_info.product_version or "unknown",
    }
    meta.versions.json = {
        id = version_info and version_info.json_id or "xt.combo_trial",
        version = version_info and version_info.json_version or "2",
    }
    transcription = type(transcription) == "table" and transcription or {}
    local source_input = transcription.input_source
    local input_origin = source_input == "timeline"
        and "captured_timeline_replay" or "source_recording"
    if source_input == "timeline"
        or source_input == RawInputCodec.RELATIVE_FIELD then
        local relative = RawInputCodec.normalize_stream(
            transcription.relative_raw_inputs
        )
        if not relative then
            return nil, "transcribed_relative_raw_inputs_missing"
        end
        candidate[1].relative_raw_inputs = deep_copy(relative)
        -- Never leave a native stream beside a timeline-derived portable
        -- stream. Older WTT builds prioritize raw_inputs and would replay the
        -- same side-switch bug instead of falling back to the retained timeline.
        candidate[1].raw_inputs = nil
    elseif source_input == "raw_inputs" then
        local native = RawInputCodec.normalize_stream(transcription.raw_inputs)
        if not native then return nil, "transcribed_raw_inputs_missing" end
        candidate[1].raw_inputs = deep_copy(native)
        candidate[1].relative_raw_inputs = nil
    end
    meta.transcription = type(meta.transcription) == "table" and meta.transcription or {}
    meta.transcription.schema = "sf6cc.combo_transcription.v1"
    meta.transcription.source_input = source_input
    meta.transcription.input_stream_origin = input_origin
    if source_input == "timeline"
        or source_input == RawInputCodec.RELATIVE_FIELD then
        meta.transcription.portable_input =
            RawInputCodec.describe_relative_stream()
        meta.transcription.raw_inputs_origin = nil
        meta.input_stream = RawInputCodec.describe_relative_stream()
    elseif source_input == "raw_inputs" then
        meta.transcription.portable_input = nil
        meta.transcription.raw_inputs_origin = input_origin
        meta.input_stream = nil
    end
    if type(transcription.source_advisories) == "table"
        and #transcription.source_advisories > 0 then
        meta.transcription.source_advisories =
            deep_copy(transcription.source_advisories)
    else
        meta.transcription.source_advisories = nil
    end
    if type(transcription.environment_adjustments) == "table"
        and #transcription.environment_adjustments > 0 then
        meta.transcription.environment_adjustments =
            deep_copy(transcription.environment_adjustments)
    else
        meta.transcription.environment_adjustments = nil
    end
    if synchronized_legacy_fields > 0 then
        meta.transcription.synchronized_legacy_scene_fields =
            synchronized_legacy_fields
    else
        meta.transcription.synchronized_legacy_scene_fields = nil
    end
    if type(meta.step_notes) == "table" then
        local source_notes = meta.step_notes
        local rewritten_notes = {}
        for index = 1, #candidate do
            rewritten_notes[index] = type(source_notes[index]) == "string"
                and source_notes[index] or ""
        end
        meta.step_notes = rewritten_notes
    end

    local source_stats = type(source_sequence[1].combo_stats) == "table"
        and deep_copy(source_sequence[1].combo_stats) or {}
    source_stats.damage = tonumber(compiled.stats and compiled.stats.damage) or source_stats.damage or 0
    source_stats.drive_used = tonumber(compiled.stats and compiled.stats.drive_used)
        or source_stats.drive_used or 0
    source_stats.super_used = tonumber(compiled.stats and compiled.stats.super_used)
        or source_stats.super_used or 0
    candidate[1].combo_stats = source_stats
    -- build_candidate is the one-way compatibility boundary from legacy V2
    -- metadata to the canonical environment. Infer old combo_stats.hit_type
    -- here exactly once; all later playback/audit paths consume the persisted
    -- dummy_counter_type without guessing again.
    TrainingEnvironment.normalize_counter_policy(candidate, true)
    return candidate
end

function Transcriber.new_run(character, paths, now, options)
    options = type(options) == "table" and options or {}
    local copied_paths = {}
    for _, path in ipairs(type(paths) == "table" and paths or {}) do
        copied_paths[#copied_paths + 1] = path
    end
    return {
        active = true,
        cancel_requested = false,
        character = character or "Unknown",
        transcription_scope = options.scope or "all",
        requested_path = options.requested_path,
        paths = copied_paths,
        path_index = 0,
        resume_processed = 0,
        index = 0,
        total = #copied_paths,
        passed = 0,
        failed = 0,
        started_at = now,
        finished_at = nil,
        current_path = nil,
        current_name = nil,
        current_source = nil,
        input_source = nil,
        capture_input_source = nil,
        captured_raw_inputs = nil,
        input_finished_frame = nil,
        pending_next = false,
        pending_next_frame = nil,
        session = nil,
        phase = nil,
        capture_compiled = nil,
        capture_evaluation = nil,
        verification_candidate = nil,
        items = {},
        status = "准备转录",
        report_path = nil,
    }
end

local function normalized_source_path(path)
    return tostring(path or ""):gsub("\\", "/"):lower()
end

function Transcriber.remaining_paths(previous_run, paths)
    local completed = {}
    local retained = {}
    local items = type(previous_run) == "table"
        and type(previous_run.items) == "table" and previous_run.items or {}
    for _, item in ipairs(items) do
        -- Reports written before raw replay verification have no marker at
        -- all. Requeue both their apparent passes and failures: either result
        -- may have been caused by the old, unstable environment startup.
        -- Current failures explicitly store false plus the active validation
        -- revision. A policy upgrade requeues only stale failures.
        local has_verification_marker = item.raw_replay_verified ~= nil
        local validation_is_current =
            tonumber(item.validation_revision) == Transcriber.VALIDATION_REVISION
        local is_completed =
            (item.status == "passed" and item.raw_replay_verified == true)
            or (item.status ~= "passed"
                and has_verification_marker
                and validation_is_current)
        if is_completed then
            local key = normalized_source_path(item and item.source_file)
            if key ~= "" then completed[key] = true end
            retained[#retained + 1] = deep_copy(item)
        end
    end

    local remaining = {}
    for _, path in ipairs(type(paths) == "table" and paths or {}) do
        if not completed[normalized_source_path(path)] then
            remaining[#remaining + 1] = path
        end
    end
    return remaining, #retained, retained
end

function Transcriber.resume_info(previous_run, character, paths)
    if type(previous_run) ~= "table" or previous_run.active == true then return nil end
    local scope = previous_run.transcription_scope
    if scope ~= nil and scope ~= "all" then return nil end
    if type(previous_run.items) ~= "table" or #previous_run.items == 0 then return nil end
    if tostring(previous_run.character or ""):lower() ~= tostring(character or ""):lower() then
        return nil
    end

    local remaining, processed = Transcriber.remaining_paths(previous_run, paths)
    if #remaining == 0 then return nil end
    return {
        processed = processed,
        remaining = #remaining,
        total = processed + #remaining,
    }
end

function Transcriber.failed_source_paths(previous_run)
    if type(previous_run) ~= "table"
        or previous_run.active == true
        or previous_run.mode == "runtime_audit"
        or type(previous_run.items) ~= "table" then
        return {}
    end
    local paths = {}
    local seen = {}
    for _, item in ipairs(previous_run.items) do
        local path = item and item.source_file
        local key = normalized_source_path(path)
        if item and item.status ~= "passed" and key ~= "" and not seen[key] then
            paths[#paths + 1] = path
            seen[key] = true
        end
    end
    return paths
end

-- A failure-only retry retains the source report's scope. For character-wide
-- runs, keep previously verified passes so the new report and candidate browser
-- remain a complete install set; current/subset runs stay narrow.
function Transcriber.failure_retry_run(previous_run, character, paths, now)
    local run = Transcriber.new_run(character, paths, now, {
        scope = type(previous_run) == "table"
            and (previous_run.transcription_scope or "all") or "all",
        requested_path = type(previous_run) == "table"
            and previous_run.requested_path or nil,
    })
    local retained = {}
    local items = type(previous_run) == "table"
        and type(previous_run.items) == "table" and previous_run.items or {}
    for _, item in ipairs(items) do
        if item.status == "passed"
            and item.raw_replay_verified == true
            and type(item.candidate_file) == "string"
            and item.candidate_file ~= "" then
            retained[#retained + 1] = deep_copy(item)
        end
    end
    run.items = retained
    run.resume_processed = #retained
    run.index = #retained
    run.total = #retained + #run.paths
    run.passed = #retained
    run.status = string.format(
        "准备重试：已验证 %d，待重试 %d",
        #retained,
        #run.paths
    )
    return run
end

function Transcriber.resume_run(previous_run, character, paths, now)
    local info = Transcriber.resume_info(previous_run, character, paths)
    if not info then return nil, "nothing_to_resume" end

    local remaining, _, retained = Transcriber.remaining_paths(previous_run, paths)
    local run = Transcriber.new_run(
        character,
        remaining,
        previous_run.started_at or now
    )
    run.items = retained
    run.resume_processed = #run.items
    run.index = run.resume_processed
    run.total = run.resume_processed + #run.paths
    run.output_dir = previous_run.output_dir or previous_run.candidate_root
    run.report_path = previous_run.report_path
    run.resume_count = (tonumber(previous_run.resume_count) or 0) + 1
    run.resumed = true
    run.status = string.format(
        "准备续转：已处理 %d，剩余 %d",
        run.resume_processed,
        #run.paths
    )
    for _, item in ipairs(run.items) do
        if item.status == "passed" then
            run.passed = run.passed + 1
        else
            run.failed = run.failed + 1
        end
    end
    return run
end

function Transcriber.report(run)
    return {
        schema = Transcriber.REPORT_SCHEMA,
        validation_revision = Transcriber.VALIDATION_REVISION,
        character = run.character,
        transcription_scope = run.transcription_scope or "all",
        requested_path = run.requested_path,
        started_at = run.started_at,
        finished_at = run.finished_at,
        canceled = run.cancel_requested == true,
        fatal_error = run.fatal_error,
        total = run.total,
        processed = #run.items,
        passed = run.passed,
        failed = run.failed,
        resume_count = tonumber(run.resume_count) or 0,
        source_audit_report = run.source_audit_report,
        source_transcription_report = run.source_transcription_report,
        candidate_root = run.output_dir
            or (Transcriber.OUTPUT_ROOT .. "/" .. tostring(run.character)),
        items = deep_copy(run.items),
    }
end

Transcriber.deep_copy = deep_copy
Transcriber.expected_outcome = expected_outcome

return Transcriber
