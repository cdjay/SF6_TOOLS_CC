local M = {
    name = "ComboTrials.Type63DirectionalSemantics",
    REASON = "ac_type63_directional_followup_from_verified_bcm_owner",
}

local DIRECTION_BY_PARAM = {
    [1] = "8", [2] = "2", [4] = "4", [5] = "7",
    [6] = "1", [8] = "6", [9] = "9", [10] = "3",
}

local function integer(value)
    local number = tonumber(value)
    if number == nil or number < 0 or number % 1 ~= 0 then return nil end
    return number
end

local function strict_array(value)
    if type(value) ~= "table" then return nil end
    local count = #value
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > count then
            return nil
        end
    end
    return count
end

local function compact_command(command)
    local display = type(command) == "table" and command.display or nil
    if type(display) ~= "string" or display:match("^%s*(.-)%s*$") == ""
        or strict_array(command.inputs) == nil or #command.inputs == 0 then
        return nil
    end
    for _, input in ipairs(command.inputs) do
        if type(input) ~= "string" or input:match("^%s*(.-)%s*$") == "" then return nil end
    end
    return display:match("^%s*(.-)%s*$")
end

local function compact(value)
    return tostring(value or ""):upper():gsub("%s+", "")
end

local function relation_index(meta, audit)
    local relations = type(meta) == "table" and meta.type63_directional_followup_relations or nil
    local meta_relations = type(meta) == "table"
        and tonumber(meta.type63_directional_followup_relation_count) or nil
    local meta_routes = type(meta) == "table"
        and tonumber(meta.type63_directional_followup_route_count) or nil
    local audit_relations = type(audit) == "table"
        and tonumber(audit.type63_directional_followup_relation_count) or nil
    local audit_routes = type(audit) == "table"
        and tonumber(audit.type63_directional_followup_route_count) or nil
    if relations == nil and meta_relations == nil and meta_routes == nil
        and audit_relations == nil and audit_routes == nil then
        return {}
    end
    if strict_array(relations) == nil
        or meta_relations ~= #relations or audit_relations ~= #relations
        or meta_routes ~= #relations or audit_routes ~= #relations then
        return nil, "invalid_type63_directional_audit"
    end

    local by_target = {}
    for _, relation in ipairs(relations) do
        local source_id = type(relation) == "table" and integer(relation.source_action_id) or nil
        local target_id = type(relation) == "table" and integer(relation.target_action_id) or nil
        local direction = type(relation) == "table"
            and DIRECTION_BY_PARAM[tonumber(relation.param01)] or nil
        if source_id == nil or target_id == nil or source_id == target_id
            or by_target[target_id] ~= nil or tonumber(relation.branch_type) ~= 63
            or tonumber(relation.attr) ~= 0 or tonumber(relation.action_frame) ~= 0
            or tonumber(relation.param00) ~= 0 or tonumber(relation.param02) ~= 1
            or tonumber(relation.param03) ~= 0 or tonumber(relation.param04) ~= 0
            or tonumber(relation.param05) ~= 0 or tonumber(relation.trigger_id) ~= -1
            or direction == nil or tostring(relation.direction or "") ~= direction
            or compact(relation.display) ~= ">" .. direction .. "+P"
            or tostring(relation.reason or "") ~= M.REASON then
            return nil, "invalid_type63_directional_relation"
        end
        by_target[target_id] = {
            source_id = source_id,
            target_id = target_id,
            direction = direction,
            relation = relation,
        }
    end
    return by_target
end

function M.validate_audit(meta, audit)
    local index, error_code = relation_index(meta, audit)
    return index ~= nil, error_code
end

