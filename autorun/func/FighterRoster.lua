-- FighterRoster.lua
-- Single fighter roster for SF6CC Lua modules.
--
-- data/SF6CC/fighters.json is the only place that maps a native fighter ID to
-- the SF6CC key that names per-fighter data (command_display/<key>.json,
-- exceptions/<key>.json, CustomCombos/<key>/) and to display names. Tools read
-- the same file. A fighter that is not in the roster yet still gets a stable,
-- distinct key (ESF_034) so recording, saving and character switching keep
-- working on the day a new fighter is released.

local FighterRoster = {
    name = "FighterRoster",
    FILE = "SF6CC/fighters.json",
    SCHEMA = "sf6cc.fighter_roster.v1",
    UNKNOWN = "Unknown",
    -- app.EPlayerType also carries World Tour gimmick values from 60 upwards.
    MAX_FIGHTER_ID = 59,
}

local state = nil
local injected_document = nil

local function report_error(message)
    pcall(function()
        local registry = _G._mod_errors
        if type(registry) == "table" and type(registry.list) == "table" then
            registry.count = (registry.count or 0) + 1
            registry.list[#registry.list + 1] = {
                ctx = "FighterRoster",
                err = tostring(message),
                t = os.clock(),
            }
        end
        if log and log.error then log.error("[SF6CC] " .. tostring(message)) end
    end)
end

local function integer(value)
    local number = tonumber(value)
    if number == nil or number % 1 ~= 0 then return nil end
    return math.tointeger(number) or number
end

local function non_empty_string(value)
    return type(value) == "string" and value:match("^%s*(.-)%s*$") ~= ""
end

