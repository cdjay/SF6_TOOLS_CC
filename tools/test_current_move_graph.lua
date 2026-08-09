package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local FIXTURE_DIR = "tools/fixtures/current_move_graph"
local RUNTIME_PATH = FIXTURE_DIR .. "/runtime-current.v1.json"
local fixture_data = dofile(FIXTURE_DIR .. "/fixtures.lua")

-- REFramework global stubs. fs.read serves the real fixture bytes from disk.
-- json.load_file exists only so the Telemetry dependency chain (SF6CC_Version)
-- loads quietly; json.load_string decodes through the Lua fixture mirror.
log = { warn = function() end, error = function() end }
fs = {
    read = function(path)
        local handle = io.open(path, "rb")
        if not handle then return nil end
        local raw = handle:read("*a")
        handle:close()
        return raw
    end,
}

local function deep_copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do
        copy[key] = deep_copy(item)
    end
    return copy
end

local Telemetry = require("func/ComboTrials/Telemetry")

local function decode_fixture(raw)
    if raw:find("m5%-export%-manifest") then
        local copy = deep_copy(fixture_data.manifest)
        -- Pin the manifest mirror to the real fixture bytes so the hash path
        -- exercises the genuine SHA-256 comparison.
        local runtime_raw = fs.read(RUNTIME_PATH)
        copy.artifacts.runtime_current.bytes = #runtime_raw
        copy.artifacts.runtime_current.sha256 = Telemetry.sha256(runtime_raw)
        return copy
    end
    return deep_copy(fixture_data.runtime)
end

json = {
    load_file = function() return nil end,
    load_string = function(raw) return decode_fixture(raw) end,
}

local CurrentMoveGraph = require("func/ComboTrials/Semantic/CurrentMoveGraph")
assert(CurrentMoveGraph.DIRECTORY == "TrainingComboTrials_data/semantic/current",
    "future package location must remain separate from V2 and Legacy data")

local function expect_failure(status, code)
    assert(type(status) == "table" and status.ok == false,
        "failure status must be explicit, got: " .. tostring(status))
    assert(status.code == code,
        "expected error code " .. code .. ", got " .. tostring(status.code)
            .. " (" .. tostring(status.message) .. ")")
    assert(status.readiness.load_success == false
        and status.readiness.production_ready == false,
        "failures must never report readiness")
end

local function load_mutated(mutate_manifest, mutate_runtime)
    return CurrentMoveGraph.load({
        dir = FIXTURE_DIR,
        decode = function(raw)
            local copy = decode_fixture(raw)
            if raw:find("m5%-export%-manifest") then
                if mutate_manifest then mutate_manifest(copy) end
            else
                if mutate_runtime then mutate_runtime(copy) end
            end
            return copy
        end,
    })
end

-- Valid load through the real default dependencies (fs.read, json.load_string
-- dispatch and Telemetry.sha256).
local graph, status = CurrentMoveGraph.load({
    dir = FIXTURE_DIR,
    expected_display_version = "2026-08-03",
})
assert(graph ~= nil and status.ok == true,
    "valid artifact must load: " .. tostring(status and status.message))
assert(status.character_count == 4, "fixture covers 4 characters")
assert(status.artifact.file == "runtime-current.v1.json")

local readiness = graph:get_readiness()
assert(readiness.load_success == true)
assert(readiness.authority == "current_semantic_candidate_only")
assert(readiness.auto_approved == false)
assert(readiness.artifact_set == true)
assert(readiness.review_complete == false)
assert(readiness.integration_candidate == false)
assert(readiness.production_ready == false,
    "a candidate artifact must never be production ready")
assert(readiness.verified_summary.moves == 7
    and readiness.verified_summary.unresolved_rows == 1)
assert(readiness.manifest_only.decisions == 0
    and readiness.manifest_only.unresolved_migration_links == 0,
    "ledger-only claims must be separated from runtime-verifiable summaries")

local info = graph:get_build_info()
assert(info.build_uid == "sf6b_c0269f7351fc73e06633b780")
assert(info.display_version == "2026-08-03")
assert(type(info.source) == "table"
    and #info.source.ledger_sha256 == 64
    and info.source.ledger_sha256:match("^[0-9a-f]+$") ~= nil)

