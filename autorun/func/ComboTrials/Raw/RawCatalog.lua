-- RawCatalog.lua
-- Stage 1 raw data access layer for the SF6ACBCM current-only artifact
-- (`sf6.raw.current.v1`). This module is a Fact Access Layer, not a semantic
-- core: it never applies owner/alias/absorb/group/AC/compatibility rules,
-- never invents command notation or presentation text, and never merges
-- profiles across triggers.
--
-- Profile command references are plural. `command_definition_uids` and
-- `variant_indexes` are parallel over the referenced command variant array;
-- `direct_command_tokens` is an independent direct-command token list (a
-- button-only row can carry a token with zero definition references). The
-- old singular `command_definition_uid`, `variant_index` and `command_token`
-- fields are rejected; `command_index` (when present) is only a raw BCM
-- pointer index and is never used as a variant selector.
--
-- Loads are fail-closed. The loader reads the manifest bytes, decodes them,
-- recomputes the manifest root digest over the sealed character set, then
-- reads the requested character artifact bytes and verifies size and SHA-256
-- against the manifest before decoding. Any contract, schema, count or build
-- violation returns an explicit status.code and no partial data.

local RawCatalog = {
    name = "ComboTrials.Raw.RawCatalog",
    SCHEMA = "sf6.raw.current.v1",
    MANIFEST_SCHEMA = "sf6.raw.current-manifest.v1",
    ALGORITHM_VERSION = "raw-current.v1",
    AUTHORITY = "current_full_bcm_atomic_fact_only",
    DIRECTORY = "TrainingComboTrials_data/raw/current",
    MANIFEST_FILE = "raw-current-manifest.v1.json",
    DIRECT_BINDING_STATUS = "DIRECT",
    NO_DIRECT_BCM_BINDING = "NO_DIRECT_BCM_BINDING",
    PROFILE_NAMES = { norm = true, easy = true, sprt = true, supr = true },
}

local RawSha256 = require("func/ComboTrials/Raw/RawSha256")

local ARTIFACT_KEYS = {
    schema = true, algorithm_version = true, authority = true,
    auto_approved = true, build = true, source = true, character = true,
    action_catalog = true, command_catalog = true, counts = true,
}
local MANIFEST_KEYS = {
    schema = true, algorithm_version = true, authority = true,
    auto_approved = true, build = true, generator = true, source = true,
    characters = true, character_coverage = true, totals = true,
    root_digest = true, generated_at = true,
}
local BUILD_KEYS = {
    build_uid = true, display_version = true, game_version = true,
    captured_at = true, exporter = true,
}
local EXPORTER_KEYS = { name = true, version = true, commit = true }
local ARTIFACT_SOURCE_KEYS = { ac = true, bcm = true }
local SOURCE_FILE_KEYS = { file = true, schema = true, sha256 = true, bytes = true }
local ARTIFACT_SOURCE_FILE_KEYS = {
    file = true, schema = true, sha256 = true, bytes = true, capture = true,
}
local CHARACTER_KEYS = { fighter_id = true, character = true }
local COUNT_KEYS = {
    actions = true, ac_edges = true, bcm_triggers = true,
    bcm_commands = true, bcm_command_definitions = true, bcm_inputs = true,
}
local COUNT_FIELDS = {
    "actions", "ac_edges", "bcm_triggers",
    "bcm_commands", "bcm_command_definitions", "bcm_inputs",
}
local ACTION_KEYS = {
    raw_action_uid = true, source_scope = true, style_index = true,
    resource_index = true, action_id = true, dictionary_index = true,
    dictionary_key = true, dictionary_hash_code = true,
    root_object_id = true, root_fields = true, raw_locator = true,
}
local EDGE_KEYS = {
    raw_edge_uid = true, source_raw_action_uid = true,
    target_action_id = true,
    branch_type = true, attr = true, action_frame = true, trigger_id = true,
    params = true, ordinal = true, raw_evidence = true,
}
local DEFINITION_KEYS = {
    definition_uid = true, command_no = true, variant_index = true,
    charge_bit = true, max_frame = true, total_frame = true,
    raw_locator = true, inputs = true,
}
local INPUT_KEYS = {
    input_uid = true, ordinal = true, direction = true, raw_mask = true,
    frame_count = true, input_type = true, charge_id = true,
    charge_release = true,
}
-- The old singular command fields are deliberately absent: they are
-- forbidden keys under this contract, not optional legacy facts.
local PROFILE_KEYS = {
    raw_command_uid = true, profile_name = true, command_no = true,
    command_index = true, command_definition_uids = true,
    variant_indexes = true, direct_command_tokens = true, ng_flag = true,
    enabled = true, button_mask = true, button_condition = true,
    dc_exc_flags = true, ng_key_flags = true, preceding_time = true,
    raw_profile = true, raw_locator = true,
}
local TRIGGER_KEYS = {
    raw_trigger_uid = true, trigger_index = true, action_id = true,
    raw_object_id = true, conditions = true, raw_locator = true,
    profiles = true,
}
local MANIFEST_CHARACTER_KEYS = {
    fighter_id = true, character = true, file = true, sha256 = true,
    bytes = true, counts = true, source = true,
}
local CHARACTER_SOURCE_KEYS = { ac = true, bcm = true }
local MANIFEST_SOURCE_KEYS = { manifest = true }
local COVERAGE_KEYS = { expected = true, generated = true, failed = true }
local GENERATOR_KEYS = { name = true, version = true }
local ACTION_CATALOG_KEYS = { actions = true, edges = true }
local COMMAND_CATALOG_KEYS = { definitions = true, triggers = true }

-- Single active-character cache: at most one catalog and one manifest are
-- retained at any time so random character visits cannot accumulate 31
-- multi-megabyte artifacts in memory.
local CACHE = {}
local MANIFEST_CACHE = {}

local TELEMETRY
local function telemetry()
    if TELEMETRY == nil then
        TELEMETRY = require("func/ComboTrials/Telemetry")
    end
    return TELEMETRY
end

local function failure(code, message)
    return nil, {
        ok = false,
        code = code,
        message = tostring(message),
    }
end

local function plain_copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = plain_copy(item) end
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

local function non_empty_string(value)
    return type(value) == "string" and value ~= ""
end

local function is_plain_filename(value)
    return non_empty_string(value)
        and not value:find("/", 1, true)
        and not value:find("\\", 1, true)
        and not value:find("..", 1, true)
end

local function is_iso_datetime(value)
    if type(value) ~= "string" then return false end
    if value:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d")
        and value:sub(-1) == "Z" then
        return true
    end
    return value:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d[%+%-]%d%d:%d%d$")
        ~= nil
end

local function is_uid(value)
    return type(value) == "string"
        and #value >= 1 and #value <= 160
        and value:match("^[A-Za-z0-9_.:-]+$") ~= nil
