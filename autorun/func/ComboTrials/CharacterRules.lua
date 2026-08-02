local json = json

local CharacterRules = {
    name = "ComboTrials.CharacterRules"
}

local EXCEPTION_DIR = "TrainingComboTrials_data/exceptions"
local COMMON_EXCEPTIONS_FILE = EXCEPTION_DIR .. "/Common.json"

-- Some commands select a different runtime Action ID according to game version
-- or runtime state. Keep this compatibility outside recorded combo JSON so
-- legacy files remain portable and immutable.
local UNIVERSAL_ACTION_VARIANT_RULES = {
    -- Older recordings use 854 for Drive Impact. Current command data and
    -- runtime use 855 for the same DI command.
    ["854"] = {
        action_alias_ids = "855"
    }
}

local ACTION_VARIANT_RULES = {
    DeeJay = {
        ["1268"] = {
            action_alias_ids = "1272",
            action_alias_combo_deltas = { ["1272"] = 23 },
            finish_on_first_hit = true
        },
        ["1272"] = {
            action_alias_ids = "1268",
            action_alias_combo_deltas = { ["1268"] = 32 },
            finish_on_first_hit = true
        }
    },
    EHonda = {
        -- These pairs are verified inherited variants of the same physical
        -- command. The game can select either member on two identical raw
        -- replays, so matching must be symmetric while the captured real ID
        -- remains in the candidate JSON.
        ["970"] = { action_alias_ids = "971" },
        ["971"] = { action_alias_ids = "970" },
        ["972"] = { action_alias_ids = "973" },
        ["973"] = { action_alias_ids = "972" }
    }
}

local function merge_match_rule(base, overlay)
    if not overlay then return base end
    if not base then return overlay end

    local merged = {}
    for key, value in pairs(base) do merged[key] = value end
    for key, value in pairs(overlay) do merged[key] = value end
    return merged
end

function CharacterRules.get_exception_filename(character_name)
    return EXCEPTION_DIR .. "/" .. tostring(character_name or ""):gsub("[^%w_]", "") .. ".json"
end

function CharacterRules.load_common()
    local common_exceptions = {}
    pcall(function()
        local loaded = _G.safe_load_json(COMMON_EXCEPTIONS_FILE)
        if loaded then common_exceptions = loaded end
    end)
    return common_exceptions
end

function CharacterRules.load_for_character(character_name)
    local loaded = json.load_file(CharacterRules.get_exception_filename(character_name))
    if loaded then return loaded end
    return {}
end

function CharacterRules.get_exception(character_rules, common_rules, action_id)
    local id = tostring(action_id)
    local character_exception = character_rules and character_rules[id] or nil
    local common_exception = common_rules and common_rules[id] or nil
    return character_exception or common_exception, character_exception, common_exception
end

function CharacterRules.get_match_rule(character_rules, common_rules, character_name, action_id)
    local exception = CharacterRules.get_exception(character_rules, common_rules, action_id)
    local universal_variant = UNIVERSAL_ACTION_VARIANT_RULES[tostring(action_id)]
    local character_variants = ACTION_VARIANT_RULES[tostring(character_name or "")]
    local character_variant = character_variants and character_variants[tostring(action_id)] or nil
    return merge_match_rule(
        merge_match_rule(exception, universal_variant),
        character_variant
    )
end

function CharacterRules.has_character_exception(character_rules, action_id)
    return character_rules and character_rules[tostring(action_id)] and true or false
end

