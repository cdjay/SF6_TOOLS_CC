-- CurrentMoveGraph.lua
-- Read-only data access layer for the SF6ACBCM current-only runtime artifact.
--
-- This module is a Data Access Layer, not a semantic core. It never infers,
-- merges, migrates or reinterprets Move/Action data, never applies Legacy
-- compatibility or CharacterRules, and never produces presentation text.
-- It validates the candidate artifact against its export manifest and then
-- exposes the contract data through read-only indexes.
--
-- Authority boundary: the artifact authority is "current_semantic_candidate_only"
-- and auto_approved is always false. A successful load only means the artifact
-- is structurally valid for development, diagnostics and future shadow
-- comparison. Production readiness is reported separately from the manifest
-- review state and is currently expected to be false.
--
-- Fail-closed: any contract, hash, build or consistency violation returns
-- (nil, status) with an explicit error code. Callers (and therefore the
-- Legacy MOD) are never crashed and never receive partial semantics.

local CurrentMoveGraph = {
    name = "ComboTrials.Semantic.CurrentMoveGraph",
    RUNTIME_SCHEMA = "sf6acbcm.runtime-current.v1",
    MANIFEST_SCHEMA = "sf6acbcm.m5-export-manifest.v1",
    ALGORITHM_VERSION = "m5-export.v1",
    AUTHORITY = "current_semantic_candidate_only",
    DIRECTORY = "TrainingComboTrials_data/semantic/current",
    RUNTIME_FILE = "runtime-current.v1.json",
    MANIFEST_FILE = "export-manifest.v1.json",
}

local ROLE_STRICTNESS = {
    primary = "STRICT",
    replacement = "STRICT",
    alias = "STRICT",
    derived = "STRICT",
    internal = "STRICT",
    shared = "SHARED",
    contextual = "CONTEXTUAL",
    unresolved = "UNRESOLVED",
}

local STRICTNESS = { STRICT = true, SHARED = true, CONTEXTUAL = true, UNRESOLVED = true }
local DIAGNOSTIC_KINDS = { row = true, extension = true, transition = true }
local REVIEW_STATUS = { pending = true, acknowledged = true }
local SOURCE_HASH_FIELDS = {
    "m2_graph_file_sha256",
    "m2_graph_canonical_sha256",
    "m4_index_sha256",
    "ledger_sha256",
}
local COUNT_GROUP_FIELDS = { "migration_links", "memberships", "rows", "extensions", "transitions" }
local APPROVAL_COVERAGE_FIELDS = {
    "moves",
    "stable_identities",
    "provisional",
    "decisions",
    "active_decisions",
    "approved_migration_links",
}

local function failure(code, message)
    return nil, {
        ok = false,
        code = code,
        message = tostring(message),
        readiness = {
            load_success = false,
            production_ready = false,
        },
    }
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
    return type(value) == "number"
        and value % 1 == 0
        and value >= (minimum or 0)
end

local function is_action_id(value)
    return is_integer(value, 0) and value <= 10000000
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

local function join_path(dir, file)
    return (dir:gsub("[/\\]+$", "")) .. "/" .. file
end

-- Array validators reject non-sequential keys so truncated or padded tables
-- cannot silently hide entries.
local function validate_array(value, item_kind, validate_item, context)
    if type(value) ~= "table" then
        return item_kind .. " must be an array"
    end
    local count = 0
    for index, item in ipairs(value) do
        local err = validate_item(item, context)
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

local function validate_build(build)
    if type(build) ~= "table" then return "build must be an object" end
    if not is_uid(build.build_uid) then return "build.build_uid invalid" end
    if not non_empty_string(build.display_version) then
        return "build.display_version invalid"
    end
    return nil
end

local function validate_source(source)
    if type(source) ~= "table" then return "source must be an object" end
    for _, field in ipairs(SOURCE_HASH_FIELDS) do
        if not is_sha256(source[field]) then
            return "source." .. field .. " invalid"
        end
    end
    local head = source.ledger_head_sha256
    if head ~= nil and not is_sha256(head) then
        return "source.ledger_head_sha256 invalid"
    end
    return nil
end