end

local function is_sha256(value)
    return type(value) == "string" and #value == 64
        and value:match("^[0-9a-f]+$") ~= nil
end

local function is_integer(value, minimum)
    if type(value) ~= "number" or value % 1 ~= 0 then return false end
    if minimum ~= nil and value < minimum then return false end
    return true
end

local function is_action_id(value)
    return is_integer(value, 0) and value <= 10000000
end

local function is_boolean(value)
    return type(value) == "boolean"
end

local function is_nullable_boolean(value)
    return value == nil or type(value) == "boolean"
end

local function is_nullable_integer(value)
    return value == nil or is_integer(value)
end

local function is_nullable_string(value)
    return value == nil or type(value) == "string"
end

local function is_nullable_uid(value)
    return value == nil or is_uid(value)
end

local function validate_array(value, item_kind, validate_item)
    if type(value) ~= "table" then
        return item_kind .. " must be an array"
    end
    local count = 0
    for index, item in ipairs(value) do
        local err = validate_item(item, index)
        if err then
            return item_kind .. "[" .. index .. "]: " .. err
        end
        count = index
    end
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > count then
            return item_kind .. " has non-sequential keys"
        end
    end
    return nil
end

-- Rejects unknown keys so injected semantic fields (move_uid, presentation,
-- normalized_notation, legacy overrides, ...) can never ride along as facts.
-- Nullable fields may decode from JSON null to Lua nil, so presence of every
-- allowed key is not required; the individual validators enforce the fields
-- that are mandatory in the sealed contract.
local function validate_strict_object(value, name, allowed)
    if type(value) ~= "table" then return name .. " must be an object" end
    for key in pairs(value) do
        if not allowed[key] then
            return name .. " has forbidden key " .. tostring(key)
        end
    end
    return nil
end

local function validate_counts(counts)
    if type(counts) ~= "table" then return "counts must be an object" end
    local err = validate_strict_object(counts, "counts", COUNT_KEYS)
    if err then return err end
    for _, field in ipairs(COUNT_FIELDS) do
        if not is_integer(counts[field], 0) then
            return "counts." .. field .. " invalid"
        end
    end
    return nil
end

local function validate_build(build)
    if type(build) ~= "table" then return "build must be an object" end
    local err = validate_strict_object(build, "build", BUILD_KEYS)
    if err then return err end
    if not is_uid(build.build_uid) then return "build.build_uid invalid" end
    if not non_empty_string(build.display_version) then
        return "build.display_version invalid"
    end
    if not non_empty_string(build.game_version) then
        return "build.game_version invalid"
    end
    if not is_iso_datetime(build.captured_at) then
        return "build.captured_at invalid"
    end
    if type(build.exporter) ~= "table" then return "build.exporter invalid" end
    err = validate_strict_object(build.exporter, "build.exporter", EXPORTER_KEYS)
    if err then return err end
    if not non_empty_string(build.exporter.name)
        or not non_empty_string(build.exporter.version)
        or not non_empty_string(build.exporter.commit) then
        return "build.exporter fields must be non-empty strings"
    end
    return nil
end

local function validate_source_file(value, name, with_capture)
    if type(value) ~= "table" then return name .. " must be an object" end
    local err = validate_strict_object(
        value, name, with_capture and ARTIFACT_SOURCE_FILE_KEYS or SOURCE_FILE_KEYS)
    if err then return err end
    if not non_empty_string(value.file) then return name .. ".file invalid" end
    if not non_empty_string(value.schema) then return name .. ".schema invalid" end
    if not is_sha256(value.sha256) then return name .. ".sha256 invalid" end
    if not is_integer(value.bytes, 1) then return name .. ".bytes invalid" end
    if with_capture and value.capture == nil then
        return name .. ".capture missing"
    end
    return nil
end

local function validate_artifact_source(source)
    if type(source) ~= "table" then return "source must be an object" end
    local err = validate_strict_object(source, "source", ARTIFACT_SOURCE_KEYS)
    if err then return err end
    err = validate_source_file(source.ac, "source.ac", true)
    if err then return err end
    err = validate_source_file(source.bcm, "source.bcm", true)
    if err then return err end
    return nil
end

local function validate_character(character)
    if type(character) ~= "table" then return "character must be an object" end
    local err = validate_strict_object(character, "character", CHARACTER_KEYS)
    if err then return err end
    if not is_integer(character.fighter_id, 1) then
        return "character.fighter_id invalid"
    end
    if not non_empty_string(character.character) then
        return "character.character invalid"
    end
    return nil
end

local function validate_action(action)
    if type(action) ~= "table" then return "action must be an object" end
    local err = validate_strict_object(action, "action", ACTION_KEYS)
    if err then return err end
    if not is_uid(action.raw_action_uid) then return "raw_action_uid invalid" end
    if action.source_scope ~= "character" and action.source_scope ~= "common" then
        return "source_scope invalid"
    end
    if not is_integer(action.style_index, 0) then return "style_index invalid" end
    if not is_integer(action.resource_index, 0) then
        return "resource_index invalid"
    end
    if not is_action_id(action.action_id) then return "action_id invalid" end
    if not is_nullable_integer(action.dictionary_index) then
        return "dictionary_index invalid"
    end
    if not is_nullable_string(action.dictionary_key) then
        return "dictionary_key invalid"
    end
    if not is_nullable_string(action.dictionary_hash_code) then
        return "dictionary_hash_code invalid"
    end
    if not is_nullable_integer(action.root_object_id) then
        return "root_object_id invalid"
    end
    if action.root_fields == nil then return "root_fields missing" end
    if action.raw_locator == nil then return "raw_locator missing" end
    return nil
end

local function validate_edge(edge)
    if type(edge) ~= "table" then return "edge must be an object" end
    local err = validate_strict_object(edge, "edge", EDGE_KEYS)
    if err then return err end
    if not is_uid(edge.raw_edge_uid) then return "raw_edge_uid invalid" end
    if not is_uid(edge.source_raw_action_uid) then
        return "source_raw_action_uid invalid"
    end
    if not is_action_id(edge.target_action_id) then
        return "target_action_id invalid"
    end
    if not is_nullable_integer(edge.branch_type) then
        return "branch_type invalid"
    end
    if not is_nullable_integer(edge.attr) then return "attr invalid" end
    if not is_nullable_integer(edge.action_frame) then
        return "action_frame invalid"
    end
    if not is_nullable_integer(edge.trigger_id) then
        return "trigger_id invalid"
    end
    local params_err = validate_array(edge.params, "params", function(value)
        if value ~= nil and not is_integer(value) then
            return "param must be an integer or null"
        end
        return nil
    end)
    if params_err then return params_err end
    if not is_integer(edge.ordinal, 0) then return "ordinal invalid" end
    if edge.raw_evidence == nil then return "raw_evidence missing" end
    return nil
