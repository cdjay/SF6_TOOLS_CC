local CurrentMoveGraph = require("func/ComboTrials/Semantic/CurrentMoveGraph")

local MoveResolver = {
    name = "ComboTrials.Semantic.MoveResolver",
}

local Resolver = {}
Resolver.__index = Resolver
Resolver.__newindex = function()
    error("MoveResolver is read-only", 2)
end

local RESOLVER_STATE = setmetatable({}, { __mode = "k" })

local function resolver_state(resolver)
    return assert(RESOLVER_STATE[resolver], "invalid MoveResolver instance")
end

local function integer(value)
    local number = tonumber(value)
    if number == nil or number % 1 ~= 0 then return nil end
    return number
end

local function copy_array(value)
    local result = {}
    for index, item in ipairs(value or {}) do result[index] = item end
    return result
end

local function sorted_keys(set)
    local result = {}
    for key in pairs(set) do result[#result + 1] = key end
    table.sort(result)
    return result
end

local function candidate_identity(move)
    if type(move.stable_move_uid) == "string" and move.stable_move_uid ~= "" then
        return move.stable_move_uid, "stable"
    end
    return move.current_move_uid, "current_provisional"
end

local function candidate_from(entry)
    local move = entry.move
    local membership = entry.membership
    local identity, identity_kind = candidate_identity(move)
    return {
        identity = identity,
        identity_kind = identity_kind,
        current_move_uid = move.current_move_uid,
        stable_move_uid = move.stable_move_uid,
        revision_uid = move.revision_uid,
        provisional = move.provisional == true,
        role = membership.role,
        strictness = membership.strictness,
        action_id = membership.action_id,
        evidence = membership.evidence,
    }
end

local function invalid_resolution(code, message, fighter_id, action_id)
    return {
        status = code,
        message = message,
        fighter_id = fighter_id,
        action_id = action_id,
        candidates = {},
        identities = {},
        current_move_uids = {},
        production_ready = false,
    }
end

function Resolver:get_readiness()
    return resolver_state(self).readiness
end

function Resolver:resolve_action(fighter_id, action_id)
    fighter_id = integer(fighter_id)
    action_id = integer(action_id)
    if fighter_id == nil or fighter_id < 0 then
        return invalid_resolution("INVALID_FIGHTER", "fighter_id must be an integer", fighter_id, action_id)
    end
    if action_id == nil or action_id < 0 then
        return invalid_resolution("INVALID_ACTION", "action_id must be an integer", fighter_id, action_id)
    end

    local state = resolver_state(self)
    local entries = state.graph:get_moves_by_action(fighter_id, action_id)
    local candidates = {}
    local identities = {}
    local current_moves = {}
    local unresolved = false
    local provisional = false

    for index, entry in ipairs(entries) do
        local candidate = candidate_from(entry)
        candidates[index] = candidate
        identities[candidate.identity] = true
        current_moves[candidate.current_move_uid] = true
        unresolved = unresolved or candidate.role == "unresolved"
            or candidate.strictness == "UNRESOLVED"
        provisional = provisional or candidate.provisional
            or candidate.identity_kind ~= "stable"
    end

    local identity_list = sorted_keys(identities)
    local current_move_uids = sorted_keys(current_moves)
    local status
    if #candidates == 0 then
        status = "NOT_FOUND"
    elseif unresolved then
        status = "UNRESOLVED"
    elseif #identity_list > 1 then
        status = "AMBIGUOUS"
    elseif provisional then
        status = "PROVISIONAL"
    else
        status = "RESOLVED"
    end

    return {
        status = status,
        fighter_id = fighter_id,
        action_id = action_id,
        candidates = candidates,
        identities = identity_list,
        current_move_uids = current_move_uids,
        move_identity = #identity_list == 1 and identity_list[1] or nil,
        current_move_uid = #current_move_uids == 1 and current_move_uids[1] or nil,
        production_ready = state.readiness.production_ready == true,
        authority = state.readiness.authority,
        build = state.build,
    }
end

function Resolver:compare_actions(fighter_id, left_action_id, right_action_id)
    local left = self:resolve_action(fighter_id, left_action_id)
    local right = self:resolve_action(fighter_id, right_action_id)
    local right_identities = {}
    for _, identity in ipairs(right.identities) do right_identities[identity] = true end
    local shared_identities = {}
    for _, identity in ipairs(left.identities) do
        if right_identities[identity] then shared_identities[#shared_identities + 1] = identity end
    end
    local right_moves = {}
    for _, move_uid in ipairs(right.current_move_uids) do right_moves[move_uid] = true end
    local shared = {}
    for _, move_uid in ipairs(left.current_move_uids) do
        if right_moves[move_uid] then shared[#shared + 1] = move_uid end
    end

    local status
    local equivalent
    if left.status == "INVALID_FIGHTER" or left.status == "INVALID_ACTION"
        or right.status == "INVALID_FIGHTER" or right.status == "INVALID_ACTION" then
        status = "INVALID"
    elseif left.status == "NOT_FOUND" or right.status == "NOT_FOUND" then
        status = "NOT_COMPARABLE"
    elseif left.status == "UNRESOLVED" or right.status == "UNRESOLVED"
        or left.status == "AMBIGUOUS" or right.status == "AMBIGUOUS" then
        status = #shared_identities > 0 and "OVERLAP_AMBIGUOUS" or "UNKNOWN"
    elseif #shared_identities == 1 then
        status = "SAME_MOVE"
        equivalent = true
    else
        status = "DISTINCT_MOVE"
        equivalent = false
    end

    return {
        status = status,
        equivalent = equivalent,
        fighter_id = integer(fighter_id),
        left_action_id = integer(left_action_id),
        right_action_id = integer(right_action_id),
        shared_move_identities = copy_array(shared_identities),
        shared_current_move_uids = copy_array(shared),
        left = left,
        right = right,
        production_ready = resolver_state(self).readiness.production_ready == true,
    }
end

function MoveResolver.new(graph)
    if type(graph) ~= "table"
        or type(graph.get_moves_by_action) ~= "function"
        or type(graph.get_readiness) ~= "function"
        or type(graph.get_build_info) ~= "function" then
        return nil, {
            ok = false,
            code = "invalid_graph",
            message = "graph must implement the CurrentMoveGraph query contract",
        }
    end
    local readiness = graph:get_readiness()
    local resolver = setmetatable({}, Resolver)
    RESOLVER_STATE[resolver] = {
        graph = graph,
        readiness = readiness,
        build = graph:get_build_info(),
    }
    return resolver, {
        ok = true,
        readiness = readiness,
    }
end

function MoveResolver.load(options)
    local graph, graph_status = CurrentMoveGraph.load(options)
    if graph == nil then return nil, graph_status end
    local resolver, resolver_status = MoveResolver.new(graph)
    resolver_status.graph = graph_status
    return resolver, resolver_status
end

return MoveResolver