local function parse_id_set(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end

    local ids = {}
    for absorb_str in string.gmatch(value, "([^,]+)") do
        local absorb_num = tonumber(absorb_str:match("^%s*(.-)%s*$"))
        if absorb_num then ids[absorb_num] = true end
    end
    return ids
end

local function parse_absorb_ids(exception)
    return type(exception) == "table"
        and parse_id_set(exception.absorb_ids) or nil
end

-- Build the pure runtime projection table consumed by ActionEventCompiler.
-- JSON loading stays in the caller; this function only interprets already
-- loaded product rules. An explicit action_event_projection object opts an
-- owner in, while absorb_ids remains the sole internal-phase membership list.
function CharacterRules.build_action_event_projection_rules(
    character_rules,
    common_rules
)
    local effective_owners = {}
    for owner_id, exception in pairs(common_rules or {}) do
        effective_owners[tostring(owner_id)] = exception
    end
    for owner_id, exception in pairs(character_rules or {}) do
        effective_owners[tostring(owner_id)] = exception
    end

    local result = {}
    local ambiguous = {}
    for owner_id, exception in pairs(effective_owners) do
        local owner_num = tonumber(owner_id)
        local projection = type(exception) == "table"
            and exception.action_event_projection or nil
        local absorb_ids = parse_absorb_ids(exception)
        if owner_num ~= nil and type(projection) == "table"
            and type(absorb_ids) == "table" then
            local canonical_ids = parse_id_set(projection.canonical_owner_ids) or {}
            for child_id in pairs(absorb_ids) do
                local rule = {
                    kind = canonical_ids[child_id]
                        and "canonical_owner" or "internal_phase",
                    owner_id = owner_num,
                }
                if rule.kind == "canonical_owner" then
                    rule.max_fold_delay_frames = math.max(
                        0,
                        tonumber(projection.max_fold_delay_frames) or 0
                    )
                    rule.require_same_anchor =
                        projection.require_same_anchor == true
                else
                    -- Input passthrough is a separate behavior from outcome
                    -- projection. Most contact/recovery phases should consume
                    -- their incidental edge; only runtime-proven buffered
                    -- phases may return it to the binder.
                    rule.carry_input_anchor =
                        projection.carry_input_anchor == true
                    rule.max_fold_delay_frames = math.max(
                        0,
                        tonumber(projection.max_fold_delay_frames) or 0
                    )
                    rule.require_same_anchor =
                        projection.require_same_anchor == true
                    rule.allow_same_button_press_fold =
                        projection.allow_same_button_press_fold == true
                end
                local existing = result[child_id]
                if type(existing) == "table"
                    and tonumber(existing.owner_id) ~= owner_num then
                    result[child_id] = nil
                    ambiguous[child_id] = true
                elseif not ambiguous[child_id] then
                    result[child_id] = rule
                end
            end
        end
    end
    return result
end

-- Use the compiler's effective projection table instead of interpreting one
-- owner in isolation. This preserves its ambiguity guard when two owners claim
-- the same runtime Action ID.
local function canonical_owner_ids_for_expected(
    character_rules,
    common_rules,
    expected_id
)
    local expected_owner = tonumber(expected_id)
    if expected_owner == nil then return nil end

    local accepted = {}
    local projection_rules =
        CharacterRules.build_action_event_projection_rules(
            character_rules,
            common_rules
        )
    for action_id, rule in pairs(projection_rules) do
        if type(rule) == "table" and rule.kind == "canonical_owner"
            and tonumber(rule.owner_id) == expected_owner then
            local action_num = tonumber(action_id)
            if action_num ~= nil then accepted[action_num] = true end
        end
    end
    return next(accepted) ~= nil and accepted or nil
end

function CharacterRules.find_recording_absorb_owner(character_rules, common_rules, action_id)
    local actual_id = tonumber(action_id)
    if actual_id == nil then return nil end

    local matches = {}
    local function collect(rules)
        for owner_id, exception in pairs(rules or {}) do
            if type(exception) == "table" and exception.record_absorb_as_parent == true then
                local projection = type(exception.action_event_projection) == "table"
                    and exception.action_event_projection or nil
                local absorb_ids = projection
                    and parse_id_set(projection.canonical_owner_ids)
                    or parse_absorb_ids(exception)
                local owner_num = tonumber(owner_id)
                if owner_num and absorb_ids and absorb_ids[actual_id] then
                    matches[#matches + 1] = owner_num
                end
            end
        end
    end

    collect(character_rules)
    collect(common_rules)
    if #matches == 1 then return matches[1] end
    return nil
end

function CharacterRules.is_action_required(exception)
    if type(exception) ~= "table" then return false end
    return exception.action_required == true
        or exception.no_combo_auto_advance == true
        or exception.require_absorb == true
end

local function absorb_requires_combo(exception)
    if type(exception) ~= "table" then return true end
    if exception.absorb_requires_combo == false then return false end
    return not CharacterRules.is_action_required(exception)
end

-- Raw-input playback normally rejects legacy absorb substitutions because the
-- recorded Action ID is its truth. The explicit canonical-owner projection is
-- narrower: ActionEventCompiler already maps this runtime ID to the authored
-- owner, so the live validator must admit the same identity and no other
-- internal phase from absorb_ids.
function CharacterRules.find_recent_canonical_confirmation(
    character_rules,
    common_rules,
    expected,
    recent_inputs,
    character_name
)
    if not expected then return { matched = false, block_reason = "missing_expected" } end

    local exception = CharacterRules.get_exception(
        character_rules,
        common_rules,
        expected.id
    )
    local canonical_ids = canonical_owner_ids_for_expected(
        character_rules,
        common_rules,
        expected.id
    )
    local projection = type(exception) == "table"
        and type(exception.action_event_projection) == "table"
        and exception.action_event_projection or nil
    local declared_ids = projection and projection.canonical_owner_ids or nil
    if type(canonical_ids) ~= "table" then
        return {
            matched = false,
            block_reason = "canonical_owner_projection_missing",
            canonical_owner_ids = declared_ids,
        }
    end

    local expected_combo = tonumber(expected.expected_combo)
    if expected_combo == nil then
        return {
            matched = false,
            block_reason = "missing_expected_combo",
            canonical_owner_ids = declared_ids,
        }
    end

    for i = 1, math.min(10, #(recent_inputs or {})) do
        local recent = recent_inputs[i]
        local recent_id = recent and tonumber(recent.id)
        if recent_id and canonical_ids[recent_id] then
            local combo_count = tonumber(recent.combo_count) or 0
            local combo_ok = (not absorb_requires_combo(exception))
                or combo_count >= expected_combo
            if combo_ok then
                return {
                    matched = true,
                    actual_action_id = recent_id,
                    match_reason = "action_event_projection_recent_canonical_owner",
                    recent_index = i,
                    combo_count = combo_count,
                    start_frame = recent.start_frame,
                    action_instance = recent.action_instance,
                    motion = recent.motion,
                    real_input = recent.real_input,
                    intentional = recent.intentional,
                    expected_id = expected.id,
                    expected_combo = expected_combo,
                    canonical_owner_ids = declared_ids,
                    absorb_ids = declared_ids,
                    source = "action_event_projection",
                    ignore_combo_check = not absorb_requires_combo(exception),
                }
            end
            return {
                matched = false,
                block_reason = "combo_not_reached",
                actual_action_id = recent_id,
                recent_index = i,
                combo_count = combo_count,
                expected_combo = expected_combo,
                canonical_owner_ids = declared_ids,
            }
        end
    end

    return {
        matched = false,
        block_reason = "canonical_owner_id_not_recent",
        canonical_owner_ids = declared_ids,
    }
end

function CharacterRules.match_current_canonical_confirmation(
    character_rules,
    common_rules,
    expected,
    action_id,
    combo_count,
    character_name
)
    if not expected then return { matched = false, block_reason = "missing_expected" } end

    local exception = CharacterRules.get_exception(
        character_rules,
        common_rules,
        expected.id
    )
    local canonical_ids = canonical_owner_ids_for_expected(
        character_rules,
        common_rules,
        expected.id
    )
    local projection = type(exception) == "table"
        and type(exception.action_event_projection) == "table"
        and exception.action_event_projection or nil
    local declared_ids = projection and projection.canonical_owner_ids or nil
    local current_id = tonumber(action_id)
    if not current_id or type(canonical_ids) ~= "table"
        or not canonical_ids[current_id] then
        return {
            matched = false,
            block_reason = type(canonical_ids) == "table"
                and "current_id_not_canonical_owner"
                or "canonical_owner_projection_missing",
            canonical_owner_ids = declared_ids,
        }
    end

    local expected_combo = tonumber(expected.expected_combo)
    if expected_combo == nil then
        return {
            matched = false,
            block_reason = "missing_expected_combo",
            canonical_owner_ids = declared_ids,
        }
    end

    local current_combo = tonumber(combo_count) or 0
    local combo_ok = (not absorb_requires_combo(exception))
        or current_combo >= expected_combo
    if not combo_ok then
        return {
            matched = false,
            block_reason = "combo_not_reached",
            actual_action_id = current_id,
            combo_count = current_combo,
            expected_combo = expected_combo,
            canonical_owner_ids = declared_ids,
        }
    end

    return {
        matched = true,
        actual_action_id = current_id,
        match_reason = "action_event_projection_current_canonical_owner",
        combo_count = current_combo,
        expected_id = expected.id,
        expected_combo = expected_combo,
        canonical_owner_ids = declared_ids,
        absorb_ids = declared_ids,
        source = "action_event_projection",
        motion = "Unknown",
        real_input = "None",
        ignore_combo_check = not absorb_requires_combo(exception),
    }
end

function CharacterRules.find_recent_absorb_confirmation(character_rules, common_rules, expected, recent_inputs, character_name)
    if not expected then return { matched = false, block_reason = "missing_expected" } end

    local exception = CharacterRules.get_exception(character_rules, common_rules, expected.id)
    local absorb_ids = parse_absorb_ids(exception)
    local is_honda = character_name == "EHonda" or character_name == "Honda"
    local match_reason = is_honda and "ehonda_recent_absorb" or "exception_recent_absorb"

    local expected_combo = tonumber(expected.expected_combo)
    if expected_combo == nil then return { matched = false, block_reason = "missing_expected_combo" } end

    for i = 1, math.min(10, #(recent_inputs or {})) do
        local recent = recent_inputs[i]
        local recent_id = recent and tonumber(recent.id)
        local is_exception_absorb = recent_id and absorb_ids and absorb_ids[recent_id]
        if is_exception_absorb then
            local combo_count = tonumber(recent.combo_count) or 0
            local combo_ok = (not absorb_requires_combo(exception)) or combo_count >= expected_combo
            if combo_ok then
                return {
                    matched = true,
                    actual_action_id = recent_id,
                    match_reason = match_reason,
                    recent_index = i,
                    combo_count = combo_count,
                    start_frame = recent.start_frame,
                    action_instance = recent.action_instance,
                    motion = recent.motion,
                    real_input = recent.real_input,
                    intentional = recent.intentional,
                    expected_id = expected.id,
                    expected_combo = expected_combo,
                    absorb_ids = exception and exception.absorb_ids or nil,
                    source = "exception",
                    ignore_combo_check = not absorb_requires_combo(exception)
                }
            end
            return {
                matched = false,
                block_reason = "combo_not_reached",
                actual_action_id = recent_id,
                recent_index = i,
                combo_count = combo_count,
                expected_combo = expected_combo,
                absorb_ids = exception and exception.absorb_ids or nil
            }
        end
    end

    return { matched = false, block_reason = "absorb_id_not_recent", absorb_ids = exception and exception.absorb_ids or nil }
end

function CharacterRules.match_current_absorb_confirmation(character_rules, common_rules, expected, action_id, combo_count, character_name)
    if not expected then return { matched = false, block_reason = "missing_expected" } end

    local exception = CharacterRules.get_exception(character_rules, common_rules, expected.id)
    local absorb_ids = parse_absorb_ids(exception)
    local is_honda = character_name == "EHonda" or character_name == "Honda"
    local match_reason = is_honda and "ehonda_current_absorb" or "exception_current_absorb"

    local current_id = tonumber(action_id)
    local is_exception_absorb = current_id and absorb_ids and absorb_ids[current_id]
    if not current_id or not is_exception_absorb then
        return { matched = false, block_reason = "current_id_not_absorbed", absorb_ids = exception and exception.absorb_ids or nil }
    end

    local expected_combo = tonumber(expected.expected_combo)
    if expected_combo == nil then return { matched = false, block_reason = "missing_expected_combo" } end

    local current_combo = tonumber(combo_count) or 0
    local combo_ok = (not absorb_requires_combo(exception)) or current_combo >= expected_combo
    if not combo_ok then
        return {
            matched = false,
            block_reason = "combo_not_reached",
            actual_action_id = current_id,
            combo_count = current_combo,
            expected_combo = expected_combo,
            absorb_ids = exception and exception.absorb_ids or nil
        }
    end

    return {
        matched = true,
        actual_action_id = current_id,
        match_reason = match_reason,
        combo_count = current_combo,
        expected_id = expected.id,
        expected_combo = expected_combo,
        absorb_ids = exception and exception.absorb_ids or nil,
        source = "current_non_intentional_absorb",
        motion = "Unknown",
        real_input = "None",
        ignore_combo_check = not absorb_requires_combo(exception)
    }
end

function CharacterRules.apply_runtime_overrides(character_name, action_id, exception, log)
    if character_name == "Cammy" and (action_id == 908 or action_id == 922) then
        if #log > 0 and (log[1].id == 652 or log[1].id == 653 or log[1].id == 926) then
            if not exception then exception = {} end
            exception.force = true
        end
    end
    return exception
end

return CharacterRules
