local M = {
    name = "ComboTrials.Type63StrengthSemantics",
    REASON = "ac_type63_classic_modern_strength_family",
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

local function expected_strength(strength)
    if strength == "medium" then
        return { classic = 32, modern = 128, classic_button = "MP", button = "中" }
    end
    if strength == "heavy" then
        return { classic = 64, modern = 256, classic_button = "HP", button = "强" }
    end
    return nil
end

local function relation_index(meta, audit)
    local relations = type(meta) == "table" and meta.type63_strength_variant_relations or nil
    local meta_relations = type(meta) == "table"
        and tonumber(meta.type63_strength_variant_relation_count) or nil
    local meta_routes = type(meta) == "table"
        and tonumber(meta.type63_strength_variant_route_count) or nil
    local audit_relations = type(audit) == "table"
        and tonumber(audit.type63_strength_variant_relation_count) or nil
    local audit_routes = type(audit) == "table"
        and tonumber(audit.type63_strength_variant_route_count) or nil
    if relations == nil and meta_relations == nil and meta_routes == nil
        and audit_relations == nil and audit_routes == nil then
        return {}
    end
    if strict_array(relations) == nil
        or meta_relations ~= #relations or audit_relations ~= #relations
        or meta_routes ~= #relations or audit_routes ~= #relations then
        return nil, "invalid_type63_strength_audit"
    end

    local by_target = {}
    for _, relation in ipairs(relations) do
        local source_id = type(relation) == "table" and integer(relation.source_action_id) or nil
        local target_id = type(relation) == "table" and integer(relation.target_action_id) or nil
        local strength = type(relation) == "table" and tostring(relation.strength or "") or ""
        local expected = expected_strength(strength)
        if source_id == nil or target_id == nil or source_id == target_id
            or by_target[target_id] ~= nil or tonumber(relation.branch_type) ~= 63
            or tostring(relation.reason or "") ~= M.REASON
            or expected == nil or tonumber(relation.classic_param01) ~= expected.classic
            or tonumber(relation.modern_param01) ~= expected.modern then
            return nil, "invalid_type63_strength_relation"
        end
        by_target[target_id] = {
            source_id = source_id,
            target_id = target_id,
            strength = strength,
            expected = expected,
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
    if declared == nil then return nil, "type63_strength_relation_not_found" end

    local source_id = declared.source_id
    local expected = declared.expected
    local entry = document[tostring(target_id)] or document[target_id]
    local source_entry = document[tostring(source_id)] or document[source_id]
    local character = type(meta) == "table" and tostring(meta.character or "") or ""
    if type(entry) ~= "table" or entry.ownership ~= "type63_strength_variant"
        or type(source_entry) ~= "table" or source_entry.ownership ~= "direct"
        or character == "" then
        return nil, "invalid_type63_strength_ownership"
    end
    local classic = type(entry) == "table" and compact_command(entry.classic_command) or nil
    local source_classic = type(source_entry) == "table"
        and compact_command(source_entry.classic_command) or nil
    local compact = type(classic) == "string" and classic:upper():gsub("%s+", "") or ""
    local source_compact = type(source_classic) == "string"
        and source_classic:upper():gsub("%s+", "") or ""
    local target_prefix, classic_button = compact:match("^(.*)([LMH]P)$")
    local source_prefix, source_button = source_compact:match("^(.*)([LMH]P)$")
    if classic_button ~= expected.classic_button
        or source_button ~= "LP" or target_prefix ~= source_prefix then
        return nil, "invalid_type63_strength_command"
    end

    local source_routes = type(source_entry) == "table" and source_entry.routes or nil
    local expected_route_display = nil
    local expected_direction = nil
    local source_route_count = 0
    if strict_array(source_routes) ~= nil then
        for _, source_route in ipairs(source_routes) do
            local candidates = type(source_route) == "table" and source_route.button_candidates or nil
            local source_display = type(source_route) == "table"
                and tostring(source_route.display or "") or ""
            local source_visible_button = type(source_route) == "table"
                and tostring(source_route.visible_button or "") or ""
            local valid_attack_candidates = strict_array(candidates) ~= nil and #candidates > 0
            if strict_array(candidates) ~= nil then
                for _, candidate in ipairs(candidates) do
                    if candidate ~= "弱" and candidate ~= "中" and candidate ~= "强" then
                        valid_attack_candidates = false
                        break
                    end
                end
            end
            local offset = nil
            local search_from = 1
            while source_visible_button ~= "" do
                local found = source_display:find(source_visible_button, search_from, true)
                if found == nil then break end
                offset = found
                search_from = found + #source_visible_button
            end
            if type(source_route) == "table"
                and source_route.source == "bcm_profile"
                and source_route.direct_evidence == true
                and source_route.inheritance_evidence == false
                and source_route.rebind_evidence == false
                and source_route.runtime_common_evidence == false
                and source_route.official_semantic_evidence == false
                and source_route.community_semantic_evidence == false
                and source_route.assist_combo_evidence == false
                and source_route.inheritance_reason == nil
                and source_route.rebind_reason == nil
                and source_route.runtime_common_reason == nil
                and source_route.official_semantic_reason == nil
                and source_route.community_semantic_reason == nil
                and source_route.assist_combo_reason == nil
                and tostring(source_route.confidence or "") == "direct_structural"
                and tostring(source_route.character or "") == character
                and integer(source_route.owner_action_id) == source_id
                and tonumber(source_route.required_button_count) == 1
                and valid_attack_candidates and offset ~= nil then
                expected_route_display = source_display:sub(1, offset - 1)
                    .. expected.button
                    .. source_display:sub(offset + #source_visible_button)
                expected_direction = tostring(source_route.visible_direction or "")
                source_route_count = source_route_count + 1
            end
        end
    end
    if source_route_count ~= 1 then return nil, "invalid_type63_strength_source_route" end

    local routes = type(entry) == "table" and entry.routes or nil
    local matching_routes = 0
    if strict_array(routes) ~= 1 then return nil, "invalid_type63_strength_route_count" end
    for _, route in ipairs(routes) do
        if type(route) == "table" and route.source == "ac_type63_strength_variant" then
            local path = route.ac_path
            local candidates = route.button_candidates
            if tostring(route.character or "") ~= character
                or integer(route.display_action_id) ~= target_id
                or integer(route.owner_action_id) ~= source_id
                or integer(route.bcm_owner_action_id) ~= source_id
                or integer(route.inherited_from_action_id) ~= source_id
                or tonumber(route.ac_relation_type) ~= 63
                or strict_array(path) == nil or #path < 2
                or integer(path[#path - 1]) ~= source_id or integer(path[#path]) ~= target_id
                or route.direct_evidence ~= false
                or route.inheritance_evidence ~= true
                or route.rebind_evidence ~= false
                or route.runtime_common_evidence ~= false
                or route.official_semantic_evidence ~= false
                or route.community_semantic_evidence ~= false
                or route.assist_combo_evidence ~= false
                or route.rebind_reason ~= nil
                or route.runtime_common_reason ~= nil
                or route.official_semantic_reason ~= nil
                or route.community_semantic_reason ~= nil
                or route.assist_combo_reason ~= nil
                or tostring(route.inheritance_reason or "") ~= M.REASON
                or tostring(route.confidence or "") ~= "verified_inherited_strength_variant"
                or tostring(route.strength or "") ~= declared.strength
                or tonumber(route.classic_param01) ~= expected.classic
                or tonumber(route.modern_param01) ~= expected.modern
                or tostring(route.visible_direction or "") ~= expected_direction
                or tostring(route.visible_button or "") ~= expected.button
                or strict_array(candidates) == nil or #candidates ~= 1
                or candidates[1] ~= expected.button
                or tonumber(route.required_button_count) ~= 1
                or tostring(route.display or "") ~= expected_route_display then
                return nil, "invalid_type63_strength_route"
            end
            matching_routes = matching_routes + 1
        end
    end
    if matching_routes ~= 1 then return nil, "invalid_type63_strength_route_count" end
    return {
        classic = classic,
        display = expected_route_display,
        source_action_id = source_id,
        target_action_id = target_id,
        strength = declared.strength,
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