end

local function validate_input(input)
    if type(input) ~= "table" then return "input must be an object" end
    local err = validate_strict_object(input, "input", INPUT_KEYS)
    if err then return err end
    if not is_uid(input.input_uid) then return "input_uid invalid" end
    if not is_integer(input.ordinal, 0) then return "ordinal invalid" end
    if type(input.direction) ~= "string" then return "direction invalid" end
    if type(input.raw_mask) ~= "string" then return "raw_mask invalid" end
    if not is_nullable_integer(input.frame_count) then
        return "frame_count invalid"
    end
    if not is_nullable_integer(input.input_type) then
        return "input_type invalid"
    end
    if not is_nullable_string(input.charge_id) then
        return "charge_id invalid"
    end
    if not is_boolean(input.charge_release) then
        return "charge_release invalid"
    end
    return nil
end

local function validate_definition(definition)
    if type(definition) ~= "table" then return "definition must be an object" end
    local err = validate_strict_object(definition, "definition", DEFINITION_KEYS)
    if err then return err end
    if not is_uid(definition.definition_uid) then return "definition_uid invalid" end
    if not is_integer(definition.command_no, 0) then return "command_no invalid" end
    if not is_integer(definition.variant_index, 0) then
        return "variant_index invalid"
    end
    if type(definition.charge_bit) ~= "string" then
        return "charge_bit invalid"
    end
    if not is_nullable_integer(definition.max_frame) then
        return "max_frame invalid"
    end
    if not is_nullable_integer(definition.total_frame) then
        return "total_frame invalid"
    end
    if definition.raw_locator == nil then return "raw_locator missing" end
    local input_uids = {}
    err = validate_array(definition.inputs, "inputs", function(input)
        local item_err = validate_input(input)
        if item_err then return item_err end
        if input_uids[input.input_uid] then
            return "duplicate input_uid " .. input.input_uid
        end
        input_uids[input.input_uid] = true
        return nil
    end)
    if err then return err end
    return nil
end

local function validate_profile(profile)
    if type(profile) ~= "table" then return "profile must be an object" end
    local err = validate_strict_object(profile, "profile", PROFILE_KEYS)
    if err then return err end
    if not is_uid(profile.raw_command_uid) then return "raw_command_uid invalid" end
    if type(profile.profile_name) ~= "string"
        or not RawCatalog.PROFILE_NAMES[profile.profile_name] then
        return "profile_name invalid"
    end
    -- command_no / command_index are raw BCM pointer facts only. Resolution
    -- and variant selection always use the parallel command arrays below.
    if not is_nullable_integer(profile.command_no) then
        return "command_no invalid"
    end
    if not is_nullable_integer(profile.command_index) then
        return "command_index invalid"
    end
    err = validate_array(profile.command_definition_uids,
        "command_definition_uids", function(uid)
            if not is_uid(uid) then return "definition uid invalid" end
            return nil
        end)
    if err then return err end
    err = validate_array(profile.variant_indexes, "variant_indexes", function(index)
        if not is_integer(index, 0) then return "variant index invalid" end
        return nil
    end)
    if err then return err end
    err = validate_array(profile.direct_command_tokens,
        "direct_command_tokens", function(token)
            if type(token) ~= "string" then return "command token invalid" end
            return nil
        end)
    if err then return err end
    if #profile.command_definition_uids ~= #profile.variant_indexes then
        return "command_definition_uids and variant_indexes must have equal length"
    end
    if not is_nullable_boolean(profile.ng_flag) then return "ng_flag invalid" end
    if not is_boolean(profile.enabled) then return "enabled invalid" end
    if type(profile.button_mask) ~= "string" then return "button_mask invalid" end
    if type(profile.button_condition) ~= "string" then
        return "button_condition invalid"
    end
    if type(profile.dc_exc_flags) ~= "string" then
        return "dc_exc_flags invalid"
    end
    if type(profile.ng_key_flags) ~= "string" then
        return "ng_key_flags invalid"
    end
    if not is_nullable_integer(profile.preceding_time) then
        return "preceding_time invalid"
    end
    if profile.raw_profile == nil then return "raw_profile missing" end
    if profile.raw_locator == nil then return "raw_locator missing" end
    return nil
end

local function validate_trigger(trigger)
    if type(trigger) ~= "table" then return "trigger must be an object" end
    local err = validate_strict_object(trigger, "trigger", TRIGGER_KEYS)
    if err then return err end
    if not is_uid(trigger.raw_trigger_uid) then
        return "raw_trigger_uid invalid"
    end
    if not is_integer(trigger.trigger_index, 0) then
        return "trigger_index invalid"
    end
    if not is_action_id(trigger.action_id) then return "action_id invalid" end
    if not is_nullable_integer(trigger.raw_object_id) then
        return "raw_object_id invalid"
    end
    if trigger.conditions == nil then return "conditions missing" end
    if trigger.raw_locator == nil then return "raw_locator missing" end
    err = validate_array(trigger.profiles, "profiles", validate_profile)
    if err then return err end
    if #trigger.profiles == 0 then return "trigger must have at least one profile" end
    return nil
end

local function validate_envelope(artifact)
    if type(artifact) ~= "table" then
        return "invalid_artifact", "artifact must be an object"
    end
    local err = validate_strict_object(artifact, "artifact", ARTIFACT_KEYS)
    if err then return "invalid_artifact", err end
    if artifact.schema ~= RawCatalog.SCHEMA then
        return "unsupported_schema", tostring(artifact.schema) .. " is not " .. RawCatalog.SCHEMA
    end
    if artifact.algorithm_version ~= RawCatalog.ALGORITHM_VERSION then
        return "unsupported_algorithm",
            tostring(artifact.algorithm_version) .. " is not " .. RawCatalog.ALGORITHM_VERSION
    end
    if artifact.authority ~= RawCatalog.AUTHORITY then
        return "authority_mismatch",
            tostring(artifact.authority) .. " is not " .. RawCatalog.AUTHORITY
    end
    if artifact.auto_approved ~= false then
        return "auto_approved_violation", "auto_approved must be false"
    end
    return nil
end

