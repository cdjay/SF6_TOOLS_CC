local CommandDisplayOverrides = {
    name = "ComboTrials.CommandDisplayOverrides",
    DIRECTORY = "TrainingComboTrials_data/command_display_overrides",
    SCHEMA = "xt.command_display_overrides.v1",
}

local function trim(value)
    return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

local function valid_display(value)
    local display = trim(value)
    if display == "" then return nil end
    local upper = display:upper()
    if display:find("未识别", 1, true) ~= nil
        or upper:find("UNKNOWN", 1, true) ~= nil
        or upper:find("ACTION_", 1, true) ~= nil then
        return nil
    end
    return display
end

local function read_modern_commands(entry)
    if type(entry) ~= "table" or entry.commands == nil then return nil, true end
    if type(entry.commands) ~= "table" then return nil, false end
    local simple = valid_display(entry.commands.simple)
    local motion = valid_display(entry.commands.motion)
    if simple == nil or motion == nil then return nil, false end
    return {
        simple = simple,
        motion = motion,
        all = simple == motion and simple or (simple .. "/" .. motion),
    }, true
end

local function character_key(value)
    return tostring(value or ""):gsub("[^%w_]", "")
end

local function action_id(value)
    if type(value) == "number" then
        if value ~= value or value == math.huge or value == -math.huge
            or value < 0 or value % 1 ~= 0 then
            return nil
        end
        return value
    end
    local text = tostring(value or "")
    if not text:match("^%d+$") then return nil end
    local id = tonumber(text)
    if id == nil or id < 0 or id % 1 ~= 0 then return nil end
    return id
end

-- Contextual internal phases are presentation-only facts. They deliberately
-- do not participate in ActionEventCompiler or runtime matching: recordings
-- retain both real Action IDs, while the command table may hide a child only
-- after one of its exact, evidence-verified owners.
local function parse_contextual_internal_phases(document)
    local source = type(document) == "table"
        and document.contextual_internal_phases or nil
    if source == nil then return nil, true end
    if type(source) ~= "table" then return nil, false end

    local parsed = { _validated = true }
    local phase_count = 0
    for child_key, entry in pairs(source) do
        local child_id = action_id(child_key)
        local owners = type(entry) == "table" and entry.owner_ids or nil
        local evidence = type(entry) == "table" and trim(entry.evidence) or ""
        if child_id == nil or type(owners) ~= "table" or evidence == "" then
            return nil, false
        end

        local owner_set = {}
        local owner_count = 0
        for index, owner_value in ipairs(owners) do
            local owner_id = action_id(owner_value)
            if owner_id == nil or owner_id == child_id
                or owner_set[owner_id] == true then
                return nil, false
            end
            owner_set[owner_id] = true
            owner_count = owner_count + 1
        end
        for key in pairs(owners) do
            if type(key) ~= "number" or key < 1 or key % 1 ~= 0
                or key > owner_count then
                return nil, false
            end
        end
        if owner_count == 0 then return nil, false end

        parsed[child_id] = {
            owner_ids = owner_set,
            evidence = evidence,
        }
        phase_count = phase_count + 1
    end
    if phase_count == 0 then return nil, false end
    return parsed, true
end

function CommandDisplayOverrides.get_filename(character)
    local key = character_key(character)
    if key == "" then return nil end
    return CommandDisplayOverrides.DIRECTORY .. "/" .. key .. ".json"
end

function CommandDisplayOverrides.merge(slim, character, document)
    if type(slim) ~= "table" or slim._slim ~= true then
        return slim, 0, "invalid_command_map"
    end
    if type(document) ~= "table"
        or document.schema ~= CommandDisplayOverrides.SCHEMA
        or character_key(document.character) ~= character_key(character)
        or type(document.entries) ~= "table" then
        return slim, 0, "invalid_override_document"
    end

    local contextual_phases, contextual_ok =
        parse_contextual_internal_phases(document)
    if not contextual_ok then
        return slim, 0, "invalid_contextual_internal_phases"
    end

    local applied = 0
    for action_id, entry in pairs(document.entries) do
        local id = tostring(action_id or "")
        local classic = type(entry) == "table" and valid_display(entry.classic) or nil
        local evidence = type(entry) == "table" and trim(entry.evidence) or ""
        local commands, commands_ok = read_modern_commands(entry)
        local existing = slim[id]
        local may_replace = type(entry) == "table" and entry.replace == true
        if id:match("^%d+$") and classic ~= nil and evidence ~= ""
            and commands_ok
            and (existing == nil or may_replace) then
            slim[id] = {
                classic = classic,
                commands = commands,
                status = "runtime_verified_override",
                metadata = {
                    source = "command_display_override",
                    evidence = evidence,
                    control_support = commands and "classic_modern" or "classic_only",
                    replaced_existing = existing ~= nil,
                },
            }
            applied = applied + 1
        end
    end
    slim._contextual_internal_phases = contextual_phases
    return slim, applied, "loaded"
end

function CommandDisplayOverrides.is_contextual_internal_phase(
    command_map,
    previous_owner_id,
    child_action_id
)
    local previous_id = action_id(previous_owner_id)
    local child_id = action_id(child_action_id)
    local phases = type(command_map) == "table"
        and command_map._contextual_internal_phases or nil
    if previous_id == nil or child_id == nil
        or type(phases) ~= "table" or phases._validated ~= true then
        return false
    end
    local phase = phases[child_id]
    return type(phase) == "table"
        and type(phase.owner_ids) == "table"
        and phase.owner_ids[previous_id] == true
end

function CommandDisplayOverrides.load_and_merge(slim, character, loader)
    local filename = CommandDisplayOverrides.get_filename(character)
    if filename == nil or type(loader) ~= "function" then
        return slim, 0, "loader_unavailable"
    end
    local ok, document = pcall(loader, filename)
    if not ok or type(document) ~= "table" then
        return slim, 0, "override_not_found"
    end
    return CommandDisplayOverrides.merge(slim, character, document)
end

return CommandDisplayOverrides
