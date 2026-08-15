package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local FIXTURE_DIR = "tools/fixtures/current_move_graph"
local RUNTIME_PATH = FIXTURE_DIR .. "/runtime-current.v1.json"
local fixture_data = dofile(FIXTURE_DIR .. "/fixtures.lua")

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
    for key, item in pairs(value) do copy[key] = deep_copy(item) end
    return copy
end

local Telemetry = require("func/ComboTrials/Telemetry")
local function decode_fixture(raw)
    if raw:find("m5%-export%-manifest") then
        local copy = deep_copy(fixture_data.manifest)
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

local MoveResolver = require("func/ComboTrials/Semantic/MoveResolver")
local Shadow = require("func/ComboTrials/Semantic/MoveResolverShadow")
local UnifiedActionConsumer = require("func/ComboTrials/UnifiedActionConsumer")
local CommandDisplayOverrides = require("func/ComboTrials/CommandDisplayOverrides")

local resolver, status = MoveResolver.load({
    dir = FIXTURE_DIR,
    expected_display_version = "2026-08-03",
})
assert(resolver ~= nil and status.ok == true)
assert(resolver:get_readiness().production_ready == false)
local mutation_ok = pcall(function() resolver._graph = {} end)
assert(mutation_ok == false, "MoveResolver instance state must be read-only")

local replacement = resolver:resolve_action(20, 977)
assert(replacement.status == "PROVISIONAL")
assert(#replacement.current_move_uids == 1)
assert(replacement.candidates[1].role == "replacement")

local same_move = resolver:compare_actions(20, 976, 977)
assert(same_move.status == "SAME_MOVE" and same_move.equivalent == true)
assert(#same_move.shared_move_identities == 1)
assert(#same_move.shared_current_move_uids == 1)

local distinct_move = resolver:compare_actions(20, 965, 961)
assert(distinct_move.status == "DISTINCT_MOVE" and distinct_move.equivalent == false)

local ambiguous = resolver:resolve_action(6, 900)
assert(ambiguous.status == "AMBIGUOUS")
assert(#ambiguous.current_move_uids == 2)

local missing = resolver:resolve_action(20, 99999)
assert(missing.status == "NOT_FOUND" and #missing.candidates == 0)
assert(#missing.identities == 0,
    "runtime-only Actions must not acquire a fake stable Move identity")
assert(resolver:resolve_action("bad", 1).status == "INVALID_FIGHTER")
assert(resolver:resolve_action(20, "bad").status == "INVALID_ACTION")

local before_presentation = resolver:resolve_action(20, 976)
local command_map = {
    _slim = true,
    ["976"] = { classic = "236+P", status = "strict_route" },
}
local merged, applied = CommandDisplayOverrides.merge(command_map, "EHonda", {
    schema = CommandDisplayOverrides.SCHEMA,
    character = "EHonda",
    entries = {
        ["976"] = {
            classic = "DISPLAY ONLY",
            replace = true,
            evidence = "synthetic presentation isolation evidence",
        },
    },
})
assert(applied == 1 and merged["976"].classic == "DISPLAY ONLY")
local after_presentation = resolver:resolve_action(20, 976)
assert(after_presentation.status == before_presentation.status)
assert(table.concat(after_presentation.identities, ",")
    == table.concat(before_presentation.identities, ","),
    "presentation overrides must not alter resolver identity")

local agreement = Shadow.compare_match(resolver, {
    character = "EHonda",
    fighter_id = 20,
    expected_action_id = 976,
    observed_action_id = 977,
    legacy_matched = true,
    consumer = "detection",
})
assert(agreement.production_result == "legacy")
assert(agreement.difference_category == "IDENTITY_MATCH")
assert(agreement.severity == "INFO")

local unexpected = Shadow.compare_match(resolver, {
    character = "EHonda",
    fighter_id = 20,
    expected_action_id = 976,
    observed_action_id = 977,
    legacy_matched = false,
    consumer = "detection",
})
assert(unexpected.difference_category == "CANDIDATE_ONLY")
assert(unexpected.expected == false and unexpected.severity == "P1")

local compatibility = Shadow.compare_match(resolver, {
    character = "EHonda",
    fighter_id = 20,
    expected_action_id = 965,
    observed_action_id = 961,
    legacy_matched = true,
    expected_difference = true,
    compatibility_projection = true,
    consumer = "playback",
})
assert(compatibility.difference_category == "LEGACY_ONLY")
assert(compatibility.expected == true and compatibility.severity == "INFO")

local blocked = Shadow.compare_match(resolver, {
    character = "Zangief",
    fighter_id = 6,
    expected_action_id = 900,
    observed_action_id = 903,
    legacy_matched = false,
    consumer = "recording",
})
assert(blocked.difference_category == "UNKNOWN")
assert(blocked.severity == "BLOCKED")

local gateway = UnifiedActionConsumer.compare_expected_action_shadow(resolver, {
    character = "EHonda",
    fighter_id = 20,
    expected_action_id = 976,
    observed_action_id = 977,
    legacy_matched = true,
    consumer = "audit",
})
assert(gateway.difference_category == "IDENTITY_MATCH")
local unavailable = UnifiedActionConsumer.compare_expected_action_shadow(nil, {
    consumer = "display",
})
assert(unavailable.production_result == "legacy")
assert(unavailable.candidate_classification == "RESOLVER_UNAVAILABLE")

print("MoveResolver shadow tests passed")
