local M = {
    name = "ComboTrials.GeneratedActionRelations",
    DIRECTORY = "TrainingComboTrials_data/command_display",
}

local SUPPORTED_GENERATORS = {
    ac_bcm = true,
    ["ac_bcm+capcom_official_semantics"] = true,
}

local function character_key(value)
    return tostring(value or ""):gsub("[^%w_]", "")
end

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

local function read_direct_bcm_commands(document)
    local commands = {}
    for key, entry in pairs(document) do
        local action_id = integer(key)
        local command = type(entry) == "table" and entry.classic_command or nil
        local display = type(command) == "table" and command.display or nil
        local routes = type(entry) == "table" and entry.routes or nil
        local direct_bcm_route = false
        if strict_array(routes) ~= nil then
            for _, route in ipairs(routes) do
                if type(route) == "table"
                    and route.source == "bcm_profile"
                    and route.direct_evidence == true
                    and integer(route.owner_action_id) == action_id then
                    direct_bcm_route = true
                    break
                end
            end
        end
        if action_id ~= nil and type(display) == "string"
            and display:match("^%s*(.-)%s*$") ~= ""
            and strict_array(command.inputs) ~= nil and #command.inputs > 0
            and direct_bcm_route then
            local valid = true
            for _, input in ipairs(command.inputs) do
                if type(input) ~= "string" or input:match("^%s*(.-)%s*$") == "" then
                    valid = false
                    break
                end
            end
            if valid then commands[action_id] = display:match("^%s*(.-)%s*$") end
        end
    end
    return commands
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