local function validate_anchor(anchor)
    if type(anchor) ~= "table" then return "anchor must be an object" end
    if not is_uid(anchor.anchor_route_uid) then return "anchor_route_uid invalid" end
    if not is_integer(anchor.trigger_index, 0) then return "trigger_index invalid" end
    if not is_action_id(anchor.owner_action_id) then return "owner_action_id invalid" end
    if not is_sha256(anchor.condition_hash) then return "condition_hash invalid" end
    if type(anchor.has_enabled_profile) ~= "boolean"
        or type(anchor.charge_command) ~= "boolean"
        or type(anchor.resource_gated) ~= "boolean"
        or type(anchor.state_gated) ~= "boolean" then
        return "anchor flags must be booleans"
    end
    if not non_empty_string(anchor.control_mode_availability) then
        return "control_mode_availability invalid"
    end
    return nil
end

local function validate_command(command)
    if type(command) ~= "table" then return "command must be an object" end
    if not non_empty_string(command.profile_name) then return "profile_name invalid" end
    if type(command.enabled) ~= "boolean" then return "enabled must be a boolean" end
    if type(command.normalized_notation) ~= "string" then
        return "normalized_notation invalid"
    end
    if not is_uid(command.anchor_route_uid) then return "anchor_route_uid invalid" end
    return nil
end

local function validate_membership(membership, context)
    if type(membership) ~= "table" then return "membership must be an object" end
    if not is_uid(membership.build_uid) then return "build_uid invalid" end
    if membership.build_uid ~= context.build_uid then
        return "build_uid does not match artifact build"
    end
    if not is_uid(membership.move_uid) then return "move_uid invalid" end
    if membership.move_uid ~= context.move_uid then
        return "move_uid does not match containing move"
    end
    if membership.action_id ~= nil and not is_action_id(membership.action_id) then
        return "action_id invalid"
    end
    local expected_strictness = ROLE_STRICTNESS[membership.role]
    if expected_strictness == nil then return "role invalid" end
    if not STRICTNESS[membership.strictness] then return "strictness invalid" end
    if membership.strictness ~= expected_strictness then
        return "strictness does not match role"
    end
    if membership.context_key ~= nil and not non_empty_string(membership.context_key) then
        return "context_key invalid"
    end
    return nil
end