-- Character lookup by fighter_id and canonical identifier only.
assert(graph:get_character(20).character == "EHonda")
assert(graph:get_character("Zangief").fighter_id == 6)
assert(graph:get_character(999) == nil, "unknown fighter_id must return nil")
assert(graph:get_character("ehonda") == nil, "display names must not resolve identity")
assert(#graph:list_characters() == 4)

-- Move lookup by current UID and revision UID.
local move965, owner965 = graph:get_move("m2move_6c92dae21a5e22f63d2bfc7f")
assert(move965 ~= nil and owner965.fighter_id == 20 and owner965.character == "EHonda")
local by_revision = graph:get_move_by_revision("m2rev_3ac10406c9e8bf0d477121a9")
assert(by_revision == move965, "revision lookup must resolve the same move")
assert(graph:get_move("m2move_doesnotexist") == nil)

local mutation_ok = pcall(function() move965.provisional = false end)
assert(mutation_ok == false and graph:get_move(move965.current_move_uid).provisional == true,
    "query results must not permit mutation of graph data")
mutation_ok = pcall(function() readiness.review_complete = true end)
assert(mutation_ok == false and graph:get_readiness().review_complete == false,
    "readiness must be an immutable view")
mutation_ok = pcall(function() graph.injected = true end)
assert(mutation_ok == false, "the graph instance must reject external state")

-- EHonda sentinels: 965/961 single primary, 976 primary + 977 replacement on
-- one Move revision (977 is not in owner_action_ids).
local honda965 = graph:get_moves_by_action(20, 965)
assert(#honda965 == 1 and honda965[1].membership.role == "primary")
assert(#graph:get_moves_by_action(20, 961) == 1)
local honda976 = graph:get_moves_by_action(20, 976)
local honda977 = graph:get_moves_by_action(20, 977)
assert(#honda976 == 1 and #honda977 == 1)
assert(honda977[1].membership.role == "replacement")
assert(honda976[1].move.current_move_uid == honda977[1].move.current_move_uid)
assert(honda976[1].move.revision_uid == "m2rev_6b83e2480b45445c53312838")

-- Zangief sentinels: action 900 belongs to two Move revisions and must never
-- be collapsed; 903 stays on the second revision only.
local gief900 = graph:get_moves_by_action(6, 900)
assert(#gief900 == 2, "Zangief 900 must preserve both memberships")
local uid_set = {}
for _, entry in ipairs(gief900) do
    uid_set[entry.move.current_move_uid] = true
end
assert(uid_set["m2move_4d0ae239087cf32fa91e300a"]
    and uid_set["m2move_6f6007b8f44f01b2b5339ab2"])
local gief903 = graph:get_moves_by_action(6, 903)
assert(#gief903 == 1
    and gief903[1].move.current_move_uid == "m2move_6f6007b8f44f01b2b5339ab2")
assert(#graph:get_action_memberships(6, 900) == 2)
assert(#graph:get_moves_by_action(20, 900) == 0, "action ids are fighter-scoped")
assert(#graph:get_moves_by_action(6, 999999) == 0)

-- Command lookup returns raw contract revisions without UI formatting.
local commands = graph:get_commands("m2move_6c92dae21a5e22f63d2bfc7f")
assert(#commands == 4)
local norm
for _, entry in ipairs(commands) do
    if entry.profile_name == "norm" then norm = entry end
end
assert(norm ~= nil and norm.enabled == true and norm.normalized_notation == "2+P")
assert(graph:get_commands("m2move_doesnotexist") == nil)

-- Transition lookup, including UNRESOLVED boundary diagnostics with null ends.
local from = graph:get_transitions_from("m2move_1052594b4f203eed8dce1672")
assert(#from == 1 and from[1].kind == "followup"
    and from[1].to_move_uid == "m2move_097e7341cf954d4bbb754fab")
local to = graph:get_transitions_to("m2move_097e7341cf954d4bbb754fab")
assert(#to == 1 and to[1].strictness == "STRICT")
assert(#graph:get_transitions_from("m2move_6c92dae21a5e22f63d2bfc7f") == 0)
local luke_transitions = graph:get_character_transitions("Luke")
assert(#luke_transitions == 1 and luke_transitions[1].strictness == "UNRESOLVED"
    and luke_transitions[1].from_move_uid == nil,
    "boundary diagnostics must keep null endpoints untouched")
assert(graph:get_character_transitions(999) == nil)

-- Unresolved diagnostics preserved verbatim and filterable.
local unresolved = graph:get_unresolved()
assert(#unresolved == 2)
local ed_rows = graph:get_unresolved({ fighter_id = 19 })
assert(#ed_rows == 1 and ed_rows[1].diagnostic_kind == "row"
    and ed_rows[1].review.status == "pending"
    and ed_rows[1].detail.predicate == "t17_exact_rebind")
local unresolved_transitions = graph:get_unresolved({ diagnostic_kind = "transition" })
assert(#unresolved_transitions == 1 and unresolved_transitions[1].fighter_id == 3)

-- Production readiness is recomputed from the exporter formula, not trusted as
-- an independent manifest assertion.
local inconsistent_ready_graph, inconsistent_ready_status = load_mutated(function(manifest)
    manifest.ready.review_complete = true
    manifest.ready.integration_candidate = true
end)
assert(inconsistent_ready_graph == nil)
expect_failure(inconsistent_ready_status, "readiness_inconsistent")

local incomplete_graph, incomplete_status = load_mutated(function(manifest)
    manifest.ready.artifact_set = false
end)
assert(incomplete_graph == nil)
expect_failure(incomplete_status, "readiness_inconsistent")

local production_graph, production_status = load_mutated(function(manifest)
    for _, field in ipairs({ "migration_links", "memberships", "rows", "extensions", "transitions" }) do
        manifest.unresolved[field] = 0
        manifest.review_pending[field] = 0
    end
    manifest.approval_coverage.stable_identities = manifest.approval_coverage.moves
    manifest.approval_coverage.provisional = 0
    manifest.approval_coverage.decisions = 1
    manifest.approval_coverage.active_decisions = 1
    manifest.ready.review_complete = true
    manifest.ready.integration_candidate = true
end, function(runtime)
    local move_index = 0
    for _, character in ipairs(runtime.characters) do
        local transitions = {}
        for _, transition in ipairs(character.transitions) do
            if transition.strictness ~= "UNRESOLVED"
                and transition.from_move_uid ~= nil and transition.to_move_uid ~= nil then
                transitions[#transitions + 1] = transition
            end
        end
        character.transitions = transitions
        for _, move in ipairs(character.moves) do
            move_index = move_index + 1
            move.stable_move_uid = string.format("move_%016x", move_index)
            move.provisional = false
        end
    end
    runtime.unresolved_diagnostics = {}
end)
assert(production_graph ~= nil and production_status.readiness.production_ready == true,
    "only a formula-consistent reviewed artifact may report production readiness")

-- Fail-closed contract violations.
local missing, missing_status = CurrentMoveGraph.load({ dir = "tools/fixtures/absent" })
assert(missing == nil)
expect_failure(missing_status, "read_failed")

local no_options, no_options_status = CurrentMoveGraph.load({})
assert(no_options == nil)
expect_failure(no_options_status, "invalid_options")

local wrong_schema_graph, wrong_schema = load_mutated(nil, function(runtime)
    runtime.schema = "sf6acbcm.runtime-current.v0"
end)
assert(wrong_schema_graph == nil)
expect_failure(wrong_schema, "unsupported_schema")

local wrong_algo_graph, wrong_algo = load_mutated(function(manifest)
    manifest.algorithm_version = "m5-export.v2"
end)
assert(wrong_algo_graph == nil)
expect_failure(wrong_algo, "unsupported_algorithm")

local authority_graph, authority_status = load_mutated(function(manifest)
    manifest.authority = "production_semantic_authority"
end)
assert(authority_graph == nil)
expect_failure(authority_status, "authority_mismatch")

local approved_graph, approved_status = load_mutated(function(manifest)
    manifest.auto_approved = true
end)
assert(approved_graph == nil)
expect_failure(approved_status, "auto_approved_violation")

local malformed_graph, malformed_status = CurrentMoveGraph.load({
    dir = FIXTURE_DIR,
    decode = function(raw)
        if raw:find("m5%-export%-manifest") then
            return decode_fixture(raw)
        end
        return nil
    end,
})
assert(malformed_graph == nil)
expect_failure(malformed_status, "malformed_json")

local wrong_hash_graph, wrong_hash = load_mutated(function(manifest)
    manifest.artifacts.runtime_current.sha256 = string.rep("0", 64)
end)
assert(wrong_hash_graph == nil)
expect_failure(wrong_hash, "artifact_hash_mismatch")

local wrong_size_graph, wrong_size = load_mutated(function(manifest)
    manifest.artifacts.runtime_current.bytes =
        manifest.artifacts.runtime_current.bytes + 1
end)
assert(wrong_size_graph == nil)
expect_failure(wrong_size, "artifact_size_mismatch")

local wrong_name_graph, wrong_name = load_mutated(function(manifest)
    manifest.artifacts.runtime_current.file = "renamed.json"
end)
assert(wrong_name_graph == nil)
expect_failure(wrong_name, "artifact_name_mismatch")

local build_graph, build_status = CurrentMoveGraph.load({
    dir = FIXTURE_DIR,
    expected_build_uid = "sf6b_000000000000000000000000",
})
assert(build_graph == nil)
expect_failure(build_status, "build_mismatch")

local version_graph, version_status = CurrentMoveGraph.load({
    dir = FIXTURE_DIR,
    expected_display_version = "2026-08-04",
})
assert(version_graph == nil)
expect_failure(version_status, "build_mismatch")

local inconsistent_graph, inconsistent_status = load_mutated(function(manifest)
    manifest.build.build_uid = "sf6b_111111111111111111111111"
end)
assert(inconsistent_graph == nil)
expect_failure(inconsistent_status, "build_inconsistent")

local source_graph, source_status = load_mutated(nil, function(runtime)
    runtime.source.ledger_sha256 = string.rep("a", 64)
end)
assert(source_graph == nil)
expect_failure(source_status, "source_inconsistent")

local coverage_graph, coverage_status = load_mutated(nil, function(runtime)
    table.remove(runtime.characters, 4)
end)
assert(coverage_graph == nil)
expect_failure(coverage_status, "coverage_mismatch")

local summary_graph, summary_status = load_mutated(function(manifest)
    manifest.approval_coverage.moves = manifest.approval_coverage.moves + 1
end)
assert(summary_graph == nil)
expect_failure(summary_status, "artifact_summary_mismatch")

local pending_graph, pending_status = load_mutated(function(manifest)
    manifest.review_pending.memberships = manifest.review_pending.memberships + 1
end)
assert(pending_graph == nil)
expect_failure(pending_status, "artifact_summary_mismatch")

local dangling_graph, dangling_status = load_mutated(nil, function(runtime)
    runtime.characters[3].transitions[1].to_move_uid = "m2move_missing"
end)
assert(dangling_graph == nil)
expect_failure(dangling_status, "invalid_artifact")

local duplicate_graph, duplicate_status = load_mutated(nil, function(runtime)
    local moves = runtime.characters[2].moves
    moves[2].current_move_uid = moves[1].current_move_uid
    for _, ms in ipairs(moves[2].memberships) do
        ms.move_uid = moves[1].current_move_uid
    end
end)
assert(duplicate_graph == nil)
expect_failure(duplicate_status, "duplicate_move_uid")

local role_graph, role_status = load_mutated(nil, function(runtime)
    runtime.characters[1].moves[1].memberships[1].role = "shared"
end)
assert(role_graph == nil)
expect_failure(role_status, "invalid_artifact")
assert(role_status.message:find("strictness") ~= nil,
    "role/strictness mismatch must be reported")

local thrown_graph, thrown_status = CurrentMoveGraph.load({
    dir = FIXTURE_DIR,
    sha256 = function() error("simulated hash failure") end,
})
assert(thrown_graph == nil)
expect_failure(thrown_status, "internal_error")

print("current move graph loader tests passed")
