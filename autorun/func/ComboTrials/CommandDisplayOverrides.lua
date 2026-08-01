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
    return slim, applied, "loaded"
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