local function validate_move(move, context)
    if type(move) ~= "table" then return "move must be an object" end
    if not is_uid(move.current_move_uid) then return "current_move_uid invalid" end
    if move.stable_move_uid ~= nil
        and (type(move.stable_move_uid) ~= "string"
            or not move.stable_move_uid:match("^move_[0-9a-f]+$")
            or #move.stable_move_uid < 21 or #move.stable_move_uid > 69) then
        return "stable_move_uid invalid"
    end
    if type(move.provisional) ~= "boolean" then return "provisional must be a boolean" end
    if not is_uid(move.revision_uid) then return "revision_uid invalid" end
    if not is_sha256(move.fingerprint) then return "fingerprint invalid" end
    if type(move.duplicate_owners) ~= "boolean" then
        return "duplicate_owners must be a boolean"
    end
    if type(move.disabled_only) ~= "boolean" then
        return "disabled_only must be a boolean"
    end
    local err = validate_array(move.owner_action_ids, "owner_action_ids", function(id)
        if not is_action_id(id) then return "action id invalid" end
        return nil
    end)
    if err then return err end
    err = validate_array(move.anchors, "anchors", validate_anchor)
    if err then return err end
    err = validate_array(move.commands, "commands", validate_command)
    if err then return err end
    err = validate_array(move.memberships, "memberships", validate_membership, {
        build_uid = context.build_uid,
        move_uid = move.current_move_uid,
    })
    if err then return err end
    return nil
end

local function validate_transition(transition)
    if type(transition) ~= "table" then return "transition must be an object" end
    if not is_uid(transition.transition_uid) then return "transition_uid invalid" end
    if not non_empty_string(transition.kind) then return "kind invalid" end
    if not STRICTNESS[transition.strictness] then return "strictness invalid" end
    if transition.from_move_uid ~= nil and not is_uid(transition.from_move_uid) then
        return "from_move_uid invalid"
    end
    if transition.to_move_uid ~= nil and not is_uid(transition.to_move_uid) then
        return "to_move_uid invalid"
    end
    if not is_action_id(transition.source_action_id) then
        return "source_action_id invalid"
    end
    if not is_action_id(transition.target_action_id) then
        return "target_action_id invalid"
    end
    return nil
end

local function validate_diagnostic(diagnostic)
    if type(diagnostic) ~= "table" then return "diagnostic must be an object" end
    if not is_uid(diagnostic.diagnostic_uid) then return "diagnostic_uid invalid" end
    if not DIAGNOSTIC_KINDS[diagnostic.diagnostic_kind] then
        return "diagnostic_kind invalid"
    end
    if diagnostic.fighter_id ~= nil and not is_integer(diagnostic.fighter_id, 1) then
        return "fighter_id invalid"
    end
    if diagnostic.character ~= nil and not non_empty_string(diagnostic.character) then
        return "character invalid"
    end
    if not is_action_id(diagnostic.source_action_id) then
        return "source_action_id invalid"
    end
    if not is_action_id(diagnostic.target_action_id) then
        return "target_action_id invalid"
    end
    local review = diagnostic.review
    if type(review) ~= "table" then return "review must be an object" end
    if not REVIEW_STATUS[review.status] then return "review.status invalid" end
    if review.decision_uid ~= nil and not is_uid(review.decision_uid) then
        return "review.decision_uid invalid"
    end
    if review.reason ~= nil and type(review.reason) ~= "string" then
        return "review.reason invalid"
    end
    local err = validate_array(review.evidence_refs, "review.evidence_refs", function(ref)
        if type(ref) ~= "string" then return "evidence ref invalid" end
        return nil
    end)
    if err then return err end
    if review.disposition ~= nil and review.disposition ~= "accepted_as_known_limitation" then
        return "review.disposition invalid"
    end
    return nil
end

local function validate_character(character, context)
    if type(character) ~= "table" then return "character must be an object" end
    if not is_integer(character.fighter_id, 1) then return "fighter_id invalid" end
    if not non_empty_string(character.character) then return "character invalid" end
    local err = validate_array(character.moves, "moves", validate_move, context)
    if err then return err end
    err = validate_array(character.transitions, "transitions", validate_transition)
    if err then return err end
    return nil
end

local function validate_count_group(group, name)
    if type(group) ~= "table" then return name .. " must be an object" end
    for _, field in ipairs(COUNT_GROUP_FIELDS) do
        if not is_integer(group[field], 0) then
            return name .. "." .. field .. " invalid"
        end
    end
    return nil
end

local function validate_manifest_file(entry, name)
    if type(entry) ~= "table" then return "artifacts." .. name .. " must be an object" end
    if not is_plain_filename(entry.file) then
        return "artifacts." .. name .. ".file invalid"
    end
    if not is_sha256(entry.sha256) then
        return "artifacts." .. name .. ".sha256 invalid"
    end
    if not is_integer(entry.bytes, 0) then
        return "artifacts." .. name .. ".bytes invalid"
    end
    return nil
end

-- Const fields shared by the manifest and the runtime artifact. Returns an
-- error code plus message when a const is violated so callers can tell an
-- unsupported artifact apart from a corrupt one.
local function check_const_envelope(document, expected_schema)
    if document.schema ~= expected_schema then
        return "unsupported_schema",
            "schema " .. tostring(document.schema) .. " is not " .. expected_schema
    end
    if document.algorithm_version ~= CurrentMoveGraph.ALGORITHM_VERSION then
        return "unsupported_algorithm",
            "algorithm_version " .. tostring(document.algorithm_version)
                .. " is not " .. CurrentMoveGraph.ALGORITHM_VERSION
    end
    if document.authority ~= CurrentMoveGraph.AUTHORITY then
        return "authority_mismatch",
            "authority " .. tostring(document.authority)
                .. " is not " .. CurrentMoveGraph.AUTHORITY
    end
    if document.auto_approved ~= false then
        return "auto_approved_violation", "auto_approved must be false"
    end
    return nil
end

local function validate_manifest(manifest)
    local code, message = check_const_envelope(manifest, CurrentMoveGraph.MANIFEST_SCHEMA)
    if code then return code, message end
    local err = validate_build(manifest.build)
    if err then return "invalid_manifest", err end
    err = validate_source(manifest.source)
    if err then return "invalid_manifest", err end
    if type(manifest.artifacts) ~= "table" then
        return "invalid_manifest", "artifacts must be an object"
    end
    err = validate_manifest_file(manifest.artifacts.runtime_current, "runtime_current")
    if err then return "invalid_manifest", err end
    err = validate_manifest_file(manifest.artifacts.public_catalog_current, "public_catalog_current")
    if err then return "invalid_manifest", err end
    err = validate_manifest_file(manifest.artifacts.legacy_projections, "legacy_projections")
    if err then return "invalid_manifest", err end
    local coverage = manifest.character_coverage
    if type(coverage) ~= "table" then
        return "invalid_manifest", "character_coverage must be an object"
    end
    if not is_integer(coverage.expected, 0) or not is_integer(coverage.generated, 0) then
        return "invalid_manifest", "character_coverage counts invalid"
    end
    err = validate_array(coverage.failed, "character_coverage.failed", function(entry)
        if not non_empty_string(entry) then return "failed entry invalid" end
        return nil
    end)
    if err then return "invalid_manifest", err end
    err = validate_count_group(manifest.unresolved, "unresolved")
    if err then return "invalid_manifest", err end
    err = validate_count_group(manifest.review_pending, "review_pending")
    if err then return "invalid_manifest", err end
    local approval = manifest.approval_coverage
    if type(approval) ~= "table" then
        return "invalid_manifest", "approval_coverage must be an object"
    end
    for _, field in ipairs(APPROVAL_COVERAGE_FIELDS) do
        if not is_integer(approval[field], 0) then
            return "invalid_manifest", "approval_coverage." .. field .. " invalid"
        end
    end
    local provenance = manifest.provenance_summary
    if type(provenance) ~= "table"
        or provenance.current_only ~= true
        or provenance.raw_workspace_read_only ~= true
        or provenance.m4_index_query_only ~= true
        or provenance.legacy_projection_separate ~= true then
        return "invalid_manifest", "provenance_summary must assert read-only current-only provenance"
    end
    local ready = manifest.ready
    if type(ready) ~= "table"
        or type(ready.artifact_set) ~= "boolean"
        or type(ready.review_complete) ~= "boolean"
        or type(ready.integration_candidate) ~= "boolean" then
        return "invalid_manifest", "ready flags must be booleans"
    end
    return nil
end

local function validate_artifact(artifact)
    local code, message = check_const_envelope(artifact, CurrentMoveGraph.RUNTIME_SCHEMA)
    if code then return code, message end
    local err = validate_build(artifact.build)
    if err then return "invalid_artifact", err end
    err = validate_source(artifact.source)
    if err then return "invalid_artifact", err end
    err = validate_array(artifact.unresolved_diagnostics, "unresolved_diagnostics",
        validate_diagnostic)
    if err then return "invalid_artifact", err end
    err = validate_array(artifact.characters, "characters", validate_character, {
        build_uid = artifact.build.build_uid,
    })
    if err then return "invalid_artifact", err end
    return nil
end

local function validate_artifact_manifest_consistency(artifact, manifest)
    local move_count = 0
    local provisional_count = 0
    local stable_identity_count = 0
    local unresolved = { memberships = 0, rows = 0, extensions = 0, transitions = 0 }
    local review_pending = { memberships = 0, rows = 0, extensions = 0, transitions = 0 }
    local transition_uids = {}
    local diagnostic_uids = {}

    for _, character in ipairs(artifact.characters) do
        local character_moves = {}
        for _, move in ipairs(character.moves) do
            move_count = move_count + 1
            if move.provisional then provisional_count = provisional_count + 1 end
            if move.stable_move_uid ~= nil then stable_identity_count = stable_identity_count + 1 end
            character_moves[move.current_move_uid] = true
            for _, membership in ipairs(move.memberships) do
                if membership.role == "unresolved" then
                    unresolved.memberships = unresolved.memberships + 1
                    local evidence = membership.evidence
                    if membership.action_id == nil or type(evidence) ~= "table"
                        or evidence.authority ~= "human_review_decision_only" then
                        review_pending.memberships = review_pending.memberships + 1
                    end
                end
            end
        end
        for _, transition in ipairs(character.transitions) do
            if transition_uids[transition.transition_uid] then
                return "duplicate_transition_uid",
                    "duplicate transition_uid " .. transition.transition_uid
            end
            transition_uids[transition.transition_uid] = true
            if transition.from_move_uid ~= nil
                and not character_moves[transition.from_move_uid] then
                return "invalid_artifact",
                    "transition " .. transition.transition_uid .. " has unknown from_move_uid"
            end
            if transition.to_move_uid ~= nil
                and not character_moves[transition.to_move_uid] then
                return "invalid_artifact",
                    "transition " .. transition.transition_uid .. " has unknown to_move_uid"
            end
        end
    end

    for _, diagnostic in ipairs(artifact.unresolved_diagnostics) do
        if diagnostic_uids[diagnostic.diagnostic_uid] then
            return "duplicate_diagnostic_uid",
                "duplicate diagnostic_uid " .. diagnostic.diagnostic_uid
        end
        diagnostic_uids[diagnostic.diagnostic_uid] = true
        local plural = diagnostic.diagnostic_kind .. "s"
        unresolved[plural] = unresolved[plural] + 1
        if diagnostic.review.status == "pending" then
            review_pending[plural] = review_pending[plural] + 1
        end
    end

    local approval = manifest.approval_coverage
    if approval.moves ~= move_count
        or approval.provisional ~= provisional_count
        or approval.stable_identities ~= stable_identity_count then
        return "artifact_summary_mismatch",
            "approval_coverage does not match runtime artifact moves"
    end
    for _, field in ipairs({ "memberships", "rows", "extensions", "transitions" }) do
        if manifest.unresolved[field] ~= unresolved[field] then
            return "artifact_summary_mismatch",
                "unresolved." .. field .. " does not match runtime artifact"
        end
    end
    for _, field in ipairs({ "memberships", "rows", "extensions", "transitions" }) do
        if manifest.review_pending[field] ~= review_pending[field] then
            return "artifact_summary_mismatch",
                "review_pending." .. field .. " does not match runtime artifact"
        end
    end
    if manifest.approval_coverage.active_decisions
        > manifest.approval_coverage.decisions then
        return "artifact_summary_mismatch",
            "active decisions cannot exceed total decisions"
    end

    local complete = #manifest.character_coverage.failed == 0
        and manifest.character_coverage.generated == manifest.character_coverage.expected
        and manifest.character_coverage.generated == #artifact.characters
    local review_complete = stable_identity_count == move_count
    local integration_candidate = complete and stable_identity_count == move_count
    for _, field in ipairs(COUNT_GROUP_FIELDS) do
        review_complete = review_complete and manifest.review_pending[field] == 0
        integration_candidate = integration_candidate and manifest.unresolved[field] == 0
    end
    if manifest.ready.artifact_set ~= complete
        or manifest.ready.review_complete ~= review_complete
        or manifest.ready.integration_candidate ~= integration_candidate then
        return "readiness_inconsistent",
            "ready flags do not match SF6ACBCM export formulas"
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
    local Telemetry = require("func/ComboTrials/Telemetry")
    return Telemetry.sha256(raw)
end

local Graph = {}
local GRAPH_STATE = setmetatable({}, { __mode = "k" })
Graph.__index = Graph
Graph.__newindex = function()
    error("CurrentMoveGraph is read-only", 2)
end
Graph.__metatable = false

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
            error("CurrentMoveGraph data is read-only", 2)
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

local function graph_state(graph)
    return assert(GRAPH_STATE[graph], "invalid CurrentMoveGraph instance")
end

function Graph:get_build_info()
    local state = graph_state(self)
    return {
        build_uid = state.build.build_uid,
        display_version = state.build.display_version,
        source = immutable_view(state, state.source),
    }
end

function Graph:get_readiness()
    local state = graph_state(self)
    return immutable_view(state, state.readiness)
end

function Graph:list_characters()
    local state = graph_state(self)
    local list = {}
    for index, entry in ipairs(state.characters) do
        list[index] = { fighter_id = entry.fighter_id, character = entry.character }
    end
    return list
end

-- Accepts a fighter_id number or the exact canonical character identifier
-- (for example "EHonda"). Display names are intentionally not matched.
function Graph:get_character(key)
    local state = graph_state(self)
    if type(key) == "number" then
        return immutable_view(state, state.by_fighter_id[key])
    end
    if type(key) == "string" then
        return immutable_view(state, state.by_character[key])
    end
    return nil
end

-- Returns the move plus its owning { fighter_id, character } context.
function Graph:get_move(move_uid)
    local state = graph_state(self)
    local move = state.moves_by_uid[move_uid]
    if move == nil then return nil end
    return immutable_view(state, move), immutable_view(state, state.move_owner[move_uid])
end

function Graph:get_move_by_revision(revision_uid)
    local state = graph_state(self)
    local move = state.moves_by_revision[revision_uid]
    if move == nil then return nil end
    return immutable_view(state, move),
        immutable_view(state, state.move_owner[move.current_move_uid])
end

-- Action membership is many-valued: one Action ID can belong to several Move
-- revisions (for example Zangief 900). This always returns an array, never a
-- collapsed single answer. Entries are fresh tables; moves and memberships
-- are the raw contract data and must be treated as read-only.
function Graph:get_moves_by_action(fighter_id, action_id)
    local state = graph_state(self)
    local result = {}
    local by_fighter = state.actions[fighter_id]
    local bucket = by_fighter and by_fighter[action_id] or nil
    if bucket == nil then return result end
    for index, entry in ipairs(bucket) do
        result[index] = {
            fighter_id = fighter_id,
            character = entry.character,
            move = immutable_view(state, entry.move),
            membership = immutable_view(state, entry.membership),
        }
    end
    return result
end

function Graph:get_action_memberships(fighter_id, action_id)
    local state = graph_state(self)
    local result = {}
    local by_fighter = state.actions[fighter_id]
    local bucket = by_fighter and by_fighter[action_id] or nil
    if bucket == nil then return result end
    for index, entry in ipairs(bucket) do
        result[index] = immutable_view(state, entry.membership)
    end
    return result
end

-- Raw contract command revisions for a Move. No UI formatting is applied.
function Graph:get_commands(move_uid)
    local state = graph_state(self)
    local move = state.moves_by_uid[move_uid]
    if move == nil then return nil end
    return immutable_view(state, move.commands)
end

function Graph:get_transitions_from(move_uid)
    local state = graph_state(self)
    local result = {}
    local bucket = state.transitions_from[move_uid]
    if bucket == nil then return result end
    for index, transition in ipairs(bucket) do
        result[index] = immutable_view(state, transition)
    end
    return result
end

function Graph:get_transitions_to(move_uid)
    local state = graph_state(self)
    local result = {}
    local bucket = state.transitions_to[move_uid]
    if bucket == nil then return result end
    for index, transition in ipairs(bucket) do
        result[index] = immutable_view(state, transition)
    end
    return result
end

function Graph:get_character_transitions(key)
    local state = graph_state(self)
    local character = type(key) == "number" and state.by_fighter_id[key]
        or (type(key) == "string" and state.by_character[key] or nil)
    if character == nil then return nil end
    return immutable_view(state, character.transitions)
end

-- Unresolved diagnostics are exposed exactly as the artifact recorded them;
-- the loader never drops, reorders, resolves or defaults them. filter may
-- select by fighter_id and/or diagnostic_kind.
function Graph:get_unresolved(filter)
    local state = graph_state(self)
    local result = {}
    local fighter_id = type(filter) == "table" and filter.fighter_id or nil
    local kind = type(filter) == "table" and filter.diagnostic_kind or nil
    for _, diagnostic in ipairs(state.unresolved) do
        if (fighter_id == nil or diagnostic.fighter_id == fighter_id)
            and (kind == nil or diagnostic.diagnostic_kind == kind) then
            result[#result + 1] = immutable_view(state, diagnostic)
        end
    end
    return result
end

local function index_action(actions, fighter_id, character, action_id, move, membership)
    local by_fighter = actions[fighter_id]
    if by_fighter == nil then
        by_fighter = {}
        actions[fighter_id] = by_fighter
    end
    local bucket = by_fighter[action_id]
    if bucket == nil then
        bucket = {}
        by_fighter[action_id] = bucket
    end
    bucket[#bucket + 1] = { character = character, move = move, membership = membership }
end

local function build_graph(artifact, manifest)
    local ready = manifest.ready
    local readiness = {
        load_success = true,
        authority = manifest.authority,
        auto_approved = manifest.auto_approved,
        artifact_set = ready.artifact_set,
        review_complete = ready.review_complete,
        integration_candidate = ready.integration_candidate,
        -- Load success is not production permission. Readiness comes only from
        -- the manifest review state, never from the loader itself.
        production_ready = ready.artifact_set == true
            and ready.review_complete == true
            and ready.integration_candidate == true,
        verified_summary = {
            moves = manifest.approval_coverage.moves,
            stable_identities = manifest.approval_coverage.stable_identities,
            provisional = manifest.approval_coverage.provisional,
            unresolved_memberships = manifest.unresolved.memberships,
            unresolved_rows = manifest.unresolved.rows,
            unresolved_extensions = manifest.unresolved.extensions,
            unresolved_transitions = manifest.unresolved.transitions,
            review_pending_memberships = manifest.review_pending.memberships,
            review_pending_rows = manifest.review_pending.rows,
            review_pending_extensions = manifest.review_pending.extensions,
            review_pending_transitions = manifest.review_pending.transitions,
        },
        -- These ledger/migration counts are manifest claims. The runtime-current
        -- artifact does not contain enough data to independently recompute them.
        manifest_only = {
            decisions = manifest.approval_coverage.decisions,
            active_decisions = manifest.approval_coverage.active_decisions,
            approved_migration_links = manifest.approval_coverage.approved_migration_links,
            unresolved_migration_links = manifest.unresolved.migration_links,
            review_pending_migration_links = manifest.review_pending.migration_links,
        },
        provenance_summary = manifest.provenance_summary,
    }

    local graph = setmetatable({}, Graph)
    local state = {
        build = artifact.build,
        source = artifact.source,
        readiness = readiness,
        characters = {},
        by_fighter_id = {},
        by_character = {},
        moves_by_uid = {},
        moves_by_revision = {},
        move_owner = {},
        actions = {},
        transitions_from = {},
        transitions_to = {},
        unresolved = artifact.unresolved_diagnostics,
        views = setmetatable({}, { __mode = "k" }),
    }
    GRAPH_STATE[graph] = state

    for _, character in ipairs(artifact.characters) do
        local entry = {
            fighter_id = character.fighter_id,
            character = character.character,
            moves = character.moves,
            transitions = character.transitions,
        }
        state.characters[#state.characters + 1] = entry
        if state.by_fighter_id[entry.fighter_id] ~= nil then
            return failure("duplicate_character",
                "duplicate fighter_id " .. entry.fighter_id)
        end
        if state.by_character[entry.character] ~= nil then
            return failure("duplicate_character",
                "duplicate character " .. entry.character)
        end
        state.by_fighter_id[entry.fighter_id] = entry
        state.by_character[entry.character] = entry

        local owner = { fighter_id = entry.fighter_id, character = entry.character }
        for _, move in ipairs(character.moves) do
            if state.moves_by_uid[move.current_move_uid] ~= nil then
                return failure("duplicate_move_uid",
                    "duplicate current_move_uid " .. move.current_move_uid)
            end
            if state.moves_by_revision[move.revision_uid] ~= nil then
                return failure("duplicate_revision_uid",
                    "duplicate revision_uid " .. move.revision_uid)
            end
            state.moves_by_uid[move.current_move_uid] = move
            state.moves_by_revision[move.revision_uid] = move
            state.move_owner[move.current_move_uid] = owner
            -- Index from memberships, not owner_action_ids: replacement and
            -- alias actions (EHonda 977) are real memberships but do not
            -- appear in owner_action_ids.
            for _, membership in ipairs(move.memberships) do
                if membership.action_id ~= nil then
                    index_action(state.actions, entry.fighter_id, entry.character,
                        membership.action_id, move, membership)
                end
            end
        end
        for _, transition in ipairs(character.transitions) do
            if transition.from_move_uid ~= nil then
                local bucket = state.transitions_from[transition.from_move_uid]
                if bucket == nil then
                    bucket = {}
                    state.transitions_from[transition.from_move_uid] = bucket
                end
                bucket[#bucket + 1] = transition
            end
            if transition.to_move_uid ~= nil then
                local bucket = state.transitions_to[transition.to_move_uid]
                if bucket == nil then
                    bucket = {}
                    state.transitions_to[transition.to_move_uid] = bucket
                end
                bucket[#bucket + 1] = transition
            end
        end
    end

    return graph, {
        ok = true,
        readiness = immutable_view(state, readiness),
        build = immutable_view(state, artifact.build),
        artifact = immutable_view(state, manifest.artifacts.runtime_current),
        character_count = #state.characters,
    }
end

local function load_core(options)
    local dir = options.dir
    if not non_empty_string(dir) then
        return failure("invalid_options", "options.dir must be a non-empty string")
    end
    local runtime_file = options.runtime_file or CurrentMoveGraph.RUNTIME_FILE
    local manifest_file = options.manifest_file or CurrentMoveGraph.MANIFEST_FILE
    if not is_plain_filename(runtime_file) or not is_plain_filename(manifest_file) then
        return failure("invalid_options", "artifact file names must be plain file names")
    end
    local read_file = options.read_file or default_read_file
    local decode = options.decode or default_decode
    local sha256 = options.sha256 or default_sha256
    local expected_build_uid = options.expected_build_uid
    if expected_build_uid ~= nil and not is_uid(expected_build_uid) then
        return failure("invalid_options", "options.expected_build_uid invalid")
    end
    local expected_display_version = options.expected_display_version
    if expected_display_version ~= nil and not non_empty_string(expected_display_version) then
        return failure("invalid_options", "options.expected_display_version invalid")
    end

    local manifest_path = join_path(dir, manifest_file)
    local manifest_raw = read_file(manifest_path)
    if manifest_raw == nil then
        return failure("read_failed", "manifest unreadable: " .. manifest_path)
    end
    local manifest = decode(manifest_raw)
    if manifest == nil then
        return failure("malformed_json", "manifest is not valid JSON: " .. manifest_path)
    end
    local code, message = validate_manifest(manifest)
    if code then return failure(code, message) end

    local entry = manifest.artifacts.runtime_current
    if entry.file ~= runtime_file then
        return failure("artifact_name_mismatch",
            "manifest binds " .. entry.file .. " but loader was given " .. runtime_file)
    end

    local runtime_path = join_path(dir, runtime_file)
    local runtime_raw = read_file(runtime_path)
    if runtime_raw == nil then
        return failure("read_failed", "runtime artifact unreadable: " .. runtime_path)
    end
    if #runtime_raw ~= entry.bytes then
        return failure("artifact_size_mismatch",
            "runtime artifact is " .. #runtime_raw .. " bytes, manifest expects "
                .. entry.bytes)
    end
    local digest = sha256(runtime_raw)
    if digest ~= entry.sha256 then
        return failure("artifact_hash_mismatch",
            "runtime artifact sha256 " .. tostring(digest)
                .. " does not match manifest " .. entry.sha256)
    end
    local artifact = decode(runtime_raw)
    if artifact == nil then
        return failure("malformed_json", "runtime artifact is not valid JSON: " .. runtime_path)
    end
    code, message = validate_artifact(artifact)
    if code then return failure(code, message) end

    if artifact.build.build_uid ~= manifest.build.build_uid
        or artifact.build.display_version ~= manifest.build.display_version then
        return failure("build_inconsistent", "manifest and artifact build differ")
    end
    for _, field in ipairs(SOURCE_HASH_FIELDS) do
        if artifact.source[field] ~= manifest.source[field] then
            return failure("source_inconsistent", "source." .. field .. " differs")
        end
    end
    if artifact.source.ledger_head_sha256 ~= manifest.source.ledger_head_sha256 then
        return failure("source_inconsistent", "source.ledger_head_sha256 differs")
    end
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
    local coverage = manifest.character_coverage
    if #coverage.failed > 0 then
        return failure("coverage_mismatch", "character coverage reports failures")
    end
    if coverage.expected ~= coverage.generated then
        return failure("coverage_mismatch", "expected character count differs from generated")
    end
    if coverage.generated ~= #artifact.characters then
        return failure("coverage_mismatch",
            "manifest coverage " .. coverage.generated
                .. " does not match artifact characters " .. #artifact.characters)
    end

    code, message = validate_artifact_manifest_consistency(artifact, manifest)
    if code then return failure(code, message) end

    return build_graph(artifact, manifest)
end

-- Loads and validates the SF6ACBCM current-only artifact pair from
-- options.dir. Returns (graph, status) on success or (nil, status) with an
-- explicit status.code on any failure. Optional dependencies (read_file,
-- decode, sha256) can be injected for tests; defaults use REFramework fs/json
-- and the shared Telemetry.sha256 implementation.
function CurrentMoveGraph.load(options)
    options = type(options) == "table" and options or {}
    local results = table.pack(pcall(load_core, options))
    if not results[1] then
        return failure("internal_error", results[2])
    end
    return table.unpack(results, 2, results.n)
end

return CurrentMoveGraph
