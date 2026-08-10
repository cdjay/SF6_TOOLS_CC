-- PlayerDetectorShadow.lua
-- Candidate-only player detection projection. Runtime Actions with no current
-- Move membership are excluded from comparison but retained in diagnostics.
-- Membership-bearing Actions, including AC follow-ups without direct BCM
-- bindings, remain ordered and duplicate-preserving.

local PlayerDetectorShadow = {
    name = "ComboTrials.Semantic.PlayerDetectorShadow",
    SCHEMA = "sf6cc.player_detector_shadow.v1",
    MODE = "current_move_membership_order_v1",
}

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

local function instances_from(source)
    if type(source) ~= "table" then return nil, "invalid_trace" end
    if type(source.get_instances) == "function" then
        return source:get_instances()
    end
    if type(source.instances) == "table" then return source.instances end
    if type(source[1]) == "table" then return source end
    return nil, "invalid_trace"
end

local function candidate_key(move_uids)
    return table.concat(move_uids, "|")
end

local function intersects(left, right)
    local seen = {}
    for _, uid in ipairs(left) do seen[uid] = true end
    for _, uid in ipairs(right) do
        if seen[uid] then return true, uid end
    end
    return false
end

function PlayerDetectorShadow.project(resolver, source)
    if type(resolver) ~= "table" or type(resolver.resolve_action) ~= "function" then
        return nil, "resolver_required"
    end
    local instances, trace_error = instances_from(source)
    if instances == nil then return nil, trace_error end

    local projection = {
        schema = PlayerDetectorShadow.SCHEMA,
        mode = PlayerDetectorShadow.MODE,
        status = "projected",
        shadow_only = true,
        production_eligible = false,
        source_count = 0,
        event_count = 0,
        events = {},
        excluded = {},
        ambiguous_count = 0,
    }
    local occurrence_counts = {}
    for index, instance in ipairs(instances) do
        if type(instance) ~= "table" or not is_integer(instance.action_id, 0) then
            return nil, "invalid_trace"
        end
        projection.source_count = index
        local resolution, resolution_error = resolver:resolve_action(instance.action_id)
        if resolution == nil then return nil, resolution_error end
        if resolution.status == "unresolved" then
            projection.excluded[#projection.excluded + 1] = {
                source_step = instance.step or index,
                action_id = instance.action_id,
                action_occurrence = instance.occurrence,
                reason = "no_current_move_membership",
            }
        else
            local key = candidate_key(resolution.candidate_move_uids)
            local occurrence = (occurrence_counts[key] or 0) + 1
            occurrence_counts[key] = occurrence
            local event = {
                event_step = #projection.events + 1,
                event_occurrence = occurrence,
                source_step = instance.step or index,
                action_id = instance.action_id,
                action_occurrence = instance.occurrence,
                resolution_status = resolution.status,
                candidate_key = key,
                candidate_move_uids = clone(resolution.candidate_move_uids),
                candidates = clone(resolution.candidates),
            }
            projection.events[#projection.events + 1] = event
            if resolution.status == "ambiguous" then
                projection.ambiguous_count = projection.ambiguous_count + 1
            end
        end
    end
    projection.event_count = #projection.events
    if projection.event_count == 0 then projection.status = "unavailable" end
    return projection
end

local function divergence(step, reason, expected, actual)
    return {
        step = step,
        reason = reason,
        expected = clone(expected),
        actual = clone(actual),
    }
end

function PlayerDetectorShadow.compare(resolver, expected_source, actual_source, options)
    options = type(options) == "table" and options or {}
    local expected, expected_error = PlayerDetectorShadow.project(
        resolver, expected_source)
    if expected == nil then return nil, expected_error end
    local actual, actual_error = PlayerDetectorShadow.project(
        resolver, actual_source)
    if actual == nil then return nil, actual_error end

    local report = {
        schema = PlayerDetectorShadow.SCHEMA,
        mode = PlayerDetectorShadow.MODE,
        status = "progress",
        match = nil,
        shadow_only = true,
        production_eligible = false,
        expected = expected,
        actual = actual,
        first_divergence = nil,
    }
    if expected.status == "unavailable" then
        report.status = "unavailable"
        report.reason = "no_expected_move_memberships"
        return report
    end

    local compared = math.min(expected.event_count, actual.event_count)
    for step = 1, compared do
        local compatible, shared_uid = intersects(
            expected.events[step].candidate_move_uids,
            actual.events[step].candidate_move_uids)
        if not compatible then
            report.status = "diverged"
            report.match = false
            report.first_divergence = divergence(step, "move_mismatch",
                expected.events[step], actual.events[step])
            return report
        end
        report.last_shared_move_uid = shared_uid
    end

    if actual.event_count > expected.event_count then
        local step = expected.event_count + 1
        report.status = "diverged"
        report.match = false
        report.first_divergence = divergence(step, "unexpected_extra",
            nil, actual.events[step])
        return report
    end
    if actual.event_count < expected.event_count then
        if options.finalized == true then
            local step = actual.event_count + 1
            report.status = "diverged"
            report.match = false
            report.first_divergence = divergence(step, "missing_expected",
                expected.events[step], nil)
        end
        return report
    end

    report.status = "matched"
    report.match = true
    return report
end

return PlayerDetectorShadow
