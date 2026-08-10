package.path = table.concat({
    "./autorun/?.lua",
    "./autorun/?/init.lua",
    package.path,
}, ";")

local fixture = dofile("tools/fixtures/current_move_graph/fixtures.lua")
local CurrentMoveGraph = require("func/ComboTrials/Semantic/CurrentMoveGraph")
local MoveResolver = require("func/ComboTrials/Semantic/MoveResolver")
local PlayerDetectorShadow =
    require("func/ComboTrials/Semantic/PlayerDetectorShadow")

local function clone(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = clone(item) end
    return out
end

local manifest_raw = "manifest"
local runtime_raw = "runtime"
local digest = string.rep("a", 64)
local graph, graph_status = CurrentMoveGraph.load({
    dir = "fixture",
    read_file = function(path)
        return path:find("export%-manifest") and manifest_raw or runtime_raw
    end,
    decode = function(raw)
        if raw == manifest_raw then
            local manifest = clone(fixture.manifest)
            manifest.artifacts.runtime_current.bytes = #runtime_raw
            manifest.artifacts.runtime_current.sha256 = digest
            return manifest
        end
        return clone(fixture.runtime)
    end,
    sha256 = function() return digest end,
})
assert(graph ~= nil and graph_status.ok == true)

local honda = assert(MoveResolver.new({ graph = graph, fighter_id = 20 }))
local resolver_status = honda:get_status()
assert(resolver_status.shadow_only == true)
assert(resolver_status.production_eligible == false)
assert(resolver_status.readiness.integration_candidate == false)

local unmapped = assert(honda:resolve_action(1))
assert(unmapped.status == "unresolved" and #unmapped.candidates == 0)
local mapped = assert(honda:resolve_action(965))
assert(mapped.status == "resolved" and #mapped.candidate_move_uids == 1)
local replacement = assert(honda:resolve_action(977))
assert(replacement.status == "resolved")
assert(replacement.candidate_move_uids[1]
    == assert(honda:resolve_action(976)).candidate_move_uids[1])
assert(replacement.candidates[1].role == "replacement")

local gief = assert(MoveResolver.new({ graph = graph, fighter_id = 6 }))
local shared = assert(gief:resolve_action(900))
assert(shared.status == "ambiguous" and #shared.candidate_move_uids == 2,
    "many-valued membership must remain ambiguous")

local expected = {
    { step = 1, occurrence = 1, action_id = 1 },
    { step = 2, occurrence = 1, action_id = 965 },
    { step = 3, occurrence = 2, action_id = 1 },
    { step = 4, occurrence = 1, action_id = 976 },
}
local actual = {
    { step = 1, occurrence = 1, action_id = 9 },
    { step = 2, occurrence = 1, action_id = 965 },
    { step = 3, occurrence = 1, action_id = 5 },
    { step = 4, occurrence = 1, action_id = 977 },
}
local matched = assert(PlayerDetectorShadow.compare(honda, expected, actual))
assert(matched.status == "matched" and matched.match == true)
assert(matched.expected.event_count == 2 and matched.actual.event_count == 2)
assert(#matched.expected.excluded == 2 and #matched.actual.excluded == 2)

local repeated = assert(PlayerDetectorShadow.project(honda, {
    { action_id = 965 }, { action_id = 1 }, { action_id = 965 },
}))
assert(repeated.event_count == 2)
assert(repeated.events[1].event_occurrence == 1
    and repeated.events[2].event_occurrence == 2,
    "ignored context must not deduplicate repeated Move occurrences")

local divergent = assert(PlayerDetectorShadow.compare(honda,
    { { action_id = 965 }, { action_id = 976 } },
    { { action_id = 965 }, { action_id = 961 } }))
assert(divergent.status == "diverged" and divergent.match == false)
assert(divergent.first_divergence.step == 2
    and divergent.first_divergence.reason == "move_mismatch")

local progress = assert(PlayerDetectorShadow.compare(honda,
    { { action_id = 965 }, { action_id = 976 } },
    { { action_id = 965 } }))
assert(progress.status == "progress" and progress.match == nil)
local missing = assert(PlayerDetectorShadow.compare(honda,
    { { action_id = 965 }, { action_id = 976 } },
    { { action_id = 965 } }, { finalized = true }))
assert(missing.status == "diverged"
    and missing.first_divergence.reason == "missing_expected")

local unavailable = assert(PlayerDetectorShadow.compare(honda,
    { { action_id = 1 }, { action_id = 9 } },
    { { action_id = 1 } }))
assert(unavailable.status == "unavailable"
    and unavailable.reason == "no_expected_move_memberships")

local ambiguous_match = assert(PlayerDetectorShadow.compare(gief,
    { { action_id = 900 } }, { { action_id = 903 } }))
assert(ambiguous_match.status == "matched",
    "ambiguous expected candidates may match a shared actual Move candidate")

assert(expected[1].action_id == 1 and #expected == 4,
    "Shadow projection must not mutate Atomic source data")

print("player detector shadow tests passed")
