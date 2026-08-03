local Catalog = {}

Catalog.COMMAND_DIR = "TrainingComboTrials_data/command_display"

local CHARACTER_BY_KEY = {
    ESF_001 = { id = 1, name = "Ryu" },
    ESF_002 = { id = 2, name = "Luke" },
    ESF_003 = { id = 3, name = "Kimberly" },
    ESF_004 = { id = 4, name = "ChunLi" },
    ESF_005 = { id = 5, name = "Manon" },
    ESF_006 = { id = 6, name = "Zangief" },
    ESF_007 = { id = 7, name = "JP" },
    ESF_008 = { id = 8, name = "Dhalsim" },
    ESF_009 = { id = 9, name = "Cammy" },
    ESF_010 = { id = 10, name = "Ken" },
    ESF_011 = { id = 11, name = "DeeJay" },
    ESF_012 = { id = 12, name = "Lily" },
    ESF_013 = { id = 13, name = "AKI" },
    ESF_014 = { id = 14, name = "Rashid" },
    ESF_015 = { id = 15, name = "Blanka" },
    ESF_016 = { id = 16, name = "Juri" },
    ESF_017 = { id = 17, name = "Marisa" },
    ESF_018 = { id = 18, name = "Guile" },
    ESF_019 = { id = 19, name = "Ed" },
    ESF_020 = { id = 20, name = "EHonda" },
    ESF_021 = { id = 21, name = "Jamie" },
    ESF_022 = { id = 22, name = "Akuma" },
    ESF_025 = { id = 25, name = "Sagat" },
    ESF_026 = { id = 26, name = "MBison" },
    ESF_027 = { id = 27, name = "Terry" },
    ESF_028 = { id = 28, name = "Mai" },
    ESF_029 = { id = 29, name = "Elena" },
    ESF_030 = { id = 30, name = "CViper" },
    ESF_031 = { id = 31, name = "Alex" },
    ESF_032 = { id = 32, name = "Ingrid" },
    ESF_033 = { id = 33, name = "Yasmine" }
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function command_display(entry)
    for _, key in ipairs({ "classic_command", "motion_command", "simple_command" }) do
        local command = type(entry) == "table" and entry[key] or nil
        local display = type(command) == "table" and trim(command.display) or ""
        if display ~= "" then return display end
    end
    return nil
end

local function is_attack_like(display)
    local upper = tostring(display or ""):upper()
    return upper:find("P", 1, true) ~= nil
        or upper:find("K", 1, true) ~= nil
        or upper:find("弱", 1, true) ~= nil
        or upper:find("中", 1, true) ~= nil
        or upper:find("强", 1, true) ~= nil
end

function Catalog.resolve_character(info)
    info = type(info) == "table" and info or {}
    local key = type(info.key) == "string" and info.key or nil
    local definition = key and CHARACTER_BY_KEY[key] or nil
    if not definition then
        local id = tonumber(info.id)
        if id then
            key = string.format("ESF_%03d", id)
            definition = CHARACTER_BY_KEY[key]
        end
    end
    if not definition then return nil end
    return {
        id = tonumber(info.id) or definition.id,
        key = key,
        name = definition.name,
        display_name = definition.name
    }
end

function Catalog.from_document(character, document)
    local source = type(document) == "table" and (document.actions or document) or {}
    local moves = {}
    for raw_id, entry in pairs(source) do
        local action_id = tonumber(raw_id)
        local display = command_display(entry)
        if action_id and display and display ~= "" and display ~= "N" then
            local derived = display:match("^%s*>") ~= nil
            moves[#moves + 1] = {
                action_id = action_id,
                action_ids = { action_id },
                command = display,
                is_derived = derived,
                is_attack_like = is_attack_like(display),
                ownership = type(entry) == "table" and entry.ownership or nil
            }
        end
    end
    table.sort(moves, function(left, right) return left.action_id < right.action_id end)

    local labels = {}
    local starter_labels = {}
    local followup_labels = {}
    for index, move in ipairs(moves) do
        local prefix = ""
        if move.is_derived then
            local previous = moves[index - 1]
            if previous and not previous.is_derived and move.action_id == previous.action_id + 1 then
                move.parent_action_id = previous.action_id
                move.parent_command = previous.command
                prefix = "[派生·接 " .. tostring(previous.command) .. "] "
            else
                prefix = "[派生] "
            end
        end
        move.label = string.format("%s%s  [ID %d]", prefix, move.command, move.action_id)
        labels[index] = move.label
        starter_labels[index] = "前置：" .. move.label
        followup_labels[index] = "后续：" .. move.label
    end
    return {
        character = character,
        moves = moves,
        labels = labels,
        starter_labels = starter_labels,
        followup_labels = followup_labels
    }
end

function Catalog.load(character)
    if type(character) ~= "table" or type(character.name) ~= "string" then
        return Catalog.from_document(character, nil), "character unavailable"
    end
    local path = Catalog.COMMAND_DIR .. "/" .. character.name .. ".json"
    local document = nil
    if _G.safe_load_json then
        local ok, value = pcall(_G.safe_load_json, path)
        if ok then document = value end
    elseif json and json.load_file then
        local ok, value = pcall(json.load_file, path)
        if ok then document = value end
    end
    if type(document) ~= "table" then
        return Catalog.from_document(character, nil), "cannot load " .. path
    end
    return Catalog.from_document(character, document)
end

function Catalog.find_index(moves, action_id)
    action_id = tonumber(action_id)
    for index, move in ipairs(moves or {}) do
        if move.action_id == action_id then return index end
    end
    return nil
end

function Catalog.default_starter_index(moves)
    for index, move in ipairs(moves or {}) do
        if move.is_attack_like and not move.is_derived then return index end
    end
    return #moves > 0 and 1 or nil
end

function Catalog.default_followup_index(moves, starter_index)
    for index = (tonumber(starter_index) or 0) + 1, #moves do
        if moves[index].is_derived then return index end
    end
    for index, move in ipairs(moves or {}) do
        if index ~= starter_index and move.is_attack_like then return index end
    end
    return #moves > 0 and 1 or nil
end

return Catalog