local function validate_artifact(artifact, expected_fighter_id)
    local code, message = validate_envelope(artifact)
    if code then return code, message end
    local err = validate_build(artifact.build)
    if err then return "invalid_artifact", "build: " .. err end
    err = validate_artifact_source(artifact.source)
    if err then return "invalid_artifact", "source: " .. err end
    err = validate_character(artifact.character)
    if err then return "invalid_artifact", "character: " .. err end
    if expected_fighter_id ~= nil and artifact.character.fighter_id ~= expected_fighter_id then
        return "character_mismatch",
            "artifact fighter_id " .. artifact.character.fighter_id
                .. " does not match requested " .. expected_fighter_id
    end
    err = validate_strict_object(artifact.action_catalog,
        "action_catalog", ACTION_CATALOG_KEYS)
    if err then return "invalid_artifact", err end
    err = validate_strict_object(artifact.command_catalog,
        "command_catalog", COMMAND_CATALOG_KEYS)
    if err then return "invalid_artifact", err end
    err = validate_counts(artifact.counts)
    if err then return "invalid_counts", err end

    local action_uids = {}
    local actions_count = 0
    err = validate_array(artifact.action_catalog.actions, "actions", function(action)
        local item_err = validate_action(action)
        if item_err then return item_err end
        if action_uids[action.raw_action_uid] then
            return "duplicate raw_action_uid " .. action.raw_action_uid
        end
        action_uids[action.raw_action_uid] = true
        actions_count = actions_count + 1
        return nil
    end)
    if err then return "invalid_artifact", "action_catalog." .. err end

    local edge_uids = {}
    local edges_count = 0
    err = validate_array(artifact.action_catalog.edges, "edges", function(edge)
        local item_err = validate_edge(edge)
        if item_err then return item_err end
        if edge_uids[edge.raw_edge_uid] then
            return "duplicate raw_edge_uid " .. edge.raw_edge_uid
        end
        edge_uids[edge.raw_edge_uid] = true
        if action_uids[edge.source_raw_action_uid] == nil then
            return "edge source action is missing: " .. edge.source_raw_action_uid
        end
        edges_count = edges_count + 1
        return nil
    end)
    if err then return "invalid_artifact", "action_catalog." .. err end

    local definition_uids = {}
    local definition_variants = {}
    local definition_command_nos = {}
    local definitions_count = 0
    local bcm_inputs = 0
    err = validate_array(artifact.command_catalog.definitions,
        "definitions", function(definition)
            local item_err = validate_definition(definition)
            if item_err then return item_err end
            if definition_uids[definition.definition_uid] then
                return "duplicate definition_uid " .. definition.definition_uid
            end
            definition_uids[definition.definition_uid] = true
            definition_variants[definition.definition_uid] = definition.variant_index
            definition_command_nos[definition.definition_uid] = definition.command_no
            definitions_count = definitions_count + 1
            bcm_inputs = bcm_inputs + #definition.inputs
            return nil
        end)
    if err then return "invalid_artifact", "command_catalog." .. err end

    local trigger_uids = {}
    local bcm_commands = 0
    err = validate_array(artifact.command_catalog.triggers,
        "triggers", function(trigger)
            local item_err = validate_trigger(trigger)
            if item_err then return item_err end
            if trigger_uids[trigger.raw_trigger_uid] then
                return "duplicate raw_trigger_uid " .. trigger.raw_trigger_uid
            end
            trigger_uids[trigger.raw_trigger_uid] = true
            local profile_uids = {}
            for _, profile in ipairs(trigger.profiles) do
                if profile_uids[profile.raw_command_uid] then
                    return "duplicate raw_command_uid " .. profile.raw_command_uid
                        .. " in trigger " .. trigger.raw_trigger_uid
                end
                profile_uids[profile.raw_command_uid] = true
                for index, ref_uid in ipairs(profile.command_definition_uids) do
                    if definition_uids[ref_uid] == nil then
                        return "profile command definition is missing: " .. ref_uid
                    end
                    local variant_index = profile.variant_indexes[index]
                    if definition_variants[ref_uid] ~= variant_index then
                        return "profile variant mismatch for " .. ref_uid
                            .. " (profile " .. variant_index
                            .. " != definition " .. definition_variants[ref_uid] .. ")"
                    end
                    if definition_command_nos[ref_uid] ~= profile.command_no then
                        return "profile command_no mismatch for " .. ref_uid
                    end
                end
                bcm_commands = bcm_commands + 1
            end
            return nil
        end)
    if err then
        if err:find("profile variant mismatch", 1, true) then
            return "profile_variant_mismatch", "command_catalog." .. err
        end
        return "invalid_artifact", "command_catalog." .. err
    end

    if artifact.counts.actions ~= actions_count then
        return "count_mismatch", "counts.actions does not match action array"
    end
    if artifact.counts.ac_edges ~= edges_count then
        return "count_mismatch", "counts.ac_edges does not match edge array"
    end
    if artifact.counts.bcm_triggers ~= #artifact.command_catalog.triggers then
        return "count_mismatch", "counts.bcm_triggers does not match trigger array"
    end
    if artifact.counts.bcm_commands ~= bcm_commands then
        return "count_mismatch", "counts.bcm_commands does not match profile rows"
    end
    if artifact.counts.bcm_command_definitions ~= definitions_count then
        return "count_mismatch", "counts.bcm_command_definitions does not match definitions"
    end
    if artifact.counts.bcm_inputs ~= bcm_inputs then
        return "count_mismatch", "counts.bcm_inputs does not match definition inputs"
    end
    return nil
end

local function validate_manifest_envelope(manifest)
    if type(manifest) ~= "table" then
        return "invalid_manifest", "manifest must be an object"
    end
    local err = validate_strict_object(manifest, "manifest", MANIFEST_KEYS)
    if err then return "invalid_manifest", err end
    if manifest.schema ~= RawCatalog.MANIFEST_SCHEMA then
        return "unsupported_manifest_schema",
            tostring(manifest.schema) .. " is not " .. RawCatalog.MANIFEST_SCHEMA
    end
    if manifest.algorithm_version ~= RawCatalog.ALGORITHM_VERSION then
        return "unsupported_manifest_algorithm",
            tostring(manifest.algorithm_version) .. " is not " .. RawCatalog.ALGORITHM_VERSION
    end
    if manifest.authority ~= RawCatalog.AUTHORITY then
        return "manifest_authority_mismatch",
            tostring(manifest.authority) .. " is not " .. RawCatalog.AUTHORITY
    end
    if manifest.auto_approved ~= false then
        return "manifest_auto_approved_violation", "auto_approved must be false"
    end
    if not is_sha256(manifest.root_digest) then
        return "invalid_manifest", "manifest.root_digest invalid"
    end
    return nil
end