local function read_type63_strength_commands(document, meta, commands)
    local audit = type(meta) == "table" and meta.audit or nil
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
        return true
    end
    if strict_array(relations) == nil
        or meta_relations ~= #relations or audit_relations ~= #relations
        or meta_routes ~= #relations or audit_routes ~= #relations then
        return nil, "invalid_type63_strength_audit"
    end

    local seen_targets = {}
    for _, relation in ipairs(relations) do
        local source_id = type(relation) == "table" and integer(relation.source_action_id) or nil
        local target_id = type(relation) == "table" and integer(relation.target_action_id) or nil
        local strength = type(relation) == "table" and tostring(relation.strength or "") or ""
        local expected = strength == "medium"
            and { classic = 32, modern = 128, classic_button = "MP", button = "中" }
            or (strength == "heavy"
                and { classic = 64, modern = 256, classic_button = "HP", button = "强" }
                or nil)
        if source_id == nil or target_id == nil or source_id == target_id
            or seen_targets[target_id] == true or tonumber(relation.branch_type) ~= 63
            or tostring(relation.reason or "") ~= "ac_type63_classic_modern_strength_family"
            or expected == nil or tonumber(relation.classic_param01) ~= expected.classic
            or tonumber(relation.modern_param01) ~= expected.modern then
            return nil, "invalid_type63_strength_relation"
        end

        local entry = document[tostring(target_id)] or document[target_id]
        local classic = type(entry) == "table" and compact_command(entry.classic_command) or nil
        local routes = type(entry) == "table" and entry.routes or nil
        local source_entry = document[tostring(source_id)] or document[source_id]
        local source_classic = type(source_entry) == "table"
            and compact_command(source_entry.classic_command) or nil
        local compact = type(classic) == "string" and classic:upper():gsub("%s+", "") or ""
        local source_compact = type(source_classic) == "string"
            and source_classic:upper():gsub("%s+", "") or ""
        local target_prefix, classic_button = compact:match("^(.*)([LMH]P)$")
        local source_prefix, source_button = source_compact:match("^(.*)([LMH]P)$")
        if strict_array(routes) == nil or classic_button ~= expected.classic_button
            or source_button ~= "LP" or target_prefix ~= source_prefix then
            return nil, "invalid_type63_strength_command"
        end

        local source_routes = type(source_entry) == "table" and source_entry.routes or nil
        local expected_route_display = nil
        local expected_direction = nil
        local source_route_count = 0
        if strict_array(source_routes) ~= nil then
            for _, source_route in ipairs(source_routes) do
                local candidates = type(source_route) == "table"
                    and source_route.button_candidates or nil
                local source_display = type(source_route) == "table"
                    and tostring(source_route.display or "") or ""
                local source_visible_button = type(source_route) == "table"
                    and tostring(source_route.visible_button or "") or ""
                local valid_attack_candidates = strict_array(candidates) ~= nil
                    and #candidates > 0
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

        local matching_routes = 0
        for _, route in ipairs(routes) do
            if type(route) == "table" and route.source == "ac_type63_strength_variant" then
                local path = route.ac_path
                local candidates = route.button_candidates
                if integer(route.display_action_id) ~= target_id
                    or integer(route.owner_action_id) ~= source_id
                    or integer(route.bcm_owner_action_id) ~= source_id
                    or integer(route.inherited_from_action_id) ~= source_id
                    or tonumber(route.ac_relation_type) ~= 63
                    or strict_array(path) == nil or #path < 2
                    or integer(path[#path - 1]) ~= source_id or integer(path[#path]) ~= target_id
                    or route.inheritance_evidence ~= true
                    or tostring(route.inheritance_reason or "")
                        ~= "ac_type63_classic_modern_strength_family"
                    or tostring(route.confidence or "") ~= "verified_inherited_strength_variant"
                    or tostring(route.strength or "") ~= strength
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
        commands[target_id] = classic
        seen_targets[target_id] = true
    end
    return true
end

local function read_source_groups(meta, commands)
    local relations = type(meta) == "table"
        and meta.ac_state_direction_relations or nil
    local audit = type(meta) == "table" and meta.audit or nil
    local expected_relations = type(audit) == "table"
        and tonumber(audit.ac_state_direction_relation_count) or nil
    local expected_routes = type(audit) == "table"
        and tonumber(audit.ac_state_direction_route_count) or nil
    if strict_array(relations) == nil
        or expected_relations == nil or expected_relations ~= #relations
        or expected_routes == nil or expected_routes ~= expected_relations
        or tonumber(meta.ac_state_direction_route_count) ~= expected_routes then
        return nil, "invalid_state_relation_audit"
    end

    local by_action = {}
    local group_count = 0
    for _, relation in ipairs(relations) do
        local source_ids = type(relation) == "table"
            and relation.source_action_ids or nil
        local is_state_source_group = type(source_ids) == "table"
            and #source_ids >= 2
            and tostring(relation.reason or "")
                == "ac_type20_multi_direction_state_choice"
        if is_state_source_group then
            if strict_array(source_ids) == nil then
                return nil, "invalid_state_source_group"
            end
            local members = {}
            local source_action_id = integer(relation.source_action_id)
            for _, value in ipairs(source_ids) do
                local action_id = integer(value)
                if action_id == nil or members[action_id] == true then
                    return nil, "invalid_state_source_group"
                end
                members[action_id] = true
            end
            if source_action_id == nil or members[source_action_id] ~= true then
                return nil, "invalid_state_source_action"
            end
            local source_command = commands[source_action_id]
            local command_conflict = false
            if source_command ~= nil then
                local normalized_source = source_command:upper():gsub("%s+", "")
                for action_id in pairs(members) do
                    local direct_command = commands[action_id]
                    if direct_command ~= nil
                        and direct_command:upper():gsub("%s+", "") ~= normalized_source then
                        command_conflict = true
                        break
                    end
                end
            end
            if source_command ~= nil and not command_conflict then
                local sorted = {}
                for action_id in pairs(members) do sorted[#sorted + 1] = action_id end
                table.sort(sorted)
                local key = "ac_state_source:" .. table.concat(sorted, ",")
                for action_id in pairs(members) do
                    by_action[action_id] = by_action[action_id] or {}
                    by_action[action_id][key] = true
                    commands[action_id] = source_command
                end
                group_count = group_count + 1
            end
        end
    end
    return by_action, group_count
end

function M.parse(document, character)
    local key = character_key(character)
    local meta = type(document) == "table" and document._meta or nil
    if key == "" or type(meta) ~= "table"
        or meta.schema ~= "xt.command_display.v1"
        or meta.strict_policy ~= "verified_action_graph_v1"
        or SUPPORTED_GENERATORS[tostring(meta.generated_from or "")] ~= true
        or character_key(meta.character) ~= key then
        return nil, 0, "invalid_generated_action_relations"
    end
    local commands = read_direct_bcm_commands(document)
    local type63_ok, type63_error = read_type63_strength_commands(document, meta, commands)
    if type63_ok == nil then return nil, 0, type63_error end
    local by_action, count_or_error = read_source_groups(meta, commands)
    if by_action == nil then return nil, 0, count_or_error end
    return {
        _validated = true,
        character = key,
        by_action = by_action,
        commands = commands,
    }, count_or_error, "loaded"
end

function M.command_for_action(relations, action_id)
    if type(relations) ~= "table" or relations._validated ~= true then return nil end
    return relations.commands[integer(action_id)]
end

function M.load(character, loader)
    local key = character_key(character)
    if key == "" or type(loader) ~= "function" then
        return nil, 0, "loader_unavailable"
    end
    local ok, document = pcall(loader, M.DIRECTORY .. "/" .. key .. ".json")
    if not ok or type(document) ~= "table" then
        return nil, 0, "generated_action_relations_not_found"
    end
    return M.parse(document, key)
end

function M.share_source_group(relations, left_action_id, right_action_id)
    if type(relations) ~= "table" or relations._validated ~= true then return false end
    local left = relations.by_action[integer(left_action_id)]
    local right = relations.by_action[integer(right_action_id)]
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    for group in pairs(left) do
        if right[group] == true then return true end
    end
    return false
end

return M