function M.validate_target(document, target_action_id)
    local target_id = integer(target_action_id)
    local meta = type(document) == "table" and document._meta or nil
    local audit = type(meta) == "table" and meta.audit or nil
    local index, error_code = relation_index(meta, audit)
    if index == nil then return nil, error_code end
    local declared = target_id ~= nil and index[target_id] or nil
    if declared == nil then return nil, "type63_directional_relation_not_found" end

    local source_id = declared.source_id
    local direction = declared.direction
    local relation = declared.relation
    local entry = document[tostring(target_id)] or document[target_id]
    local source_entry = document[tostring(source_id)] or document[source_id]
    local character = type(meta) == "table" and tostring(meta.character or "") or ""
    if type(entry) ~= "table" or entry.ownership ~= "type63_directional_followup"
        or type(source_entry) ~= "table" or source_entry.ownership ~= "direct"
        or character == "" then
        return nil, "invalid_type63_directional_ownership"
    end

    local classic = compact_command(entry.classic_command)
    local source_classic = compact_command(source_entry.classic_command)
    if compact(classic) ~= ">" .. direction .. "+P" or compact(source_classic) ~= "J.P" then
        return nil, "invalid_type63_directional_command"
    end

    local source_route_count = 0
    if strict_array(source_entry.routes) ~= nil then
        for _, route in ipairs(source_entry.routes) do
            if type(route) == "table" and route.source == "bcm_profile"
                and route.direct_evidence == true and route.inheritance_evidence == false
                and route.rebind_evidence == false and route.runtime_common_evidence == false
                and route.official_semantic_evidence == false
                and route.community_semantic_evidence == false
                and route.assist_combo_evidence == false
                and tostring(route.confidence or "") == "direct_structural"
                and tostring(route.character or "") == character
                and integer(route.owner_action_id) == source_id then
                source_route_count = source_route_count + 1
            end
        end
    end
    if source_route_count == 0 then return nil, "invalid_type63_directional_source_route" end

    local routes = type(entry) == "table" and entry.routes or nil
    if strict_array(routes) ~= 1 then return nil, "invalid_type63_directional_route_count" end
    local route = routes[1]
    local path = type(route) == "table" and route.ac_path or nil
    local candidates = type(route) == "table" and route.button_candidates or nil
    if type(route) ~= "table" or route.source ~= "ac_type63_directional_followup"
        or tostring(route.character or "") ~= character
        or integer(route.display_action_id) ~= target_id
        or integer(route.owner_action_id) ~= source_id
        or integer(route.bcm_owner_action_id) ~= source_id
        or integer(route.inherited_from_action_id) ~= source_id
        or tonumber(route.ac_relation_type) ~= 63
        or strict_array(path) ~= 2 or integer(path[1]) ~= source_id or integer(path[2]) ~= target_id
        or route.direct_evidence ~= false or route.inheritance_evidence ~= true
        or route.rebind_evidence ~= false or route.runtime_common_evidence ~= false
        or route.official_semantic_evidence ~= false
        or route.community_semantic_evidence ~= false or route.assist_combo_evidence ~= false
        or route.rebind_reason ~= nil or route.runtime_common_reason ~= nil
        or route.official_semantic_reason ~= nil or route.community_semantic_reason ~= nil
        or route.assist_combo_reason ~= nil or route.projection_scope ~= "classic_only"
        or tostring(route.inheritance_reason or "") ~= M.REASON
        or tostring(route.confidence or "") ~= "verified_inherited_directional_followup"
        or tostring(route.profile or "") ~= "norm" or integer(route.trigger_index) == nil
        or tonumber(route.ac_attr) ~= tonumber(relation.attr)
        or tonumber(route.ac_action_frame) ~= tonumber(relation.action_frame)
        or tonumber(route.ac_param00) ~= tonumber(relation.param00)
        or tonumber(route.ac_param01) ~= tonumber(relation.param01)
        or tonumber(route.ac_param02) ~= tonumber(relation.param02)
        or tonumber(route.ac_param03) ~= tonumber(relation.param03)
        or tonumber(route.ac_param04) ~= tonumber(relation.param04)
        or tonumber(route.ac_param05) ~= tonumber(relation.param05)
        or tonumber(route.ac_trigger_id) ~= tonumber(relation.trigger_id)
        or tostring(route.visible_direction or "") ~= direction
        or tostring(route.visible_button or "") ~= "P"
        or strict_array(candidates) ~= 3 or candidates[1] ~= "LP"
        or candidates[2] ~= "MP" or candidates[3] ~= "HP"
        or tonumber(route.required_button_count) ~= 1
        or compact(route.display) ~= ">" .. direction .. "+P" then
        return nil, "invalid_type63_directional_route"
    end
    return {
        classic = classic,
        display = route.display,
        source_action_id = source_id,
        target_action_id = target_id,
        direction = direction,
    }
end

function M.collect_commands(document)
    local meta = type(document) == "table" and document._meta or nil
    local audit = type(meta) == "table" and meta.audit or nil
    local index, error_code = relation_index(meta, audit)
    if index == nil then return nil, error_code end
    local commands = {}
    for target_id in pairs(index) do
        local resolved, target_error = M.validate_target(document, target_id)
        if resolved == nil then return nil, target_error end
        commands[target_id] = resolved.classic
    end
    return commands
end

return M
