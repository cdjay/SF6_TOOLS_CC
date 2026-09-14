-- Offline bank editing workflow. Adapters own JSON and storage, never game objects.
local Bank = require("tools/training_record_bank/core")
local M = { MAX_BYTES = 16 * 1024 * 1024 }

local function version_valid(value)
    return type(value) == "string" and #value == 64 and value:match("^[0-9a-f]+$") ~= nil
end
local function bytes_valid(value)
    return type(value) == "string" and #value > 0 and #value <= M.MAX_BYTES
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

function M.new(codec, storage)
    assert(type(codec) == "table" and type(codec.encode) == "function" and type(codec.decode) == "function")
    assert(type(storage) == "table" and type(storage.read) == "function" and type(storage.replace) == "function")
    local editor, version, busy, recovery_required
    local self = {}
    local function decode(bytes, fighter)
        if not bytes_valid(bytes) then error("invalid stored byte length") end
        local document = codec.decode(bytes)
        local candidate, err = Bank.open(document)
        if not candidate then error(err) end
        if candidate.snapshot().fighter_id ~= fighter then error("stored character mismatch") end
        return candidate
    end
    function self.snapshot() return editor and editor.snapshot() or nil end
    function self.is_dirty() return editor ~= nil and editor.is_dirty() end
    function self.needs_reload() return recovery_required == true end
    function self.has_saved_file() return editor ~= nil and version ~= nil end
    function self.close()
        if busy then return false, "operation in progress" end
        editor, version, recovery_required = nil, nil, false
        return true
    end
    function self.select(fighter)
        if busy then return false, "operation in progress" end
        -- A failed switch must not leave the old character editable under the new UI.
        editor, version, recovery_required = nil, nil, false
        local empty, err = Bank.empty(fighter)
        if not empty then return false, err end
        busy = true
        local ok, candidate, loaded_version = pcall(function()
            local bytes, token = storage.read(fighter)
            if bytes == nil and token == nil then return assert(Bank.open(empty)), nil end
            if not version_valid(token) then error("invalid storage read result") end
            return decode(bytes, fighter), token
        end)
        busy = false
        if not ok then return false, tostring(candidate) end
        editor, version = candidate, loaded_version
        return true
    end
    local function editable()
        if busy then return false, "operation in progress" end
        if not editor then return false, "no character bank loaded" end
        return true
    end
    for _, operation in ipairs({ "add_slot", "edit", "delete", "merge", "discard", "set_reference", "reference_plan", "stage" }) do
        self[operation] = function(...)
            local ok, err = editable()
            if not ok then return nil, err end
            return editor[operation](...)
        end
    end
    function self.save()
        local available, err = editable()
        if not available then return false, err end
        if recovery_required then return false, "reload required after uncertain storage result" end
        busy = true
        local attempted, committed_version = false, nil
        local ok, reason = editor.save(function(document)
            local expected = assert(Bank.open(document)).snapshot()
            local bytes = codec.encode(document)
            if not bytes_valid(bytes) then return false, "invalid encoded byte length" end
            local verified = decode(bytes, expected.fighter_id).snapshot()
            if not equal(expected, verified) then return false, "serialization changed recording data" end
            attempted = true
            local written, token = storage.replace(expected.fighter_id, bytes, version)
            if written ~= bytes or not version_valid(token) then return false, "unconfirmed storage publication" end
            committed_version = token
            return true
        end)
        busy = false
        if ok then version = committed_version
        elseif attempted then recovery_required = true end
        return ok, reason
    end
    return self
end

return M
