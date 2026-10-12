-- Local list preferences and a read-only view of completed manual attempts.
local State = {}
State.__index = State

State.FAVORITES_FILE = "TrainingComboTrials_data/combo_favorites.json"
State.EVENTS_FILE = "SF6_TrainingRemoteControl_data/ComboTrialTelemetry/events.jsonl"

local function path_key(path)
    if type(path) ~= "string" or path == "" then return nil end
    return path:gsub("\\", "/"):lower()
end

local function stat_key(character, filename, control, combo_id)
    if type(character) ~= "string" or character == ""
        or type(filename) ~= "string" or filename == "" then return nil end
    local identity = type(combo_id) == "string" and combo_id ~= ""
        and ("id:" .. combo_id) or ("file:" .. filename:lower())
    return character:lower() .. "\0" .. identity .. "\0" .. tostring(control or "classic"):lower()
end

function State.new(deps)
    return setmetatable({
        deps = deps, favorites = {}, stats = {}, seen = {}, offset = 0,
        loaded = false, revision = 0,
    }, State)
end

function State:load_favorites()
    if self.loaded then return true end
    local ok, data = pcall(self.deps.load, State.FAVORITES_FILE)
    if not ok or data == nil then
        if ok then self.loaded = true end
        return ok
    end
    if type(data) ~= "table" or data.schema ~= "sf6cc.combo_favorites.v1"
        or type(data.paths) ~= "table" then return false end
    local favorites = {}
    local count = 0
    for key, value in pairs(data.paths) do
        count = count + 1
        if count > 4096 or type(key) ~= "string" or #key > 1024
            or path_key(key) ~= key or value ~= true then return false end
        favorites[key] = true
    end
    self.favorites = favorites
    self.loaded = true
    return true
end

function State:is_favorite(info)
    local key = type(info) == "table" and path_key(info.filepath) or nil
    return key ~= nil and self.favorites[key] == true
end

function State:toggle_favorite(info)
    if not self:load_favorites() then return false, "无法读取收藏记录" end
    local key = type(info) == "table" and path_key(info.filepath) or nil
    if not key then return false, "连段路径无效" end
    local next_favorites = {}
    for path in pairs(self.favorites) do next_favorites[path] = true end
    if next_favorites[key] then next_favorites[key] = nil else next_favorites[key] = true end
    local ok, saved = pcall(self.deps.save, State.FAVORITES_FILE, {
        schema = "sf6cc.combo_favorites.v1", paths = next_favorites,
    })
    if not ok or saved == false then return false, "收藏保存失败" end
    self.favorites = next_favorites
    self.revision = self.revision + 1
    return true
end

function State:refresh_stats()
    local ok, file = pcall(self.deps.open, State.EVENTS_FILE)
    if not ok or not file then return false end
    local size = file:seek("end")
    if not size then file:close() return false end
    if size < self.offset then
        self.offset, self.stats, self.seen = 0, {}, {}
    end
    file:seek("set", self.offset)
    while true do
        local start = file:seek()
        local line = file:read("*l")
        if not line then break end
        local finish = file:seek()
        -- Never consume an unfinished append.
        if finish == size and size > 0 then
            file:seek("set", size - 1)
            local last = file:read(1)
            if last ~= "\n" then self.offset = start break end
        end
        self.offset = finish
        if #line <= 65536 then
            local decoded, event = pcall(self.deps.decode, line)
            if decoded and type(event) == "table" and event.schema == "sf6cc.combo_attempt.v1"
                and type(event.event_id) == "string" and not self.seen[event.event_id]
                and type(event.combo) == "table" and type(event.runtime) == "table"
                and type(event.result) == "table" and event.runtime.source == "manual"
                and (event.result.outcome == "success" or event.result.outcome == "fail") then
                local key = stat_key(event.combo.character, event.combo.local_filename,
                    event.combo.declared_control, event.combo.combo_id)
                if key then
                    self.seen[event.event_id] = true
                    local stat = self.stats[key] or { attempts = 0, successes = 0 }
                    stat.attempts = stat.attempts + 1
                    if event.result.outcome == "success" then stat.successes = stat.successes + 1 end
                    self.stats[key] = stat
                end
            end
        end
    end
    file:close()
    return true
end

function State:stat(info)
    if type(info) ~= "table" then return nil end
    local filename = type(info.filepath) == "string" and info.filepath:match("([^/\\]+)$")
    local key = stat_key(info.character, filename, info.control_type, info.combo_id)
    return key and self.stats[key] or nil
end

function State:order(items, info_items, less)
    local order = {}
    for index = 1, #items do order[index] = index end
    table.sort(order, function(a, b)
        local af, bf = self:is_favorite(info_items[a]), self:is_favorite(info_items[b])
        if af ~= bf then return af end
        if less then return less(a, b) end
        return a < b
    end)
    return order
end

State._test = { path_key = path_key, stat_key = stat_key }
return State
