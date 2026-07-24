package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local files = {}
local warnings = {}

fs = {
    read = function(path)
        return files[path] or ""
    end,
    write = function(path, value)
        files[path] = value
    end,
}

json = {
    dump_string = function(value)
        return "valid:" .. tostring(value.payload or "empty")
    end,
    load_string = function(raw)
        local payload = tostring(raw):match("^valid:(.+)$")
        if not payload then return nil end
        return { payload = payload }
    end,
}

log = {
    warn = function(message)
        warnings[#warnings + 1] = message
    end,
}

local RecoverableJsonFile = require("func/RecoverableJsonFile")
local primary = "TrainingComboTrials_data/CompletedTrials.json"
local recovery = "TrainingComboTrials_data/CompletedTrials.recovery.json"
local store = RecoverableJsonFile.new(primary, recovery)

local missing, missing_status = store:load({ payload = "default" })
assert(missing.payload == "default" and missing_status == "missing",
    "missing files must use defaults without reporting corruption")

assert(store:save({ payload = "old" }) == true, "initial save must succeed")
assert(files[primary] == "valid:old" and files[recovery] == "valid:old",
    "save must write matching validated primary and recovery files")

files[primary] = "{truncated"
local recovered, recovered_status = store:load({ payload = "default" })
assert(recovered.payload == "old" and recovered_status == "recovered",
    "invalid primary must recover the last valid payload")
assert(files[primary] == "valid:old",
    "recovery must repair the primary file")

files[primary] = "{broken-primary"
files[recovery] = "{broken-recovery"
local reset, reset_status = store:load({ payload = "empty" })
assert(reset.payload == "empty" and reset_status == "reset",
    "two invalid copies must reset to defaults")
assert(files[primary] == "valid:empty" and files[recovery] == "valid:empty",
    "reset must rebuild both JSON copies")

local archived = false
for path, raw in pairs(files) do
    if path:find("CompletedTrials.corrupt%-", 1) and raw == "{broken-primary" then
        archived = true
    end
end
assert(archived, "unrecoverable primary contents must be archived")
assert(#warnings >= 2, "recovery and reset must leave diagnostic warnings")

print("recoverable JSON file tests passed")
