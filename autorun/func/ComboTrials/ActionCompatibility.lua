local ActionCompatibility = {
    name = "ComboTrials.ActionCompatibility",
    DIRECTORY = "TrainingComboTrials_data/action_compatibility",
    SCHEMA = "xt.action_compatibility.v1",
}

local function trim(value)
    return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

local function character_key(value)
    return tostring(value or ""):gsub("[^%w_]", "")
end

local function integer(value)
    local number = tonumber(value)
    if number == nil or number < 0 or number % 1 ~= 0 then return nil end
    return number
end

local function normalize_motion(value)
    local motion = trim(value):upper():gsub("%s+", "")
    motion = motion:gsub("DRIVERUSH", "RAWDR")
    motion = motion:gsub("LP%+LK", "THROW")
    motion = motion:gsub("%+", "")
    motion = motion:gsub("^>", "")
    return motion
end

local function parse_motion_set(value)
    if type(value) ~= "table" then return nil end
    local motions = {}
    local count = 0
    for index, motion in ipairs(value) do
        local normalized = normalize_motion(motion)
        if normalized == "" or motions[normalized] == true then return nil end
        motions[normalized] = true
        count = count + 1
        if index ~= count then return nil end
    end
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > count then
            return nil
        end
    end
    return count > 0 and motions or nil
end

local function parse_runtime_action_ids(entry, recorded_id, runtime_id)
    local ids = { [runtime_id] = true }
    local aliases = type(entry) == "table"
        and entry.runtime_action_alias_ids or nil
    if aliases == nil then return ids end
    if type(aliases) ~= "table" then return nil end
    local count = 0
    for index, value in ipairs(aliases) do
        local alias_id = integer(value)
        if alias_id == nil or alias_id == recorded_id
            or ids[alias_id] == true or index ~= count + 1 then
            return nil
        end
        ids[alias_id] = true
        count = count + 1
    end
    for key in pairs(aliases) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > count then
            return nil
        end
    end
    return count > 0 and ids or nil
end

function ActionCompatibility.get_filename(character)
    local key = character_key(character)
    if key == "" then return nil end
    return ActionCompatibility.DIRECTORY .. "/" .. key .. ".json"
end

function ActionCompatibility.parse(document, character, game_version)
    local key = character_key(character)
    local target_version = trim(game_version)
    if type(document) ~= "table"
        or document.schema ~= ActionCompatibility.SCHEMA
        or character_key(document.character) ~= key
        or trim(document.target_game_version) ~= target_version
        or target_version == ""
        or type(document.entries) ~= "table" then
        return nil, 0, "invalid_compatibility_document"
    end

    local parsed = {
        _validated = true,
        character = key,
        target_game_version = target_version,
        by_recorded_id = {},
    }
    local identities = {}
    local count = 0
    for index, entry in ipairs(document.entries) do
        local recorded_id = type(entry) == "table"
            and integer(entry.recorded_action_id) or nil
        local runtime_id = type(entry) == "table"
            and integer(entry.runtime_action_id) or nil
        local motions = type(entry) == "table"
            and parse_motion_set(entry.recorded_motions) or nil
        local runtime_ids = recorded_id ~= nil and runtime_id ~= nil
            and parse_runtime_action_ids(entry, recorded_id, runtime_id) or nil
        local evidence = type(entry) == "table" and trim(entry.evidence) or ""
        if recorded_id == nil or runtime_id == nil or recorded_id == runtime_id
            or motions == nil or runtime_ids == nil
            or evidence == "" or index ~= count + 1 then
            return nil, 0, "invalid_compatibility_entry"
        end

        local rules = parsed.by_recorded_id[recorded_id]
        if type(rules) ~= "table" then
            rules = {}
            parsed.by_recorded_id[recorded_id] = rules
        end
        for motion in pairs(motions) do
            local identity = tostring(recorded_id) .. ":" .. motion
            if identities[identity] ~= nil then
                return nil, 0, "ambiguous_compatibility_entry"
            end
            identities[identity] = true
        end
        rules[#rules + 1] = {
            runtime_action_id = runtime_id,
            runtime_action_ids = runtime_ids,
            recorded_motions = motions,
            evidence = evidence,
        }
        count = count + 1
    end
    for key_index in pairs(document.entries) do
        if type(key_index) ~= "number" or key_index < 1
            or key_index % 1 ~= 0 or key_index > count then
            return nil, 0, "invalid_compatibility_entries"
        end
    end
    if count == 0 then return nil, 0, "empty_compatibility_document" end
    return parsed, count, "loaded"
end

function ActionCompatibility.load(character, game_version, loader)
    local filename = ActionCompatibility.get_filename(character)
    if filename == nil or type(loader) ~= "function" then
        return nil, 0, "loader_unavailable"
    end
    local ok, document = pcall(loader, filename)
    if not ok or type(document) ~= "table" then
        return nil, 0, "compatibility_not_found"
    end
    return ActionCompatibility.parse(document, character, game_version)
end

function ActionCompatibility.resolve(rules, expected, observed_action_id)
    if type(rules) ~= "table" or rules._validated ~= true
        or type(expected) ~= "table" then
        return nil
    end
    local recorded_id = integer(expected.id)
    local motion = normalize_motion(expected.motion)
    local observed_id = observed_action_id == nil
        and nil or integer(observed_action_id)
    local candidates = recorded_id ~= nil
        and rules.by_recorded_id[recorded_id] or nil
    if motion == "" or type(candidates) ~= "table" then return nil end
    for _, candidate in ipairs(candidates) do
        if candidate.recorded_motions[motion] == true
            and (observed_id == nil
                or candidate.runtime_action_ids[observed_id] == true) then
            return candidate.runtime_action_id, candidate
        end
    end
    return nil
end

function ActionCompatibility.matches(rules, expected, observed_action_id)
    return ActionCompatibility.resolve(rules, expected, observed_action_id) ~= nil
end

function ActionCompatibility.project_step(rules, step)
    local runtime_id = ActionCompatibility.resolve(rules, step)
    if runtime_id == nil then return step, nil end
    local projected = {}
    for key, value in pairs(step) do projected[key] = value end
    projected._compat_recorded_action_id = step.id
    projected.id = runtime_id
    return projected, runtime_id
end

return ActionCompatibility
