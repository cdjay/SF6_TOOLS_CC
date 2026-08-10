-- MoveResolver.lua
-- Single current-build semantic query boundary for Shadow consumers.
-- It preserves every Move membership returned by CurrentMoveGraph and never
-- mutates Combo V2, Raw traces, Replay data, Legacy rules or presentation.

local MoveResolver = {
    name = "ComboTrials.Semantic.MoveResolver",
    SCHEMA = "sf6cc.move_resolution.shadow.v1",
}

local Resolver = {}
Resolver.__index = Resolver

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

local function candidate_from(entry)
    local move = entry.move
    local membership = entry.membership
    return {
        move_uid = move.current_move_uid,
        revision_uid = move.revision_uid,
        stable_move_uid = move.stable_move_uid,
        provisional = move.provisional == true,
        role = membership.role,
        strictness = membership.strictness,
        context_key = membership.context_key,
    }
end

local function candidate_less(left, right)
    if left.move_uid ~= right.move_uid then return left.move_uid < right.move_uid end
    if left.role ~= right.role then return left.role < right.role end
    return tostring(left.context_key or "") < tostring(right.context_key or "")
end

function MoveResolver.new(options)
    options = type(options) == "table" and options or {}
    local graph = options.graph
    local fighter_id = options.fighter_id
    if type(graph) ~= "table"
        or type(graph.get_moves_by_action) ~= "function"
        or type(graph.get_readiness) ~= "function"
        or type(graph.get_build_info) ~= "function" then
        return nil, "graph_required"
    end
    if not is_integer(fighter_id, 1) then return nil, "invalid_fighter_id" end
    local character = graph:get_character(fighter_id)
    if character == nil then return nil, "character_not_found" end
    local readiness = graph:get_readiness()
    if readiness.load_success ~= true then return nil, "graph_not_loaded" end
    return setmetatable({
        graph = graph,
        fighter_id = fighter_id,
        character = character.character,
        readiness = clone(readiness),
        build = clone(graph:get_build_info()),
    }, Resolver)
end

function Resolver:get_status()
    return {
        schema = MoveResolver.SCHEMA,
        fighter_id = self.fighter_id,
        character = self.character,
        build = clone(self.build),
        readiness = clone(self.readiness),
        shadow_only = true,
        production_eligible = self.readiness.production_ready == true,
    }
end

function Resolver:resolve_action(action_id)
    if not is_integer(action_id, 0) then return nil, "invalid_action_id" end
    local entries = self.graph:get_moves_by_action(self.fighter_id, action_id)
    local candidates = {}
    for _, entry in ipairs(entries) do
        candidates[#candidates + 1] = candidate_from(entry)
    end
    table.sort(candidates, candidate_less)

    local move_uids = {}
    local seen = {}
    for _, candidate in ipairs(candidates) do
        if seen[candidate.move_uid] ~= true then
            seen[candidate.move_uid] = true
            move_uids[#move_uids + 1] = candidate.move_uid
        end
    end

    local status = "unresolved"
    if #move_uids == 1 then
        status = "resolved"
    elseif #move_uids > 1 then
        status = "ambiguous"
    end
    return {
        schema = MoveResolver.SCHEMA,
        fighter_id = self.fighter_id,
        character = self.character,
        action_id = action_id,
        status = status,
        candidates = candidates,
        candidate_move_uids = move_uids,
        shadow_only = true,
        production_eligible = false,
    }
end

return MoveResolver