local function validate_manifest_character(entry, artifact, expected_fighter_id, file)
    if type(entry) ~= "table" then
        return "manifest_character_missing",
            "manifest has no entry for fighter_id " .. expected_fighter_id
    end
    if entry.fighter_id ~= expected_fighter_id then
        return "manifest_character_mismatch",
            "manifest fighter_id " .. tostring(entry.fighter_id)
                .. " does not match requested " .. expected_fighter_id
    end
    if entry.file ~= file then
        return "manifest_file_mismatch",
            "manifest binds " .. tostring(entry.file) .. " but loader was given " .. file
    end
    if entry.character ~= artifact.character.character then
        return "manifest_character_mismatch",
            "manifest character does not match artifact character"
    end
    if not is_sha256(entry.sha256) or not is_integer(entry.bytes, 1) then
        return "invalid_manifest", "manifest character sha256/bytes invalid"
    end
    for _, field in ipairs(COUNT_FIELDS) do
        if entry.counts[field] ~= artifact.counts[field] then
            return "manifest_count_mismatch",
                "manifest counts." .. field .. " does not match artifact"
        end
    end
    if not deep_equal(entry.source, artifact.source) then
        return "manifest_source_mismatch",
            "manifest source descriptors do not match artifact source"
    end
    return nil
end

-- Mirrors SF6ACBCM deriveRawCurrentRootDigest: SHA-256 over canonical JSON of
-- the explicit scalar manifest envelope plus characters sorted by fighter_id.
-- Telemetry.encode_json sorts object keys exactly like canonical JSON.
local function derive_root_digest(manifest)
    local characters = {}
    for _, entry in ipairs(manifest.characters) do
        characters[#characters + 1] = {
            fighter_id = entry.fighter_id,
            character = entry.character,
            file = entry.file,
            sha256 = entry.sha256,
            bytes = entry.bytes,
            counts = entry.counts,
            source = {
                ac = {
                    file = entry.source.ac.file,
                    schema = entry.source.ac.schema,
                    sha256 = entry.source.ac.sha256,
                    bytes = entry.source.ac.bytes,
                },
                bcm = {
                    file = entry.source.bcm.file,
                    schema = entry.source.bcm.schema,
                    sha256 = entry.source.bcm.sha256,
                    bytes = entry.source.bcm.bytes,
                },
            },
        }
    end
    table.sort(characters, function(left, right)
        return left.fighter_id < right.fighter_id
    end)
    local payload = {
        schema = manifest.schema,
        algorithm_version = manifest.algorithm_version,
        authority = manifest.authority,
        auto_approved = manifest.auto_approved,
        build = {
            build_uid = manifest.build.build_uid,
            display_version = manifest.build.display_version,
            game_version = manifest.build.game_version,
            captured_at = manifest.build.captured_at,
            exporter = {
                name = manifest.build.exporter.name,
                version = manifest.build.exporter.version,
                commit = manifest.build.exporter.commit,
            },
        },
        generator = {
            name = manifest.generator.name,
            version = manifest.generator.version,
        },
        source = {
            manifest = {
                file = manifest.source.manifest.file,
                schema = manifest.source.manifest.schema,
                sha256 = manifest.source.manifest.sha256,
                bytes = manifest.source.manifest.bytes,
            },
        },
        generated_at = manifest.generated_at,
        character_coverage = {
            expected = manifest.character_coverage.expected,
            generated = manifest.character_coverage.generated,
            failed_count = #manifest.character_coverage.failed,
        },
        totals = manifest.totals,
        characters = characters,
    }
    return telemetry().sha256(telemetry().encode_json(payload))
end

local function validate_manifest(manifest)
    local code, message = validate_manifest_envelope(manifest)
    if code then return code, message end
    local err = validate_build(manifest.build)
    if err then return "invalid_manifest", "build: " .. err end

    if type(manifest.generator) ~= "table" then
        return "invalid_manifest", "generator must be an object"
    end
    err = validate_strict_object(manifest.generator, "generator", GENERATOR_KEYS)
    if err then return "invalid_manifest", err end
    if not non_empty_string(manifest.generator.name) then
        return "invalid_manifest", "generator.name invalid"
    end
    if manifest.generator.version ~= RawCatalog.ALGORITHM_VERSION then
        return "invalid_manifest", "generator.version invalid"
    end

    if type(manifest.source) ~= "table" then
        return "invalid_manifest", "source must be an object"
    end
    err = validate_strict_object(manifest.source, "source", MANIFEST_SOURCE_KEYS)
    if err then return "invalid_manifest", err end
    err = validate_source_file(manifest.source.manifest, "source.manifest", false)
    if err then return "invalid_manifest", err end

    local fighter_ids = {}
    local names = {}
    local files = {}
    local totals = {}
    for _, field in ipairs(COUNT_FIELDS) do totals[field] = 0 end
    err = validate_array(manifest.characters, "characters", function(entry)
        if type(entry) ~= "table" then return "character must be an object" end
        local item_err = validate_strict_object(
            entry, "character", MANIFEST_CHARACTER_KEYS)
        if item_err then return item_err end
        if not is_integer(entry.fighter_id, 1) then
            return "fighter_id invalid"
        end
        if not non_empty_string(entry.character) then
            return "character invalid"
        end
        if not is_plain_filename(entry.file) then return "file invalid" end
        if not is_sha256(entry.sha256) or not is_integer(entry.bytes, 1) then
            return "sha256/bytes invalid"
        end
        if fighter_ids[entry.fighter_id] then
            return "duplicate fighter_id " .. entry.fighter_id
        end
        if names[entry.character] then
            return "duplicate character " .. entry.character
        end
        if files[entry.file] then return "duplicate artifact file " .. entry.file end
        fighter_ids[entry.fighter_id] = true
        names[entry.character] = true
        files[entry.file] = true
        item_err = validate_counts(entry.counts)
        if item_err then return item_err end
        for _, field in ipairs(COUNT_FIELDS) do
            totals[field] = totals[field] + entry.counts[field]
        end
        if type(entry.source) ~= "table" then
            return "source must be an object"
        end
        item_err = validate_strict_object(
            entry.source, "character.source", CHARACTER_SOURCE_KEYS)
        if item_err then return item_err end
        item_err = validate_source_file(entry.source.ac, "character.source.ac", true)
        if item_err then return item_err end
        item_err = validate_source_file(entry.source.bcm, "character.source.bcm", true)
        if item_err then return item_err end
        return nil
    end)
    if err then return "invalid_manifest", "characters: " .. err end

    local coverage = manifest.character_coverage
    if type(coverage) ~= "table" then
        return "invalid_manifest", "character_coverage must be an object"
    end
    err = validate_strict_object(coverage, "character_coverage", COVERAGE_KEYS)
    if err then return "invalid_manifest", err end
    if not is_integer(coverage.expected, 1) or not is_integer(coverage.generated, 1) then
        return "invalid_manifest", "character_coverage counts invalid"
    end
    err = validate_array(coverage.failed, "character_coverage.failed", function(value)
        if type(value) ~= "string" then return "failed entry invalid" end
        return nil
    end)
    if err then return "invalid_manifest", err end
    if coverage.expected ~= #manifest.characters then
        return "coverage_mismatch", "expected coverage does not match character array"
    end
    if coverage.generated ~= #manifest.characters then
        return "coverage_mismatch", "generated coverage does not match character array"
    end
    if #coverage.failed > 0 then
        return "coverage_mismatch", "manifest must not be sealed with failed characters"
    end

    err = validate_counts(manifest.totals)
    if err then return "invalid_manifest", "totals: " .. err end
    for _, field in ipairs(COUNT_FIELDS) do
        if manifest.totals[field] ~= totals[field] then
            return "manifest_totals_mismatch",
                "manifest totals." .. field .. " does not match character sums"
        end
    end

    if derive_root_digest(manifest) ~= manifest.root_digest then
        return "manifest_root_digest_mismatch",
            "manifest root_digest does not match its character set"
    end
    if manifest.generated_at ~= manifest.build.captured_at then
        return "manifest_generated_at_mismatch",
            "manifest generated_at must equal build captured_at"
    end
    return nil
