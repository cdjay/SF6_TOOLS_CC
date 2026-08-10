-- SemanticShadowController.lua
-- Fail-open lifecycle owner for candidate-only player detection Shadow output.
-- It never changes production detector state or mutates its Atomic sources.

local CurrentMoveGraph = require("func/ComboTrials/Semantic/CurrentMoveGraph")
local MoveResolver = require("func/ComboTrials/Semantic/MoveResolver")
local PlayerDetectorShadow =
    require("func/ComboTrials/Semantic/PlayerDetectorShadow")

local SemanticShadowController = {
    name = "ComboTrials.Semantic.SemanticShadowController",
    DIAGNOSTIC_FILE = "TrainingComboTrials_data/LastSemanticPlayerShadow.json",
}

local Controller = {}
Controller.__index = Controller

local function is_integer(value, minimum)
    return type(value) == "number" and value % 1 == 0
        and value >= (minimum or 0)
end

local function clone(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = clone(item) end
    return out
end

function SemanticShadowController.new(options)
    options = type(options) == "table" and options or {}
    if type(options.target_game_version) ~= "string"
        or options.target_game_version == "" then
        return nil, "target_game_version_required"
    end
    return setmetatable({
        target_game_version = options.target_game_version,
        graph_loader = options.graph_loader or CurrentMoveGraph,
        graph_dir = options.graph_dir or CurrentMoveGraph.DIRECTORY,
        resolver_factory = options.resolver_factory or MoveResolver,
        detector = options.detector or PlayerDetectorShadow,
        write_json = options.write_json,
        graph = nil,
        graph_status = nil,
        graph_load_attempted = false,
        resolvers = {},
        expected = nil,
        fighter_id = nil,
        last_signature = nil,
        last_report = nil,
    }, Controller)
end

function Controller:clear()
    self.expected = nil
    self.fighter_id = nil
    self.last_signature = nil
    self.last_report = nil
end

function Controller:install_expected(fighter_id, expected_trace)
    if not is_integer(fighter_id, 1) then return nil, "invalid_fighter_id" end
    if type(expected_trace) ~= "table" then return nil, "expected_trace_required" end
    self.expected = expected_trace
    self.fighter_id = fighter_id
    self.last_signature = nil
    self.last_report = nil
    return true
end

function Controller:_load_graph()
    if self.graph_load_attempted then return self.graph, self.graph_status end
    self.graph_load_attempted = true
    local graph, status = self.graph_loader.load({
        dir = self.graph_dir,
        expected_display_version = self.target_game_version,
    })
    self.graph = graph
    self.graph_status = status
    return graph, status
end

function Controller:_resolver()
    local graph, graph_status = self:_load_graph()
    if graph == nil then return nil, graph_status end
    local resolver = self.resolvers[self.fighter_id]
    if resolver ~= nil then return resolver end
    local created, create_error = self.resolver_factory.new({
        graph = graph,
        fighter_id = self.fighter_id,
    })
    if created == nil then return nil, { code = create_error } end
    self.resolvers[self.fighter_id] = created
    return created
end

local function report_signature(report)
    local divergence = report.first_divergence
    return table.concat({
        tostring(report.status),
        tostring(report.expected and report.expected.event_count),
        tostring(report.actual and report.actual.event_count),
        tostring(divergence and divergence.step),
        tostring(divergence and divergence.reason),
    }, "|")
end

function Controller:compare_actual(actual_trace, options)
    options = type(options) == "table" and options or {}
    if self.expected == nil or self.fighter_id == nil then
        return nil, "expected_not_installed"
    end
    if type(actual_trace) ~= "table" then return nil, "actual_trace_required" end
    local resolver, resolver_error = self:_resolver()
    local report
    if resolver == nil then
        report = {
            schema = self.detector.SCHEMA,
            mode = self.detector.MODE,
            status = "unavailable",
            reason = "semantic_graph_unavailable",
            shadow_only = true,
            production_eligible = false,
            fighter_id = self.fighter_id,
            loader_status = clone(resolver_error),
        }
    else
        report = self.detector.compare(
            resolver, self.expected, actual_trace, options)
        if report == nil then return nil, "shadow_compare_failed" end
        report.fighter_id = self.fighter_id
        report.resolver_status = resolver:get_status()
        report.loader_status = clone(self.graph_status)
    end
    report.atomic_status = options.atomic_status
    report.atomic_match = options.atomic_match

    self.last_report = report
    local signature = report_signature(report)
    if signature ~= self.last_signature and type(self.write_json) == "function" then
        self.last_signature = signature
        pcall(self.write_json, SemanticShadowController.DIAGNOSTIC_FILE, report)
    end
    return report
end

function Controller:get_last_report()
    return clone(self.last_report)
end

return SemanticShadowController
