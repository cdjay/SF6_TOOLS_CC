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
    local type63_commands, type63_error = Type63StrengthSemantics.collect_commands(document)
    if type63_commands == nil then return nil, 0, type63_error end
    for action_id, command in pairs(type63_commands) do commands[action_id] = command end
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
