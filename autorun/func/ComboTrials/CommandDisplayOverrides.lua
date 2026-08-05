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

local function read_button_masks(entry)
    if type(entry) ~= "table" or entry.button_masks == nil then return nil, true end
    if type(entry.button_masks) ~= "table" then return nil, false end
    local masks = {}
    local count = 0
    for _, value in ipairs(entry.button_masks) do
        local mask = action_id(value)
        if mask == nil or mask <= 0 or mask > 0xFFF0
            or (mask & 0xF) ~= 0 or masks[mask] == true then
            return nil, false
        end
        masks[mask] = true
        count = count + 1
    end
    for key in pairs(entry.button_masks) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0
            or key > count then
            return nil, false
        end
    end
    if count == 0 then return nil, false end
    return masks, true
end

local function select_display(entry, mode)
    if mode == "classic" then return entry.classic end
    local commands = entry.commands
    if type(commands) ~= "table" then return nil end
    if mode ~= "motion" and mode ~= "all" then mode = "simple" end
    return commands[mode] or commands.simple or commands.motion or commands.all
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
    local conditioned = {}
    for action_id, entry in pairs(document.entries) do
        local id = tostring(action_id or "")
        local classic = type(entry) == "table" and valid_display(entry.classic) or nil
        local evidence = type(entry) == "table" and trim(entry.evidence) or ""
        local commands, commands_ok = read_modern_commands(entry)
        local button_masks, button_masks_ok = read_button_masks(entry)
        local existing = slim[id]
        local may_replace = type(entry) == "table" and entry.replace == true
        if id:match("^%d+$") and classic ~= nil and evidence ~= ""
            and commands_ok and button_masks_ok
            and (existing == nil or may_replace) then
            local resolved = {
                classic = classic,
                commands = commands,
                status = button_masks ~= nil
                    and "runtime_verified_conditioned_override"
                    or "runtime_verified_override",
                metadata = {
                    source = "command_display_override",
                    evidence = evidence,
                    control_support = commands and "classic_modern" or "classic_only",
                    replaced_existing = existing ~= nil,
                },
            }
            if button_masks ~= nil then
                resolved.button_masks = button_masks
                local numeric_id = tonumber(id)
                conditioned[numeric_id] = conditioned[numeric_id] or {}
                conditioned[numeric_id][#conditioned[numeric_id] + 1] = resolved
            else
                slim[id] = resolved
            end
            applied = applied + 1
        end
    end
    slim._contextual_internal_phases = contextual_phases
    slim._input_conditioned_entries = next(conditioned) ~= nil
        and conditioned or nil
    return slim, applied, "loaded"
end

function CommandDisplayOverrides.resolve_input_conditioned(
    command_map,
    requested_action_id,
    direct_input,
    newly_pressed,
    mode
)
    local id = action_id(requested_action_id)
    local conditioned = type(command_map) == "table"
        and command_map._input_conditioned_entries or nil
    local entries = id ~= nil and type(conditioned) == "table"
        and conditioned[id] or nil
    if type(entries) ~= "table" then return nil end
    local buttons = ((tonumber(direct_input) or 0)
        | (tonumber(newly_pressed) or 0)) & 0xFFF0
    for _, entry in ipairs(entries) do
        if type(entry.button_masks) == "table"
            and entry.button_masks[buttons] == true then
            local display = select_display(entry, mode)
            if display ~= nil then return display, entry.status, entry.metadata end
        end
    end
    return nil
end

function CommandDisplayOverrides.resolve_recorded_input_conditioned(
    command_map,
    requested_action_id,
    recorded_motion,
    mode
)
    local id = action_id(requested_action_id)
    local conditioned = type(command_map) == "table"
        and command_map._input_conditioned_entries or nil
    local entries = id ~= nil and type(conditioned) == "table"
        and conditioned[id] or nil
    local recorded = valid_display(recorded_motion)
    if type(entries) ~= "table" or recorded == nil then return nil end
    local normalized_recorded = recorded:upper()
    for _, entry in ipairs(entries) do
        local display = select_display(entry, mode)
        if type(display) == "string"
            and trim(display):upper() == normalized_recorded then
            return display, entry.status, entry.metadata
        end
    end
    return nil
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
