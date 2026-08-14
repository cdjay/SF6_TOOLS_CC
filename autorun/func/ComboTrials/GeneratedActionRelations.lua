local M = {
    name = "ComboTrials.GeneratedActionRelations",
    DIRECTORY = "TrainingComboTrials_data/command_display",
}

local Type63StrengthSemantics = require("func/ComboTrials/Type63StrengthSemantics")

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

local function exact_string_array(value, expected)
    if strict_array(value) ~= #expected then return false end
    for index, expected_value in ipairs(expected) do
        if value[index] ~= expected_value then return false end
    end
    return true
end

local function normalized_string_array(value)
    if strict_array(value) == nil then return nil end
    local normalized = {}
    for index, item in ipairs(value) do
        if type(item) ~= "string" then return nil end
        normalized[index] = item:upper():gsub("%s+", "")
    end
    return normalized
end

local function numeric_array_signature(value)
    if strict_array(value) == nil then return nil end
    local normalized = {}
    for index, item in ipairs(value) do
        local number = tonumber(item)
        if number == nil then return nil end
        normalized[index] = tostring(number)
    end
    return table.concat(normalized, ",")
end

local function command_route_signature(command, route)
    local inputs = type(command) == "table"
        and normalized_string_array(command.inputs) or nil
    local directions = type(route) == "table"
        and numeric_array_signature(route.raw_direction_inputs) or nil
    local numeric_fields = {
        "command_no", "command_index", "raw_button_mask",
        "raw_button_condition", "raw_dc_exc_flags", "raw_ng_key_flags",
    }
    if inputs == nil or directions == nil then return nil end
    local parts = { table.concat(inputs, ","), tostring(route.profile or ""), directions }
    for _, field_name in ipairs(numeric_fields) do
        local value = tonumber(route[field_name])
        if value == nil then return nil end
        parts[#parts + 1] = tostring(value)
    end
    return table.concat(parts, "|")
end

local function read_direct_bcm_commands(document)
    local commands = {}
    local phase_evidence = {}
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
                    if entry.ownership == "direct" then
                        local trigger_index = integer(route.trigger_index)
                        local signature = command_route_signature(command, route)
                        if trigger_index ~= nil and signature ~= nil then
                            phase_evidence[action_id] = phase_evidence[action_id] or {}
                            if phase_evidence[action_id][trigger_index] ~= nil then
                                phase_evidence[action_id][trigger_index] = false
                            else
                                phase_evidence[action_id][trigger_index] = signature
                            end
                        end
                    end
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
    return commands, phase_evidence
end

local function read_source_groups(meta, commands, phase_evidence)
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
    local phase_relations = type(meta) == "table"
        and meta.ac_command_phase_relations or nil
    local expected_phase_relations = type(audit) == "table"
        and tonumber(audit.ac_command_phase_relation_count) or nil
    local declared_phase_relations = type(meta) == "table"
        and tonumber(meta.ac_command_phase_relation_count) or nil
    if phase_relations == nil and expected_phase_relations == nil
        and declared_phase_relations == nil then
        phase_relations = {}
        expected_phase_relations = 0
        declared_phase_relations = 0
    end
    if strict_array(phase_relations) == nil
        or expected_phase_relations == nil
        or expected_phase_relations ~= #phase_relations
        or declared_phase_relations ~= expected_phase_relations then
        return nil, "invalid_command_phase_relation_audit"
    end

    for _, relation in ipairs(phase_relations) do
        local action_ids = type(relation) == "table" and relation.action_ids or nil
        local source_action_id = integer(relation and relation.source_action_id)
        local target_action_id = integer(relation and relation.target_action_id)
        local source_trigger_index = integer(relation and relation.source_trigger_index)
        local target_trigger_index = integer(relation and relation.target_trigger_index)
        if strict_array(action_ids) ~= 2
            or source_action_id == nil or target_action_id == nil
            or source_action_id == target_action_id
            or source_trigger_index == nil or target_trigger_index == nil
            or tonumber(relation.branch_type) ~= 52
            or tonumber(relation.attr) ~= 256
            or tonumber(relation.action_frame) ~= 0
            or tonumber(relation.param00) ~= 1
            or tonumber(relation.param01) ~= 3
            or not exact_string_array(relation.condition_delta_fields,
                { "kind_level", "limit_shot_category" })
            or not exact_string_array(relation.fingerprint_fields,
                { "Category", "Combo", "Projectile", "State" })
            or tostring(relation.reason or "")
                ~= "ac_type52_same_command_runtime_phase_family" then
            return nil, "invalid_command_phase_relation"
        end
        local left = integer(action_ids[1])
        local right = integer(action_ids[2])
        if left == nil or right == nil or left >= right
            or (source_action_id ~= left and source_action_id ~= right)
            or (target_action_id ~= left and target_action_id ~= right) then
            return nil, "invalid_command_phase_actions"
        end
        local left_command = commands[left]
        local right_command = commands[right]
        local source_signature = phase_evidence[source_action_id]
            and phase_evidence[source_action_id][source_trigger_index] or nil
        local target_signature = phase_evidence[target_action_id]
            and phase_evidence[target_action_id][target_trigger_index] or nil
        if left_command == nil or right_command == nil
            or left_command:upper():gsub("%s+", "")
                ~= right_command:upper():gsub("%s+", "")
            or type(source_signature) ~= "string"
            or source_signature ~= target_signature then
            return nil, "invalid_command_phase_commands"
        end
        local sorted = { left, right }
        table.sort(sorted)
        local key = "ac_command_phase:" .. table.concat(sorted, ",")
        for _, action_id in ipairs(sorted) do
            by_action[action_id] = by_action[action_id] or {}
            by_action[action_id][key] = true
        end
        group_count = group_count + 1
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
    local commands, phase_evidence = read_direct_bcm_commands(document)
    local type63_commands, type63_error = Type63StrengthSemantics.collect_commands(document)
    if type63_commands == nil then return nil, 0, type63_error end
    for action_id, command in pairs(type63_commands) do commands[action_id] = command end
    local by_action, count_or_error = read_source_groups(meta, commands, phase_evidence)
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