end

local function default_read_file(path)
    if not fs or type(fs.read) ~= "function" then return nil end
    local ok, value = pcall(fs.read, path)
    if not ok then return nil end
    return type(value) == "string" and value or nil
end

local function default_decode(raw)
    if not json or type(json.load_string) ~= "function" then return nil end
    local ok, value = pcall(json.load_string, raw)
    if not ok then return nil end
    return type(value) == "table" and value or nil
end

local function default_sha256(raw)
    return RawSha256.digest(raw)
end

local function join_path(dir, file)
    return (dir:gsub("[/\\]+$", "")) .. "/" .. file
end

local function raw_filename(fighter_id)
    return "f" .. string.format("%03d", fighter_id) .. "-raw-current.v1.json"
end

local Catalog = {}
local CATALOG_STATE = setmetatable({}, { __mode = "k" })
Catalog.__index = Catalog
Catalog.__newindex = function()
    error("RawCatalog is read-only", 2)
end
Catalog.__metatable = false

local function immutable_view(state, value)
    if type(value) ~= "table" then return value end
    local cached = state.views[value]
    if cached ~= nil then return cached end
    local proxy = {}
    state.views[value] = proxy
    return setmetatable(proxy, {
        __index = function(_, key)
            return immutable_view(state, value[key])
        end,
        __newindex = function()
            error("RawCatalog data is read-only", 2)
        end,
        __len = function() return #value end,
        __pairs = function()
            local function next_value(_, key)
                local next_key, item = next(value, key)
                if next_key ~= nil then
                    return next_key, immutable_view(state, item)
                end
            end
            return next_value, proxy, nil
        end,
        __metatable = false,
    })
end

local function catalog_state(catalog)
    return assert(CATALOG_STATE[catalog], "invalid RawCatalog instance")
end

function Catalog:get_build_info()
    local state = catalog_state(self)
    return immutable_view(state, {
        build_uid = state.artifact.build.build_uid,
        display_version = state.artifact.build.display_version,
    })
end

function Catalog:get_character()
    local state = catalog_state(self)
    return immutable_view(state, {
        fighter_id = state.artifact.character.fighter_id,
        character = state.artifact.character.character,
    })
end

function Catalog:get_counts()
    local state = catalog_state(self)
    return immutable_view(state, state.artifact.counts)
end

function Catalog:get_file()
    return catalog_state(self).file
end

function Catalog:get_read_count()
    return catalog_state(self).read_count
end

-- Returns every direct BCM binding for the action, preserving trigger order,
-- profile order, duplicates, disabled rows and every profile variant.
-- Unknown action ids return (nil, RawCatalog.NO_DIRECT_BCM_BINDING).
function Catalog:get_bindings(action_id)
    local state = catalog_state(self)
    if not is_action_id(action_id) then
        return nil, RawCatalog.NO_DIRECT_BCM_BINDING
    end
    local bindings = state.bindings_by_action[action_id]
    if bindings == nil then
        return nil, RawCatalog.NO_DIRECT_BCM_BINDING
    end
    return immutable_view(state, bindings), RawCatalog.DIRECT_BINDING_STATUS
end

function Catalog:get_bindings_snapshot(action_id)
    local bindings, status = self:get_bindings(action_id)
    return bindings and plain_copy(bindings) or nil, status
end

function Catalog:has_direct_binding(action_id)
    if not is_action_id(action_id) then return false end
    return catalog_state(self).bindings_by_action[action_id] ~= nil
end

function Catalog:get_definition(definition_uid)
    local state = catalog_state(self)
    if not is_uid(definition_uid) then return nil end
    local definition = state.definitions_by_uid[definition_uid]
    if definition == nil then return nil end
    return immutable_view(state, definition)
end

function Catalog:list_definitions()
    local state = catalog_state(self)
    return immutable_view(state, state.definitions)
end

function Catalog:list_actions_with_direct_bindings()
    local state = catalog_state(self)
    local list = {}
    local index = 0
    for _, action_id in ipairs(state.direct_action_ids) do
        index = index + 1
        list[index] = action_id
    end
    return immutable_view(state, list)
end

function Catalog:get_audit_info()
    local state = catalog_state(self)
    local counts = state.artifact.counts
    local indexed_bindings = state.direct_binding_count
    local indexed_actions = #state.artifact.action_catalog.actions
    local indexed_edges = #state.artifact.action_catalog.edges
    local indexed_triggers = #state.artifact.command_catalog.triggers
    local indexed_definitions = #state.artifact.command_catalog.definitions
    local reconciliation = {
        indexed_direct_bindings = indexed_bindings,
        declared_bcm_commands = counts.bcm_commands,
        direct_binding_match = indexed_bindings == counts.bcm_commands,
        direct_binding_miss_count = math.max(0, counts.bcm_commands - indexed_bindings),
        indexed_actions = indexed_actions,
        declared_actions = counts.actions,
        action_match = indexed_actions == counts.actions,
        indexed_ac_edges = indexed_edges,
        declared_ac_edges = counts.ac_edges,
        ac_edge_match = indexed_edges == counts.ac_edges,
        indexed_triggers = indexed_triggers,
        declared_bcm_triggers = counts.bcm_triggers,
        trigger_match = indexed_triggers == counts.bcm_triggers,
        indexed_definitions = indexed_definitions,
        declared_bcm_command_definitions = counts.bcm_command_definitions,
        definition_match = indexed_definitions == counts.bcm_command_definitions,
        indexed_bcm_inputs = state.indexed_bcm_inputs,
        declared_bcm_inputs = counts.bcm_inputs,
        input_match = state.indexed_bcm_inputs == counts.bcm_inputs,
        indexed_definition_refs = state.indexed_definition_refs,
        referenced_definition_count = state.referenced_definition_count,
        all_match = indexed_bindings == counts.bcm_commands
            and indexed_actions == counts.actions
            and indexed_edges == counts.ac_edges
            and indexed_triggers == counts.bcm_triggers
            and indexed_definitions == counts.bcm_command_definitions
            and state.indexed_bcm_inputs == counts.bcm_inputs,
    }
    local integrity = state.integrity or {}
    return plain_copy({
        character = {
            fighter_id = state.artifact.character.fighter_id,
            character = state.artifact.character.character,
        },
        build_uid = state.artifact.build.build_uid,
        display_version = state.artifact.build.display_version,
        counts = state.artifact.counts,
        bindings = {
            direct_binding_count = indexed_bindings,
            direct_action_count = #state.direct_action_ids,
        },
        reconciliation = reconciliation,
        integrity = {
            verified = integrity.verified == true,
            reason = integrity.reason,
            artifact_sha256 = integrity.artifact_sha256,
            artifact_bytes = integrity.artifact_bytes,
            manifest_root_digest = state.manifest and state.manifest.root_digest or nil,
            manifest_root_digest_verified = integrity.manifest_root_digest_verified == true,
        },
        manifest = state.manifest and {
            root_digest = state.manifest.root_digest,
            expected_sha256 = state.manifest_character
                and state.manifest_character.sha256 or nil,
            expected_bytes = state.manifest_character
                and state.manifest_character.bytes or nil,
            loaded_from = state.manifest_file,
        } or nil,
        loaded_from = state.file,
    })
