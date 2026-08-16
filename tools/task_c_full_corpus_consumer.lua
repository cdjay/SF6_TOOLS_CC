package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local input_file = assert(arg[1], "missing generated Lua corpus input")
local output_file = assert(arg[2], "missing JSON output path")
local corpus = dofile(input_file)

local function deep_copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[deep_copy(key, seen)] = deep_copy(item, seen)
    end
    return copy
end

local function deep_equal(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not deep_equal(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function normalize_path(value)
    return tostring(value or ""):gsub("\\", "/"):gsub("^%./", ""):lower()
end

local json_documents = corpus.json_documents or {}
json = {
    load_file = function(path)
        local document = json_documents[normalize_path(path)]
        if document == nil then return nil end
        return deep_copy(document)
    end,
    load_string = function() return nil end,
}
_G.safe_load_json = function(path) return json.load_file(path) end
fs = { read = function() return nil end }
log = { warn = function() end, error = function() end, info = function() end }
sdk = {}
imgui = setmetatable({}, { __index = function() return function() return nil end end })
re = {
    on_frame = function() end,
    on_draw_ui = function() end,
    on_application_entry = function() end,
}

local UnifiedActionConsumer = require("func/ComboTrials/UnifiedActionConsumer")
local RawInputCodec = require("func/ComboTrials/RawInputCodec")
local TimelineSequenceNormalizer = require("func/ComboTrials/TimelineSequenceNormalizer")
local SequenceGrouping = require("func/ComboTrials/SequenceGrouping")
local SceneState = require("func/ComboTrials/SceneState")
local Validator = require("func/ComboTrials/Validator")
local CharacterRules = require("func/ComboTrials/CharacterRules")
local ActionCompatibility = require("func/ComboTrials/ActionCompatibility")
local GeneratedActionRelations = require("func/ComboTrials/GeneratedActionRelations")
local SF6CCVersion = require("func/SF6CC_Version")
local ComboTrialsImGui = require("func/ComboTrials_ImGui")

TimelineSequenceNormalizer.init({ is_drive_rush_id = function() return false end })
ComboTrialsImGui.init({
    d2d_cfg = {
        allow_classic_trials_in_modern = false,
        modern_display_mode = "simple",
        show_unresolved_action_ids = true,
        font_size = 0.02,
        trial_title_font_size = 0.03,
    },
    trial_state = {},
    players = {},
    sf6_menu_state = {},
    is_runtime_allowed = function() return false end,
})

local summary = {
    schema = "sf6cc.task-c.full-corpus-consumer.v1",
    corpus_snapshot = corpus.snapshot_id,
    target_game_build = corpus.target_game_build,
    cases = 0,
    steps = 0,
    checks = {
        normalization_pass = 0,
        normalization_fail = 0,
        normalization_idempotent = 0,
        normalization_non_idempotent = 0,
        source_immutability_pass = 0,
        source_mutation = 0,
        input_priority_pass = 0,
        input_priority_fail = 0,
        raw_mask_roundtrip_pass = 0,
        raw_mask_roundtrip_fail = 0,
        timeline_translation_pass = 0,
        timeline_translation_fail = 0,
        grouping_idempotent = 0,
        grouping_non_idempotent = 0,
        scene_state_idempotent = 0,
        scene_state_non_idempotent = 0,
        validator_idempotent = 0,
        validator_non_idempotent = 0,
        command_display_pass = 0,
        command_display_fail = 0,
        command_display_resolved_steps = 0,
        command_display_suppressed_steps = 0,
        command_display_preserved_steps = 0,
        command_display_unresolved_steps = 0,
        recorded_motion_drift_steps = 0,
        detection_exact_tp = 0,
        detection_exact_fn = 0,
        detection_wrong_id_tn = 0,
        detection_wrong_id_fp = 0,
        detection_idless_motion_tp = 0,
        detection_idless_motion_fn = 0,
        detection_idless_wrong_motion_tn = 0,
        detection_idless_wrong_motion_fp = 0,
        detection_idless_missing_input_tn = 0,
        detection_idless_missing_input_fp = 0,
        detection_alias_tp = 0,
        detection_alias_fn = 0,
        detection_compatibility_tp = 0,
        detection_compatibility_fn = 0,
        detection_generated_group_tp = 0,
        detection_generated_group_fn = 0,
        detection_combo_count_tp = 0,
        detection_combo_count_fn = 0,
        detection_wrong_combo_count_tn = 0,
        detection_wrong_combo_count_fp = 0,
    },
    input_sources = {},
    display_statuses = {},
    failures = {},
}

local function increment(table_value, key, amount)
    table_value[key] = (table_value[key] or 0) + (amount or 1)
end

local function fail(case, check, detail)
    summary.failures[#summary.failures + 1] = {
        case_id = case.character .. ":" .. case.filename,
        character = case.character,
        file = case.source or case.path,
        exact_sha256 = case.exact_sha256,
        check = check,
        detail = tostring(detail or "failed"),
    }
end

local function shifted_timeline(timeline, amount)
    if type(timeline) ~= "table" or type(timeline[1]) ~= "string" then return nil end
    local shifted = { tostring(amount) .. "f : 5" }
    for _, line in ipairs(timeline) do shifted[#shifted + 1] = line end
    return shifted
end

local function event_translation_equal(original, shifted, amount, shifted_prefix, original_start)
    shifted_prefix = shifted_prefix or 0
    original_start = original_start or 1
    if (#original - original_start + 1) + shifted_prefix
        ~= (#shifted - original_start + 1) then return false end
    for index = original_start, #original do
        local left = deep_copy(original[index])
        local right = deep_copy(shifted[index + shifted_prefix])
        for _, field in ipairs({ "frame", "start_frame" }) do
            local left_frame = tonumber(left[field])
            local right_frame = tonumber(right[field])
            if left_frame ~= nil or right_frame ~= nil then
                if left_frame == nil or right_frame ~= left_frame + amount then return false end
                left[field] = nil
                right[field] = nil
            end
        end
        left.index = nil
        right.index = nil
        if not deep_equal(left, right) then return false end
    end
    return true
end

local function validate_input_semantics(case, sequence)
    local first = sequence[1]
    local relative = RawInputCodec.normalize_stream(first.relative_raw_inputs)
    local native = RawInputCodec.normalize_stream(first.raw_inputs)
    local has_timeline = RawInputCodec.has_usable_timeline(first.timeline)
    RawInputCodec.invalidate_stream_cache(first)
    local _, runtime_source = RawInputCodec.select_transcription_stream(first, true)
    RawInputCodec.invalidate_stream_cache(first)
    local _, conversion_source = RawInputCodec.select_transcription_stream(first, false)
    local expected_runtime = relative and "relative_raw_inputs"
        or native and "raw_inputs"
        or has_timeline and "timeline" or nil
    local expected_conversion = relative and "relative_raw_inputs"
        or has_timeline and "timeline"
        or native and "raw_inputs" or nil
    increment(summary.input_sources, tostring(runtime_source or "none"))
    if runtime_source == expected_runtime and conversion_source == expected_conversion then
        summary.checks.input_priority_pass = summary.checks.input_priority_pass + 1
    else
        summary.checks.input_priority_fail = summary.checks.input_priority_fail + 1
        fail(case, "input_priority", string.format(
            "runtime=%s expected=%s conversion=%s expected_conversion=%s",
            tostring(runtime_source), tostring(expected_runtime),
            tostring(conversion_source), tostring(expected_conversion)
        ))
    end

    local streams = { relative, native }
    local masks_ok = true
    for _, stream in ipairs(streams) do
        for _, mask in ipairs(stream or {}) do
            local normalized = RawInputCodec.normalize_mask(mask)
            for _, facing_right in ipairs({ true, false }) do
                local relative_mask = RawInputCodec.native_to_relative(normalized, facing_right)
                local native_mask = RawInputCodec.relative_to_native(relative_mask, facing_right)
                if native_mask ~= normalized then masks_ok = false end
            end
        end
    end
    if masks_ok then
        summary.checks.raw_mask_roundtrip_pass = summary.checks.raw_mask_roundtrip_pass + 1
    else
        summary.checks.raw_mask_roundtrip_fail = summary.checks.raw_mask_roundtrip_fail + 1
        fail(case, "raw_mask_roundtrip", "native/relative transform was not involutive")
    end

    if has_timeline then
        local shifted = shifted_timeline(first.timeline, 5)
        local original_press = TimelineSequenceNormalizer.build_press_events(first.timeline)
        local shifted_press = shifted and TimelineSequenceNormalizer.build_press_events(shifted) or {}
        local original_direction = TimelineSequenceNormalizer.build_direction_states(first.timeline)
        local shifted_direction = shifted and TimelineSequenceNormalizer.build_direction_states(shifted) or {}
        local neutral_prefix_merged = original_direction[1]
            and tostring(original_direction[1].dir) == "5"
        local direction_prefix = neutral_prefix_merged and 0 or 1
        local direction_start = neutral_prefix_merged and 2 or 1
        local translated = shifted ~= nil
            and event_translation_equal(original_press, shifted_press, 5, 0)
            and event_translation_equal(
                original_direction,
                shifted_direction,
                5,
                direction_prefix,
                direction_start
            )
        if translated then
            summary.checks.timeline_translation_pass = summary.checks.timeline_translation_pass + 1
        else
            summary.checks.timeline_translation_fail = summary.checks.timeline_translation_fail + 1
            fail(case, "timeline_translation", "event order/content changed after +5 frame translation")
        end
    end
end

local common_rules = CharacterRules.load_common()
local detection_contexts = {}

local function first_number(value)
    if type(value) == "number" then return tonumber(value) end
    if type(value) == "table" then
        for _, item in ipairs(value) do
            local number = tonumber(item)
            if number ~= nil then return number end
        end
        return nil
    end
    if type(value) == "string" then
        return tonumber(value:match("%d+"))
    end
    return nil
end

local function detection_context(character)
    local cached = detection_contexts[character]
    if cached then return cached end
    local character_rules = CharacterRules.load_for_character(character)
    local compatibility_rules = select(1, ActionCompatibility.load(
        character,
        SF6CCVersion.GAME_VERSION,
        function(path) return json.load_file(path) end
    ))
    local generated_relations = select(1, GeneratedActionRelations.load(
        character,
        function(path) return json.load_file(path) end
    ))
    cached = {
        character_rules = character_rules,
        compatibility_rules = compatibility_rules,
        generated_relations = generated_relations,
        generated_peers = {},
    }
    detection_contexts[character] = cached
    return cached
end

local function generated_peer(context, action_id)
    local cached = context.generated_peers[action_id]
    if cached ~= nil then return cached ~= false and cached or nil end
    local relations = context.generated_relations
    local peer = nil
    if type(relations) == "table" and type(relations.by_action) == "table" then
        for candidate in pairs(relations.by_action) do
            if tonumber(candidate) ~= tonumber(action_id)
                and GeneratedActionRelations.share_source_group(
                    relations,
                    action_id,
                    candidate
                ) then
                peer = tonumber(candidate)
                break
            end
        end
    end
    context.generated_peers[action_id] = peer or false
    return peer
end

local function validate_detection(case, sequence)
    local context = detection_context(case.character)
    for index, expected in ipairs(sequence) do
        local expected_id = tonumber(expected.id)
        if expected_id ~= nil then
            local exception = CharacterRules.get_match_rule(
                context.character_rules,
                common_rules,
                case.character,
                expected_id
            )
            local exact = UnifiedActionConsumer.match_expected_action(
                expected,
                expected_id,
                expected.motion,
                expected.motion,
                exception,
                context.compatibility_rules,
                context.generated_relations
            )
            if exact.matched == true then
                summary.checks.detection_exact_tp = summary.checks.detection_exact_tp + 1
            else
                summary.checks.detection_exact_fn = summary.checks.detection_exact_fn + 1
                fail(case, "detection_exact", "step=" .. tostring(index))
            end

            local wrong = UnifiedActionConsumer.match_expected_action(
                expected,
                expected_id + 1000000,
                expected.motion,
                expected.motion,
                exception,
                context.compatibility_rules,
                context.generated_relations
            )
            if wrong.matched ~= true then
                summary.checks.detection_wrong_id_tn = summary.checks.detection_wrong_id_tn + 1
            else
                summary.checks.detection_wrong_id_fp = summary.checks.detection_wrong_id_fp + 1
                fail(case, "detection_wrong_id", "step=" .. tostring(index))
            end

            local alias_id = first_number(exception and exception.action_alias_ids)
            if alias_id ~= nil and alias_id ~= expected_id then
                local alias = UnifiedActionConsumer.match_expected_action(
                    expected,
                    alias_id,
                    expected.motion,
                    expected.motion,
                    exception,
                    context.compatibility_rules,
                    context.generated_relations
                )
                if alias.matched == true then
                    summary.checks.detection_alias_tp = summary.checks.detection_alias_tp + 1
                else
                    summary.checks.detection_alias_fn = summary.checks.detection_alias_fn + 1
                    fail(case, "detection_alias", "step=" .. tostring(index))
                end
            end

            local runtime_id = ActionCompatibility.resolve(
                context.compatibility_rules,
                expected
            )
            if runtime_id ~= nil then
                local compatibility = UnifiedActionConsumer.match_expected_action(
                    expected,
                    runtime_id,
                    expected.motion,
                    expected.motion,
                    exception,
                    context.compatibility_rules,
                    context.generated_relations
                )
                if compatibility.matched == true then
                    summary.checks.detection_compatibility_tp =
                        summary.checks.detection_compatibility_tp + 1
                else
                    summary.checks.detection_compatibility_fn =
                        summary.checks.detection_compatibility_fn + 1
                    fail(case, "detection_compatibility", "step=" .. tostring(index))
                end
            end

            local peer = generated_peer(context, expected_id)
            if peer ~= nil then
                local generated = UnifiedActionConsumer.match_expected_action(
                    expected,
                    peer,
                    expected.motion,
                    expected.motion,
                    exception,
                    context.compatibility_rules,
                    context.generated_relations
                )
                if generated.matched == true then
                    summary.checks.detection_generated_group_tp =
                        summary.checks.detection_generated_group_tp + 1
                else
                    summary.checks.detection_generated_group_fn =
                        summary.checks.detection_generated_group_fn + 1
                    fail(case, "detection_generated_group", "step=" .. tostring(index))
                end
            end

            local motion = tostring(expected.motion or "")
            if motion ~= "" then
                local idless = deep_copy(expected)
                idless.id = nil
                local idless_positive = UnifiedActionConsumer.match_expected_action(
                    idless,
                    nil,
                    motion,
                    motion,
                    nil,
                    nil,
                    nil
                )
                if idless_positive.matched == true then
                    summary.checks.detection_idless_motion_tp =
                        summary.checks.detection_idless_motion_tp + 1
                else
                    summary.checks.detection_idless_motion_fn =
                        summary.checks.detection_idless_motion_fn + 1
                    fail(case, "detection_idless_motion", "step=" .. tostring(index))
                end
                local idless_wrong = UnifiedActionConsumer.match_expected_action(
                    idless,
                    nil,
                    "TASK_C_WRONG_MOTION",
                    "TASK_C_WRONG_INPUT",
                    nil,
                    nil,
                    nil
                )
                if idless_wrong.matched ~= true then
                    summary.checks.detection_idless_wrong_motion_tn =
                        summary.checks.detection_idless_wrong_motion_tn + 1
                else
                    summary.checks.detection_idless_wrong_motion_fp =
                        summary.checks.detection_idless_wrong_motion_fp + 1
                    fail(case, "detection_idless_wrong_motion", "step=" .. tostring(index))
                end
                local idless_missing = UnifiedActionConsumer.match_expected_action(
                    idless,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil
                )
                if idless_missing.matched ~= true then
                    summary.checks.detection_idless_missing_input_tn =
                        summary.checks.detection_idless_missing_input_tn + 1
                else
                    summary.checks.detection_idless_missing_input_fp =
                        summary.checks.detection_idless_missing_input_fp + 1
                    fail(case, "detection_idless_missing_input", "step=" .. tostring(index))
                end
            end
        end

        if index > 1 then
            local previous = sequence[index - 1]
            local previous_combo = tonumber(previous.expected_combo)
            local expected_combo = tonumber(expected.expected_combo)
            local strict_combo_case = previous_combo ~= nil and previous_combo > 0
                and expected_combo ~= nil and expected_combo > 0
                and previous.is_projectile_hit ~= true
                and not Validator.is_pressure_tail_step(expected)
                and not Validator.is_non_damage_transition(expected, previous)
                and not Validator.is_expected_combo_restart_step(expected, previous)
            if strict_combo_case then
                local correct = Validator.check_combo({
                    expected = expected,
                    prev_step = previous,
                    current_combo = previous_combo,
                    opponent_knocked_down = false,
                })
                if correct == true then
                    summary.checks.detection_combo_count_tp =
                        summary.checks.detection_combo_count_tp + 1
                else
                    summary.checks.detection_combo_count_fn =
                        summary.checks.detection_combo_count_fn + 1
                    fail(case, "detection_combo_count", "step=" .. tostring(index))
                end
                local wrong_combo = Validator.check_combo({
                    expected = expected,
                    prev_step = previous,
                    current_combo = previous_combo + 1000000,
                    opponent_knocked_down = false,
                })
                if wrong_combo ~= true then
                    summary.checks.detection_wrong_combo_count_tn =
                        summary.checks.detection_wrong_combo_count_tn + 1
                else
                    summary.checks.detection_wrong_combo_count_fp =
                        summary.checks.detection_wrong_combo_count_fp + 1
                    fail(case, "detection_wrong_combo_count", "step=" .. tostring(index))
                end
            end
        end
    end
end

for _, case in ipairs(corpus.cases or {}) do
    summary.cases = summary.cases + 1
    summary.steps = summary.steps + #case.sequence
    local original = deep_copy(case.sequence)
    local normalization = UnifiedActionConsumer.normalize_sequence(case.sequence)
    if normalization.ok ~= true then
        summary.checks.normalization_fail = summary.checks.normalization_fail + 1
        fail(case, "normalization", normalization.reason)
    else
        summary.checks.normalization_pass = summary.checks.normalization_pass + 1
        local second = UnifiedActionConsumer.normalize_sequence(normalization.sequence)
        if second.ok == true and deep_equal(normalization.sequence, second.sequence) then
            summary.checks.normalization_idempotent = summary.checks.normalization_idempotent + 1
        else
            summary.checks.normalization_non_idempotent = summary.checks.normalization_non_idempotent + 1
            fail(case, "normalization_idempotence", second.reason)
        end

        if deep_equal(original, case.sequence) then
            summary.checks.source_immutability_pass = summary.checks.source_immutability_pass + 1
        else
            summary.checks.source_mutation = summary.checks.source_mutation + 1
            fail(case, "normalization_source_mutation", "source sequence changed")
        end

        validate_input_semantics(case, normalization.sequence)
        validate_detection(case, normalization.sequence)

        local grouped = deep_copy(normalization.sequence)
        SequenceGrouping.assign_groups(grouped, case.character, nil)
        local grouped_once = deep_copy(grouped)
        SequenceGrouping.assign_groups(grouped, case.character, nil)
        if deep_equal(grouped_once, grouped) then
            summary.checks.grouping_idempotent = summary.checks.grouping_idempotent + 1
        else
            summary.checks.grouping_non_idempotent = summary.checks.grouping_non_idempotent + 1
            fail(case, "grouping_idempotence", "second assignment changed groups")
        end

        local scene_sequence = deep_copy(normalization.sequence)
        SceneState.materialize_stable_legacy_actor_hp(scene_sequence)
        SceneState.synchronize_legacy_snapshot(scene_sequence[1])
        local scene_once = deep_copy(scene_sequence)
        SceneState.materialize_stable_legacy_actor_hp(scene_sequence)
        SceneState.synchronize_legacy_snapshot(scene_sequence[1])
        if deep_equal(scene_once, scene_sequence) then
            summary.checks.scene_state_idempotent = summary.checks.scene_state_idempotent + 1
        else
            summary.checks.scene_state_non_idempotent = summary.checks.scene_state_non_idempotent + 1
            fail(case, "scene_state_idempotence", "second materialization changed scene facts")
        end

        local validator_sequence = deep_copy(normalization.sequence)
        Validator.annotate_terminal_pressure_tail(validator_sequence)
        local validator_once = deep_copy(validator_sequence)
        Validator.annotate_terminal_pressure_tail(validator_sequence)
        if deep_equal(validator_once, validator_sequence) then
            summary.checks.validator_idempotent = summary.checks.validator_idempotent + 1
        else
            summary.checks.validator_non_idempotent = summary.checks.validator_non_idempotent + 1
            fail(case, "validator_idempotence", "second annotation changed sequence")
        end

        local display = ComboTrialsImGui.validate_sequence_command_display(grouped)
        increment(summary.display_statuses, tostring(display.status or "unknown"))
        summary.checks.command_display_resolved_steps =
            summary.checks.command_display_resolved_steps + (display.resolved_step_count or 0)
        summary.checks.command_display_suppressed_steps =
            summary.checks.command_display_suppressed_steps + (display.suppressed_step_count or 0)
        summary.checks.command_display_preserved_steps =
            summary.checks.command_display_preserved_steps + (display.preserved_step_count or 0)
        summary.checks.command_display_unresolved_steps =
            summary.checks.command_display_unresolved_steps + (display.unresolved_count or 0)
        summary.checks.recorded_motion_drift_steps =
            summary.checks.recorded_motion_drift_steps + (display.recorded_motion_drift_count or 0)
        if display.ok == true then
            summary.checks.command_display_pass = summary.checks.command_display_pass + 1
        else
            summary.checks.command_display_fail = summary.checks.command_display_fail + 1
            local detail = tostring(display.status)
            if type(display.unresolved) == "table" and display.unresolved[1] then
                detail = detail .. ": step=" .. tostring(display.unresolved[1].index)
                    .. " action=" .. tostring(display.unresolved[1].action_id_raw)
                    .. " route=" .. tostring(display.unresolved[1].status)
            end
            fail(case, "command_display", detail)
        end
    end
end

summary.failure_count = #summary.failures
summary.ok = summary.failure_count == 0

local function json_escape(value)
    return tostring(value)
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("\b", "\\b")
        :gsub("\f", "\\f")
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
        :gsub("\t", "\\t")
end

local function is_array(value)
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        count = math.max(count, key)
    end
    for index = 1, count do
        if value[index] == nil then return false end
    end
    return true, count
end

local function encode(value)
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" or kind == "number" then return tostring(value) end
    if kind == "string" then return '"' .. json_escape(value) .. '"' end
    if kind ~= "table" then return '"' .. json_escape(tostring(value)) .. '"' end
    local array, count = is_array(value)
    local parts = {}
    if array then
        for index = 1, count do parts[#parts + 1] = encode(value[index]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = encode(key) .. ":" .. encode(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local handle = assert(io.open(output_file, "wb"))
handle:write(encode(summary), "\n")
handle:close()
print(string.format(
    "Task C corpus consumer: cases=%d failures=%d display_pass=%d display_fail=%d",
    summary.cases,
    summary.failure_count,
    summary.checks.command_display_pass,
    summary.checks.command_display_fail
))
if not summary.ok then os.exit(1) end
