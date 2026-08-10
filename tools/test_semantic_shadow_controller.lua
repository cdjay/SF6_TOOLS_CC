package.path = table.concat({
    "./autorun/?.lua",
    "./autorun/?/init.lua",
    package.path,
}, ";")

local SemanticShadowController =
    require("func/ComboTrials/Semantic/SemanticShadowController")

local written_path = nil
local written_report = nil
local failed = assert(SemanticShadowController.new({
    target_game_version = "2026-08-03",
    graph_loader = {
        load = function()
            return nil, { ok = false, code = "read_failed" }
        end,
    },
    write_json = function(path, value)
        written_path = path
        written_report = value
    end,
}))
assert(failed:install_expected(20, { { action_id = 965 } }))
local unavailable = assert(failed:compare_actual({ { action_id = 965 } }))
assert(unavailable.status == "unavailable")
assert(unavailable.reason == "semantic_graph_unavailable")
assert(unavailable.loader_status.code == "read_failed")
assert(written_path == "TrainingComboTrials_data/LastSemanticPlayerShadow.json")
assert(written_report == unavailable)

local resolver = {
    get_status = function()
        return { shadow_only = true, production_eligible = false }
    end,
}
local detector_calls = 0
local controller = assert(SemanticShadowController.new({
    target_game_version = "2026-08-03",
    graph_loader = {
        load = function()
            return { marker = true }, { ok = true, readiness = {
                production_ready = false,
            } }
        end,
    },
    resolver_factory = {
        new = function(options)
            assert(options.graph.marker == true and options.fighter_id == 20)
            return resolver
        end,
    },
    detector = {
        SCHEMA = "shadow.test",
        MODE = "shadow_test",
        compare = function(_, expected, actual, options)
            detector_calls = detector_calls + 1
            assert(expected[1].action_id == 965)
            assert(actual[1].action_id == 977)
            return {
                status = options.finalized and "matched" or "progress",
                match = options.finalized and true or nil,
                expected = { event_count = 1 },
                actual = { event_count = 1 },
                shadow_only = true,
                production_eligible = false,
            }
        end,
    },
}))
assert(controller:install_expected(20, { { action_id = 965 } }))
local matched = assert(controller:compare_actual(
    { { action_id = 977 } }, {
        finalized = true,
        atomic_status = "failed",
        atomic_match = false,
    }))
assert(matched.status == "matched" and matched.match == true)
assert(matched.atomic_status == "failed" and matched.atomic_match == false)
assert(matched.resolver_status.production_eligible == false)
assert(detector_calls == 1)

print("semantic shadow controller tests passed")