end

local function bind_profile(trigger, profile)
    return {
        action_id = trigger.action_id,
        raw_trigger_uid = trigger.raw_trigger_uid,
        trigger_index = trigger.trigger_index,
        raw_object_id = trigger.raw_object_id,
        conditions = trigger.conditions,
        trigger_raw_locator = trigger.raw_locator,
        raw_command_uid = profile.raw_command_uid,
        profile_name = profile.profile_name,
        command_no = profile.command_no,
        -- Raw BCM pointer index only; never a variant selector.
        command_index = profile.command_index,
        command_definition_uids = profile.command_definition_uids,
        variant_indexes = profile.variant_indexes,
        direct_command_tokens = profile.direct_command_tokens,
        ng_flag = profile.ng_flag,
        enabled = profile.enabled,
        button_mask = profile.button_mask,
        button_condition = profile.button_condition,
        dc_exc_flags = profile.dc_exc_flags,
        ng_key_flags = profile.ng_key_flags,
        preceding_time = profile.preceding_time,
        raw_profile = profile.raw_profile,
        profile_raw_locator = profile.raw_locator,
    }
end

local function index_artifact(artifact)
    local bindings_by_action = {}
    local definitions_by_uid = {}
    local definitions = {}
    local direct_binding_count = 0
    local indexed_bcm_inputs = 0
    local indexed_definition_refs = 0
    local referenced_definition_uids = {}

    for index, definition in ipairs(artifact.command_catalog.definitions) do
        definitions[index] = definition
        definitions_by_uid[definition.definition_uid] = definition
        indexed_bcm_inputs = indexed_bcm_inputs + #definition.inputs
    end

    for _, trigger in ipairs(artifact.command_catalog.triggers) do
        local action_id = trigger.action_id
        local bucket = bindings_by_action[action_id]
        if bucket == nil then
            bucket = {}
            bindings_by_action[action_id] = bucket
        end
        for _, profile in ipairs(trigger.profiles) do
            bucket[#bucket + 1] = bind_profile(trigger, profile)
            direct_binding_count = direct_binding_count + 1
            for _, ref_uid in ipairs(profile.command_definition_uids) do
                indexed_definition_refs = indexed_definition_refs + 1
                referenced_definition_uids[ref_uid] = true
            end
        end
    end

    local direct_action_ids = {}
    local index = 0
    for action_id in pairs(bindings_by_action) do
        index = index + 1
        direct_action_ids[index] = action_id
    end
    table.sort(direct_action_ids)

    local referenced_definition_count = 0
    for _ in pairs(referenced_definition_uids) do
        referenced_definition_count = referenced_definition_count + 1
    end

    return {
        bindings_by_action = bindings_by_action,
        definitions_by_uid = definitions_by_uid,
        definitions = definitions,
        direct_binding_count = direct_binding_count,
        direct_action_ids = direct_action_ids,
        indexed_bcm_inputs = indexed_bcm_inputs,
        indexed_definition_refs = indexed_definition_refs,
        referenced_definition_count = referenced_definition_count,
    }
end

local function build_catalog(artifact, file, read_count, manifest,
    manifest_character, manifest_file, integrity)
    local state = {
        artifact = artifact,
        file = file,
        read_count = read_count,
        manifest = manifest,
        manifest_character = manifest_character,
        manifest_file = manifest_file,
        integrity = integrity,
        views = {},
    }
    for key, value in pairs(index_artifact(artifact)) do
        state[key] = value
    end
    local catalog = setmetatable({}, Catalog)
    CATALOG_STATE[catalog] = state
    return catalog
end

local function cache_key(dir, fighter_id, file, manifest_file)
    return table.concat({ tostring(dir), tostring(fighter_id), tostring(file),
        tostring(manifest_file) }, "\0")
end

local function manifest_cache_key(dir, file)
    return tostring(dir) .. "\0" .. tostring(file)
end

local function set_single(cache, key, value)
    for existing in pairs(cache) do
        cache[existing] = nil
    end
    cache[key] = value
end

local function find_manifest_character(manifest, fighter_id)
    for _, entry in ipairs(manifest.characters) do
        if entry.fighter_id == fighter_id then return entry end
    end
    return nil
end

local function load_core(options)
    local dir = options.dir
    if not non_empty_string(dir) then
        return failure("invalid_options", "options.dir must be a non-empty string")
    end
    if not is_integer(options.fighter_id, 1) then
        return failure("invalid_options", "options.fighter_id must be a positive integer")
    end
    local file = options.file or raw_filename(options.fighter_id)
    if not is_plain_filename(file) then
        return failure("invalid_options", "artifact file name must be a plain file name")
    end
    local manifest_file = options.manifest_file or RawCatalog.MANIFEST_FILE
    if not is_plain_filename(manifest_file) then
        return failure("invalid_options", "manifest file name must be a plain file name")
    end
    local expected_build_uid = options.expected_build_uid
    if expected_build_uid ~= nil and not is_uid(expected_build_uid) then
        return failure("invalid_options", "options.expected_build_uid invalid")
    end
    local expected_display_version = options.expected_display_version
    if expected_display_version ~= nil and not non_empty_string(expected_display_version) then
        return failure("invalid_options", "options.expected_display_version invalid")
    end
    local read_file = options.read_file or default_read_file
    local decode = options.decode or default_decode
    local sha256 = options.sha256 or default_sha256

    local use_cache = options.use_cache ~= false
    local key = cache_key(dir, options.fighter_id, file, manifest_file)
    local cached = use_cache and CACHE[key] or nil
    if cached ~= nil then
        local build = cached.catalog and cached.catalog:get_build_info() or {}
        if (expected_build_uid == nil or build.build_uid == expected_build_uid)
            and (expected_display_version == nil
                or build.display_version == expected_display_version) then
            return cached.catalog, {
                ok = true,
                cache_hit = true,
                read_count = cached.read_count,
                file = file,
            }
        end
        CACHE[key] = nil
    end

    local read_count = (cached and cached.read_count or 0) + 1
    local manifest_required = options.manifest_required ~= false
    local manifest, manifest_character
    local manifest_path = join_path(dir, manifest_file)
    local manifest_key = manifest_cache_key(dir, manifest_file)
    if manifest_required then
        local cached_manifest = use_cache and MANIFEST_CACHE[manifest_key] or nil
        if cached_manifest == nil then
            local manifest_raw = read_file(manifest_path)
            if manifest_raw == nil then
                return failure("read_failed",
                    "raw manifest unreadable: " .. manifest_path)
            end
            manifest = decode(manifest_raw)
            if manifest == nil then
                return failure("malformed_json",
                    "manifest is not valid JSON: " .. manifest_path)
            end
            local code, message = validate_manifest(manifest)
            if code then return failure(code, message) end
            if use_cache then set_single(MANIFEST_CACHE, manifest_key, manifest) end
        else
            manifest = cached_manifest
        end
        manifest_character = find_manifest_character(
            manifest, options.fighter_id)
        if manifest_character == nil then
            return failure("manifest_character_missing",
                "manifest has no entry for fighter_id " .. options.fighter_id)
        end
        if manifest_character.file ~= file then
            return failure("manifest_file_mismatch",
                "manifest binds " .. tostring(manifest_character.file)
                    .. " but loader was given " .. file)
        end
    end

    local path = join_path(dir, file)
    local artifact_raw = read_file(path)
    if artifact_raw == nil then
        return failure("read_failed", "raw artifact unreadable: " .. path)
    end
    local artifact_digest
    if manifest_required then
        if #artifact_raw ~= manifest_character.bytes then
            return failure("artifact_size_mismatch",
                "raw artifact is " .. #artifact_raw
                    .. " bytes, manifest expects " .. manifest_character.bytes)
        end
        artifact_digest = sha256(artifact_raw)
        if artifact_digest ~= manifest_character.sha256 then
            return failure("artifact_hash_mismatch",
                "raw artifact sha256 " .. tostring(artifact_digest)
                    .. " does not match manifest " .. manifest_character.sha256)
        end
    end
    local artifact = decode(artifact_raw)
    if artifact == nil then
        return failure("malformed_json",
            "raw artifact is not valid JSON: " .. path)
    end
    local code, message = validate_artifact(artifact, options.fighter_id)
    if code then return failure(code, message) end
    if expected_build_uid ~= nil and artifact.build.build_uid ~= expected_build_uid then
        return failure("build_mismatch",
            "artifact build " .. artifact.build.build_uid
                .. " does not match expected " .. expected_build_uid)
    end
    if expected_display_version ~= nil
        and artifact.build.display_version ~= expected_display_version then
        return failure("build_mismatch",
            "artifact display version " .. artifact.build.display_version
                .. " does not match expected " .. expected_display_version)
    end
    if manifest_required then
        code, message = validate_manifest_character(
            manifest_character, artifact, options.fighter_id, file)
        if code then return failure(code, message) end
        if not deep_equal(artifact.build, manifest.build) then
            return failure("manifest_build_mismatch",
                "manifest build does not match character artifact build")
        end
    end

    local integrity = {
        verified = manifest_required,
        reason = manifest_required and nil or "manifest_not_required",
        artifact_sha256 = artifact_digest,
        artifact_bytes = manifest_required and #artifact_raw or nil,
        manifest_root_digest_verified = manifest_required,
    }
    local catalog = build_catalog(
        artifact, file, read_count, manifest, manifest_character,
        manifest_file, integrity)
    if use_cache then
        set_single(CACHE, key, { catalog = catalog, read_count = read_count })
    end
    return catalog, {
        ok = true,
        cache_hit = false,
        read_count = read_count,
        file = file,
    }
end

-- Loads the per-character raw catalog after verifying manifest root digest
-- and the character artifact bytes/SHA-256 against the manifest. Optional
-- dependencies read_file/decode/sha256 can be injected for pure-Lua tests;
-- defaults use REFramework fs.read, json.load_string and RawSha256.digest.
-- use_cache=false forces a fresh read and returns a fresh catalog.
function RawCatalog.load(options)
    options = type(options) == "table" and options or {}
    local results = table.pack(pcall(load_core, options))
    if not results[1] then
        return failure("internal_error", results[2])
    end
    return table.unpack(results, 2, results.n)
end

-- Pure-Lua tests and diagnostics can build an isolated catalog from an
-- already decoded artifact. The artifact still passes full validation, but
-- byte/SHA-256 integrity is not applicable and is reported as such.
function RawCatalog.from_artifact(artifact, options)
    options = type(options) == "table" and options or {}
    local code, message = validate_artifact(artifact, options.fighter_id)
    if code then
        return failure(code, message)
    end
    local manifest = options.manifest
    local manifest_character = nil
    if manifest ~= nil then
        code, message = validate_manifest(manifest)
        if code then return failure(code, message) end
        local fighter_id = options.fighter_id or artifact.character.fighter_id
        manifest_character = find_manifest_character(manifest, fighter_id)
        if manifest_character == nil then
            return failure("manifest_character_missing",
                "manifest has no entry for fighter_id " .. tostring(fighter_id))
        end
        code, message = validate_manifest_character(
            manifest_character, artifact, fighter_id,
            options.file or "<artifact>")
        if code then return failure(code, message) end
        if not deep_equal(artifact.build, manifest.build) then
            return failure("manifest_build_mismatch",
                "manifest build does not match character artifact build")
        end
    end
    return build_catalog(
        artifact,
        options.file or "<artifact>",
        options.read_count or 1,
        manifest,
        manifest_character,
        options.manifest_file or RawCatalog.MANIFEST_FILE,
        { verified = false, reason = "decoded_artifact_only" }), {
        ok = true,
        cache_hit = false,
        read_count = options.read_count or 1,
        file = options.file or "<artifact>",
    }
end

function RawCatalog.reset_cache()
    for key in pairs(CACHE) do
        CACHE[key] = nil
    end
    for key in pairs(MANIFEST_CACHE) do
        MANIFEST_CACHE[key] = nil
    end
end

return RawCatalog
