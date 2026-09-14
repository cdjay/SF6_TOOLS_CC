-- Offline codec. Disk input must first pass AtomicBankStore's strict JSON gate.
local Bank = require("tools/training_record_bank/core")
local Json = require("tools/training_record_bank/vendor/dkjson")
local M = { MAX_BYTES = 16 * 1024 * 1024 }

local function object(value)
    local keys = {}; for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    return setmetatable(value, { __jsontype = "object", __jsonorder = keys })
end
local function array(value) return setmetatable(value, { __jsontype = "array" }) end
local function shape(value, kind)
    local meta = type(value) == "table" and getmetatable(value)
    assert(meta and meta.__jsontype == kind, "JSON " .. kind .. " required")
end

local precise_number = { __tojson = function(box)
    local number = box[1]
    if number == 0 and 1 / number < 0 then return "-0.0" end
    local result = string.format("%.17g", number)
    -- JSON uses '.', even when the host Lua numeric locale uses another separator.
    local separator = string.format("%.1f", 0.5):match("^0(.-)5$")
    assert(separator and separator ~= "", "unsupported numeric locale")
    if separator ~= "." then
        local first, last = result:find(separator, 1, true)
        if first then result = result:sub(1, first - 1) .. "." .. result:sub(last + 1) end
    end
    return result
end }

local function normalize_numbers(value)
    for key, child in pairs(value) do
        if type(child) == "table" then normalize_numbers(child)
        elseif type(child) == "number" then
            if child % 1 == 0 and not (child == 0 and 1 / child < 0) then value[key] = math.tointeger(child)
            else value[key] = setmetatable({ child }, precise_number) end
        end
    end
end

function M.encode(document)
    local bank, reason = Bank.open(document)
    assert(bank, reason)
    local copy = bank.snapshot()
    object(copy); array(copy.records)
    array(copy.record_refs)
    for _, ref in ipairs(copy.record_refs) do object(ref) end
    for _, record in ipairs(copy.records) do
        object(record); object(record.recording)
        array(record.recording.input_buff)
        object(record.recording.fields); object(record.recording.input_fields)
    end
    -- Lua can receive integer-valued floats from SDK calls; emit integer JSON tokens.
    normalize_numbers(copy)
    local bytes, err = Json.encode(copy)
    assert(type(bytes) == "string" and #bytes > 0 and #bytes <= M.MAX_BYTES, err or "encoded bank exceeds bounds")
    return bytes
end

function M.decode(bytes)
    assert(type(bytes) == "string" and #bytes > 0 and #bytes <= M.MAX_BYTES, "stored bank exceeds bounds")
    local document, position, err = Json.decode(bytes, 1, Json.null)
    assert(not err and document ~= nil, err or "invalid bank JSON")
    assert(not bytes:sub(position):find("[^ \t\r\n]"), "trailing JSON data")
    shape(document, "object"); shape(document.records, "array")
    if document.schema ~= Bank.LEGACY_SCHEMA then
        shape(document.record_refs, "array")
        for _, ref in ipairs(document.record_refs) do shape(ref, "object") end
    end
    for _, record in ipairs(document.records) do
        shape(record, "object"); shape(record.recording, "object")
        shape(record.recording.input_buff, "array")
        shape(record.recording.fields, "object"); shape(record.recording.input_fields, "object")
    end
    local bank, reason = Bank.open(document)
    assert(bank, reason)
    return bank.snapshot()
end

return M
