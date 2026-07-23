-- Shared JSONL transport for training telemetry.
-- Lua only writes anonymous events. The external tray owns authentication,
-- retry state and network upload.

local M = {}

local JSON_ESCAPES = {
    ['"'] = '\\"',
    ['\\'] = '\\\\',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t'
}

local event_counter = 0

local function encode_string(value)
    return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(character)
        return JSON_ESCAPES[character] or string.format("\\u%04x", string.byte(character))
    end) .. '"'
end

local function table_is_array(value)
    local count, maximum = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        count = count + 1
        if key > maximum then maximum = key end
    end
    return count > 0 and count == maximum
end

local function encode_json(value, stack)
    local value_type = type(value)
    if value_type == "nil" then return "null" end
    if value_type == "boolean" then return value and "true" or "false" end
    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return "null" end
        return tostring(value)
    end
    if value_type == "string" then return encode_string(value) end
    if value_type ~= "table" then return "null" end

    stack = stack or {}
    if stack[value] then error("cyclic table cannot be encoded") end
    stack[value] = true

    local parts = {}
    if table_is_array(value) then
        for index = 1, #value do parts[#parts + 1] = encode_json(value[index], stack) end
        stack[value] = nil
        return "[" .. table.concat(parts, ",") .. "]"
    end

    local keys = {}
    for key in pairs(value) do
        if type(key) == "string" or type(key) == "number" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = encode_string(tostring(key)) .. ":" .. encode_json(value[key], stack)
    end
    stack[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

function M.encode_json(value)
    return encode_json(value)
end

function M.iso8601_utc()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

function M.new_id(prefix)
    event_counter = event_counter + 1
    local clock = math.floor((tonumber(os.clock()) or 0) * 1000000) % 0x1000000
    return string.format("%s-%08x-%06x-%04x", tostring(prefix or "event"), os.time(), clock, event_counter % 0x10000)
end

function M.ensure_directories(directories)
    if not fs or not fs.create_dir then return end
    for _, directory in ipairs(directories or {}) do
        pcall(fs.create_dir, directory)
    end
end

function M.append_jsonl(path, event, directories)
    M.ensure_directories(directories)
    local file, open_error = io.open(path, "ab")
    if not file then return false, tostring(open_error or "open failed") end
    local ok, write_error = pcall(function()
        file:write(encode_json(event), "\n")
        file:flush()
    end)
    file:close()
    if not ok then return false, tostring(write_error) end
    return true
end

return M
