-- Bounded native-recorder initialization. Managed calls live in DynamicRecords.
local M = {}
local Layout = require("SF6CCTrainingLibrary/TrainingSlotLayout")

function M.new(adapter, owner, slots)
    assert(#slots > 0 and #slots <= Layout.NATIVE_RECORDS, "initialization exceeds supported recording count")
    local seen = {}
    for _, slot in ipairs(slots) do
        assert(type(slot.slot)=="number" and slot.slot%1==0 and slot.slot>=1
            and slot.slot<=Layout.NATIVE_RECORDS and not seen[slot.slot], "invalid initialization slot")
        assert(type(slot.required)=="number" and slot.required%1==0
            and slot.required>=1 and slot.required<=3600, "invalid initialization buffer length")
        seen[slot.slot]=true
    end
    -- Each native initialization takes 13 update callbacks. Keep the original
    -- small-job limits, and budget large banks without an unbounded retry loop.
    local max_ticks = math.max(240, #slots * 20 + 60)
    local max_seconds = math.max(10, math.ceil(max_ticks / 30))
    local session, data, fighter = owner.session, owner.data, owner.fighter_id
    local record_func = owner.record_func
    local index, phase, frames, ticks = 1, "start", 0, 0
    local started_at, active, changed, ended, failure = os.time(), false, false, false, nil
    local task = {}
    local function same_context(ctx)
        return ctx and ctx.allowed == true and not ctx.error and ctx.session == session
            and ctx.data == data and ctx.fighter_id == fighter
            and ctx.record_func == record_func
    end
    local function failed(message)
        ended = true
        return true, false, tostring(message) .. "; original configuration remains in pre-import backup"
    end
    local function restore()
        if changed then adapter.restore(); changed = false end
    end
    local function advance(ctx)
        if ended then return true, false, "Import operation already finished" end
        if not same_context(ctx) then return failed("Training environment changed; import cancelled") end
        ticks = ticks + 1
        if ticks > max_ticks or os.time() - started_at > max_seconds then failure = failure or "Initialization timed out" end
        if ctx.menu_closed ~= true or ctx.replay ~= false or ctx.combo_busy ~= false then
            failure = failure or "Training interrupted during initialization"
        elseif not active and ctx.busy ~= false then
            failure = failure or "Recorder busy before initialization"
        end
        if failure and phase ~= "stop" then
            if active then adapter.idle(); phase = "stop"; return false end
            restore(); return failed(failure)
        end
        if phase == "start" then
            -- Mark ownership before calls so a partially failing start is cleaned up.
            active, changed = true, true
            adapter.start(slots[index].slot)
            phase, frames = "wait", 0
        elseif phase == "wait" then
            frames = frames + 1
            if frames >= 11 then adapter.idle(); phase = "stop" end
        elseif phase == "stop" then
            -- WTT stops on the update after changing back to normal training state.
            adapter.stop(); active = false
            if failure then restore(); return failed(failure) end
            if adapter.capacity(slots[index].slot) < slots[index].required then
                restore(); return failed("Native recording buffer was not initialized")
            end
            index = index + 1
            if index <= #slots then phase = "start" else phase = "finish" end
        elseif phase == "finish" then
            restore()
            ended = true
            return true, adapter.finish()
        end
        return false
    end
    function task.tick(ctx)
        local result = table.pack(pcall(advance, ctx))
        if result[1] then return table.unpack(result, 2, result.n) end
        failure = "Initialization failed: " .. tostring(result[2])
        -- Do not retry arbitrary failing native calls; best-effort cleanup is bounded.
        task.cancel(ctx)
        return failed(failure)
    end
    function task.cancel(ctx)
        if ended then return end
        ended = true
        if not same_context(ctx) then return end
        -- Script reset cannot yield to another update. Never touch a replaced session.
        if active then pcall(adapter.idle); pcall(adapter.stop); active = false end
        pcall(restore)
    end
    return task
end

return M
