-- RecoverableJsonFile.lua
-- Small runtime JSON store with a validated recovery copy.
--
-- REFramework's json.dump_file() writes directly to the destination. If the
-- process exits during that write, the file may be left truncated. This store
-- writes and validates a recovery copy first, then writes the primary file.

local M = {}

local function non_blank(value)
    return type(value) == "string" and value:find("%S") ~= nil
end

local function log_warning(message)
    if log and log.warn then
        pcall(log.warn, "[RecoverableJsonFile] " .. tostring(message))
    end
end

local function read_text(path)
    if not fs or type(fs.read) ~= "function" then
        return nil, "fs.read unavailable"
    end
    local ok, value = pcall(fs.read, path)
    if not ok then return nil, tostring(value) end
    return type(value) == "string" and value or ""
end

local function write_text(path, value)
    if not fs or type(fs.write) ~= "function" then
        return false, "fs.write unavailable"
    end
    local ok, result = pcall(fs.write, path, value)
    if not ok then return false, tostring(result) end
    return true
end

local function decode_table(raw)
    if not non_blank(raw) then return nil, "empty" end
    if not json or type(json.load_string) ~= "function" then
        return nil, "json.load_string unavailable"
    end
    local ok, value = pcall(json.load_string, raw)
    if not ok then return nil, tostring(value) end
    if type(value) ~= "table" then return nil, "invalid JSON table" end
    return value
end

local function encode_table(value)
    if type(value) ~= "table" then return nil, "value must be a table" end
    if not json or type(json.dump_string) ~= "function" then
        return nil, "json.dump_string unavailable"
    end
    local ok, raw = pcall(json.dump_string, value, 4)
    if not ok then return nil, tostring(raw) end
    if not non_blank(raw) then return nil, "JSON serialization returned empty text" end
    local decoded, decode_error = decode_table(raw)
    if not decoded then return nil, "serialized JSON failed validation: " .. tostring(decode_error) end
    return raw
end

local function corrupt_path(path)
    local stamp = os.date and os.date("%Y%m%d-%H%M%S") or tostring(math.floor(os.clock() * 1000))
    local base = tostring(path):gsub("%.json$", "")
    return base .. ".corrupt-" .. tostring(stamp) .. ".json"
end

function M.new(primary_path, recovery_path)
    assert(type(primary_path) == "string" and primary_path ~= "", "primary_path is required")
    assert(type(recovery_path) == "string" and recovery_path ~= "", "recovery_path is required")

    local store = {
        primary_path = primary_path,
        recovery_path = recovery_path,
    }

    function store:save(value)
        local raw, encode_error = encode_table(value)
        if not raw then
            log_warning(self.primary_path .. " serialization failed: " .. tostring(encode_error))
            return false, encode_error
        end

        local recovery_ok, recovery_error = write_text(self.recovery_path, raw)
        if not recovery_ok then
            log_warning(self.recovery_path .. " write failed: " .. tostring(recovery_error))
            return false, recovery_error
        end

        local recovery_raw, recovery_read_error = read_text(self.recovery_path)
        local recovery_value, recovery_validation_error = decode_table(recovery_raw)
        if not recovery_value then
            local reason = recovery_read_error or recovery_validation_error
            log_warning(self.recovery_path .. " validation failed: " .. tostring(reason))
            return false, reason
        end

        local primary_ok, primary_error = write_text(self.primary_path, recovery_raw)
        if not primary_ok then
            log_warning(self.primary_path .. " write failed: " .. tostring(primary_error))
            return false, primary_error
        end

        local primary_raw, primary_read_error = read_text(self.primary_path)
        local primary_value, primary_validation_error = decode_table(primary_raw)
        if not primary_value then
            local reason = primary_read_error or primary_validation_error
            log_warning(self.primary_path .. " validation failed: " .. tostring(reason))
            return false, reason
        end

        return true
    end

    function store:load(default_value)
        default_value = type(default_value) == "table" and default_value or {}

        local primary_raw = read_text(self.primary_path)
        local primary_value = decode_table(primary_raw)
        if primary_value then return primary_value, "primary" end

        local recovery_raw = read_text(self.recovery_path)
        local recovery_value = decode_table(recovery_raw)
        if recovery_value then
            local restored = self:save(recovery_value)
            log_warning(self.primary_path .. (restored
                and " was restored from its recovery copy"
                or " recovery copy loaded, but primary restore failed"))
            return recovery_value, "recovered"
        end

        if not non_blank(primary_raw) and not non_blank(recovery_raw) then
            return default_value, "missing"
        end

        local damaged_raw = non_blank(primary_raw) and primary_raw or recovery_raw
        local archived_path = corrupt_path(self.primary_path)
        local archived = write_text(archived_path, damaged_raw)
        self:save(default_value)
        log_warning(self.primary_path .. (archived
            and " was invalid; damaged contents were archived to " .. archived_path
            or " was invalid and could not be archived"))
        return default_value, "reset"
    end

    return store
end

return M
