-- Slot descriptions on the game's own record, playback and reversal lists for the
-- native eight-slot bank. Text substitution only: the hooks swap the format string
-- passed to the game's text writer; no menu rows, arrays or banks are created.
-- Hooks install once, from a closed-menu update of an active library session.
local Safety = require("SF6CCTrainingLibrary/Context")
local State = require("SF6CCTrainingLibrary/State")
local SharedLibrary = require("SF6CCTrainingLibrary/Library")
local Layout = require("SF6CCTrainingLibrary/TrainingSlotLayout")
local Names = require("SF6CCTrainingLibrary/NativeRecordingNames")
local Reversals = require("SF6CCTrainingLibrary/NativeReversalRecordings")

local M = {}
local RECORD_PAGE, PLAY_PAGE, RECORD_ROW, PLAY_ROW = 107, 108, 118, 131
local function read(obj, key) return obj and obj:get_field(key) end

-- Native slot rows carry their zero-based slot in _SlotID; the parent is the
-- record (107) or playback (108) page. Other rows are never renamed.
function M.slot_info(data, parent)
    local page, kind = read(parent, "_FuncType"), read(data, "_FuncType")
    if not ((page == RECORD_PAGE and kind == RECORD_ROW) or (page == PLAY_PAGE and kind == PLAY_ROW)) then
        return nil
    end
    local slot = read(data, "_SlotID")
    if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 0 or slot >= Layout.NATIVE_RECORDS then return nil end
    return { slot = slot + 1, page = page }
end

local stopped, installed = false, false
local menu = { slot_info = M.slot_info }
local cached_ctx, cached_entry
local function current()
    local runtime = State.runtime
    local ctx = not stopped and runtime and runtime.context and runtime.context()
    -- A legacy (>8) bank has no editable descriptions; leave its labels native.
    if not ctx or ctx.bank_unsupported then return nil end
    if ctx ~= cached_ctx then
        cached_ctx = ctx
        cached_entry = { phase = "active", manager = ctx.session, data = ctx.data,
            fighter_id = ctx.fighter_id, menu = menu }
    end
    return cached_entry
end
local function allowed() return not stopped and Safety.pause_open() == true end
local function report(message)
    if log and log.error then log.error("[NativeSlotNames] " .. tostring(message)) end
end

local function install()
    local library = SharedLibrary.shared()
    Names.new(sdk, thread, current, allowed, library, report).install()
    Reversals.new(sdk, thread, current, allowed, report, library, { expand = false }).install()
end

re.on_pre_application_entry("LateUpdateBehavior", function()
    if installed or stopped then return end
    local runtime = State.runtime
    if not (runtime and runtime.presentation_session and runtime.presentation_session()) then return end
    if Safety.pause_open() ~= false then return end
    installed = true
    local ok, err = pcall(install)
    if not ok then
        -- Any hook that did install stays inert through allowed()/current().
        stopped = true
        report("Stopped: " .. tostring(err))
    end
end)
re.on_script_reset(function() stopped = true end)

return M