local function build_state(document)
    if type(document) ~= "table" or document.schema ~= FighterRoster.SCHEMA then
        return nil, "invalid roster schema"
    end
    local fighters = document.fighters
    if type(fighters) ~= "table" or #fighters == 0 then
        return nil, "roster has no fighters"
    end
    local result = { by_id = {}, by_key = {}, by_display = {}, fighters = {} }
    for index, entry in ipairs(fighters) do
        local id = type(entry) == "table" and integer(entry.id) or nil
        local key = type(entry) == "table" and entry.key or nil
        if id == nil or id < 1 or id > FighterRoster.MAX_FIGHTER_ID then
            return nil, "fighter #" .. index .. " has an invalid id"
        end
        if type(key) ~= "string" or not key:match("^[A-Za-z][A-Za-z0-9_]*$") then
            return nil, "fighter " .. id .. " has an invalid key"
        end
        if not non_empty_string(entry.name_en) or not non_empty_string(entry.name_zh) then
            return nil, "fighter " .. key .. " is missing a display name"
        end
        if result.by_id[id] ~= nil or result.by_key[key:lower()] ~= nil then
            return nil, "duplicate fighter id or key: " .. key
        end
        local aliases = {}
        if entry.aliases ~= nil then
            if type(entry.aliases) ~= "table" then
                return nil, "fighter " .. key .. " aliases must be a list"
            end
            for _, alias in ipairs(entry.aliases) do
                if not non_empty_string(alias) then
                    return nil, "fighter " .. key .. " has an empty alias"
                end
                aliases[#aliases + 1] = alias
            end
        end
        local fighter = {
            id = id,
            key = key,
            esf_key = string.format("ESF_%03d", id),
            name_en = entry.name_en,
            name_zh = entry.name_zh,
            official_slug = type(entry.official_slug) == "string" and entry.official_slug or nil,
            aliases = aliases,
        }
        result.by_id[id] = fighter
        result.by_key[key:lower()] = fighter
        result.fighters[#result.fighters + 1] = fighter
        for _, name in ipairs({ key, fighter.name_en, table.unpack(aliases) }) do
            local existing = result.by_display[name]
            if existing ~= nil and existing ~= fighter then
                return nil, "display name '" .. name .. "' is used by two fighters"
            end
            result.by_display[name] = fighter
        end
    end
    return result
end

local function document_loader()
    if injected_document ~= nil then
        return function() return injected_document end
    end
    if type(_G.safe_load_json) == "function" then return _G.safe_load_json end
    if type(json) == "table" and type(json.load_file) == "function" then
        return json.load_file
    end
    return nil
end

-- Returns the loaded roster state, or nil plus a reason. A failed read is
-- cached so per-frame callers never retry disk IO; reload() clears it. When
-- no JSON loader exists at all (standalone tests), nothing is cached.
function FighterRoster.load()
    if state ~= nil then
        if state.ok then return state end
        return nil, state.error
    end
    local loader = document_loader()
    if loader == nil then return nil, "json loader unavailable" end
    local ok, document = pcall(loader, FighterRoster.FILE)
    local built, err = nil, nil
    if not ok then
        err = "cannot read " .. FighterRoster.FILE .. ": " .. tostring(document)
    else
        built, err = build_state(document)
    end
    if built == nil then
        state = { ok = false, error = err or "roster unavailable" }
        report_error("角色名单 " .. FighterRoster.FILE .. " 无法使用：" .. tostring(state.error))
        return nil, state.error
    end
    built.ok = true
    state = built
    return state
end

function FighterRoster.reload()
    state = nil
    return FighterRoster.load()
end

-- Test seam: use a decoded document instead of the runtime file.
function FighterRoster.use_document(document)
    injected_document = document
    state = nil
end

function FighterRoster.status()
    local loaded, err = FighterRoster.load()
    return {
        loaded = loaded ~= nil,
        error = err,
        count = loaded and #loaded.fighters or 0,
    }
end

-- Accepts a native fighter ID, an "ESF_034" key, or the shared player info
-- table ({ id = 34, key = "ESF_034" }).
function FighterRoster.parse_fighter_id(value)
    if type(value) == "table" then
        local id = integer(value.id)
        if id ~= nil and id > 0 then return FighterRoster.parse_fighter_id(id) end
        return FighterRoster.parse_fighter_id(value.key)
    end
    if type(value) == "string" then
        local digits = value:match("^ESF_(%d+)$")
        if digits == nil then return nil end
        value = digits
    end
    local id = integer(value)
    if id == nil or id < 1 or id > FighterRoster.MAX_FIGHTER_ID then return nil end
    return id
end

function FighterRoster.fallback_key(value)
    local id = FighterRoster.parse_fighter_id(value)
    return id and string.format("ESF_%03d", id) or nil
end

function FighterRoster.fighter_by_id(value)
    local id = FighterRoster.parse_fighter_id(value)
    local loaded = id and FighterRoster.load() or nil
    return loaded and loaded.by_id[id] or nil
end

function FighterRoster.fighter_by_key(key)
    if type(key) ~= "string" or key == "" then return nil end
    local loaded = FighterRoster.load()
    return loaded and loaded.by_key[key:lower()] or nil
end

local function resolve(value)
    if type(value) == "string" and not value:match("^ESF_%d+$") then
        return FighterRoster.fighter_by_key(value)
    end
    return FighterRoster.fighter_by_id(value)
end

-- SF6CC data key for a fighter: the roster key, else ESF_<id> for a fighter
-- the roster does not know yet, else "Unknown" when no fighter is present.
function FighterRoster.profile_key(value)
    local fighter = FighterRoster.fighter_by_id(value)
    if fighter then return fighter.key end
    return FighterRoster.fallback_key(value) or FighterRoster.UNKNOWN
end

function FighterRoster.is_known(value)
    return resolve(value) ~= nil
end

function FighterRoster.name_en(value)
    local fighter = resolve(value)
    return fighter and fighter.name_en or nil
end

function FighterRoster.name_zh(value)
    local fighter = resolve(value)
    return fighter and fighter.name_zh or nil
end

-- Chinese name for an English display string stored in older files
-- ("Chun-Li", "A.K.I", "Viper", ...). Returns nil when the name is unknown.
function FighterRoster.zh_for_display_name(name)
    if type(name) ~= "string" or name == "" then return nil end
    local loaded = FighterRoster.load()
    local fighter = loaded and loaded.by_display[name] or nil
    return fighter and fighter.name_zh or nil
end

function FighterRoster.all()
    local loaded = FighterRoster.load()
    local result = {}
    for index, fighter in ipairs(loaded and loaded.fighters or {}) do
        result[index] = fighter
    end
    return result
end

return FighterRoster
