-- Offline-tested orchestration contract. A verified native adapter is still required.
-- Remember a chosen bank; reload once per training entry, never save on exit.
local M = {}

function M.new(make_session, native, context, last_fighter)
    assert(type(make_session) == "function" and type(context) == "function")
    for _, key in ipairs({"prepare", "attach", "retire", "discard_prepared", "capture"}) do
        assert(type(native[key]) == "function", "missing native adapter operation: " .. key)
    end
    assert(last_fighter == nil or (type(last_fighter) == "number" and last_fighter >= 0
        and last_fighter % 1 == 0), "invalid remembered character")
    local active, blocked, busy, retained = nil, false, false, {}
    local remembered_fighter, last_attempt = last_fighter, nil
    local self = {}

    local function read_context()
        local ok, ctx = pcall(context)
        if not ok or type(ctx) ~= "table" then return nil, "training context unavailable" end
        return {allowed=ctx.allowed, idle=ctx.idle, session=ctx.session,
            data=ctx.data, fighter_id=ctx.fighter_id}
    end
    local function valid(ctx)
        return ctx and ctx.allowed == true and ctx.session ~= nil and ctx.data ~= nil
            and type(ctx.fighter_id) == "number" and ctx.fighter_id >= 0 and ctx.fighter_id % 1 == 0
    end
    local function same(ctx, owner)
        return owner ~= nil and valid(ctx) and ctx.session == owner.session and ctx.data == owner.data
            and ctx.fighter_id == owner.fighter_id
    end
    local function block(lease, reason)
        blocked = true
        if lease then retained[#retained + 1] = lease end
        return false, tostring(reason or "native operation unconfirmed")
    end
    local function retire(entry, ctx, reason)
        local ok, result, err = pcall(native.retire, entry.lease, ctx, reason)
        if not ok or result ~= true then return block(entry.lease, ok and err or result) end
        entry.session.close()
        if active == entry then active = nil end
        return true
    end
    local function discard(lease, ctx)
        local ok, result, err = pcall(native.discard_prepared, lease, ctx)
        if not ok or result ~= true then return block(lease, ok and err or result) end
        return true
    end
    local function command(fn)
        if blocked then return false, "native recovery required; no automatic retry" end
        if busy then return false, "operation in progress" end
        busy = true
        local results = table.pack(pcall(fn))
        busy = false
        if not results[1] then return false, tostring(results[2]) end
        return table.unpack(results, 2, results.n)
    end
    local function idle_context()
        local ctx, err = read_context()
        if not valid(ctx) then return nil, err or "offline training required" end
        if ctx.idle ~= true then return nil, "stop recording/playback before this operation" end
        return ctx
    end

    function self.state() return blocked and "blocked" or (active and "active" or "unloaded") end
    function self.snapshot() return active and active.session.snapshot() or nil end
    function self.last_choice() return remembered_fighter end
    local function load()
            local ctx, err = idle_context()
            if not ctx then return false, err end
            last_attempt = ctx
            if active and not same(ctx, active.owner) then return false, "retire previous training context first" end
            local candidate = make_session()
            local loaded, load_err = candidate.select(ctx.fighter_id)
            if not loaded then return false, load_err end
            if not candidate.has_saved_file() then
                candidate.close()
                return false, "selected configuration file is missing"
            end
            local ok, lease, prepare_err = pcall(native.prepare, candidate.snapshot(), ctx)
            if not ok or type(lease) ~= "table" then
                candidate.close()
                return false, ok and (prepare_err or "native preparation failed") or tostring(lease)
            end
            local fresh = read_context()
            if lease.guard_ready ~= true or not same(fresh, ctx) or fresh.idle ~= true then
                local cleaned, cleanup_err = discard(lease, fresh)
                candidate.close()
                return false, cleaned and "save protection or training context not ready" or cleanup_err
            end
            if active then
                local retired, retire_err = retire(active, fresh, "manual replacement; discard unsaved changes")
                if not retired then discard(lease, fresh); candidate.close(); return false, retire_err end
            end
            fresh = read_context()
            if not same(fresh, ctx) or fresh.idle ~= true then
                local cleaned, cleanup_err = discard(lease, fresh)
                candidate.close()
                return false, cleaned and "training changed before attachment" or cleanup_err
            end
            local entry = {session=candidate, lease=lease, owner=ctx}
            -- Publish ownership before attach, so a partial failure cannot lose its handle.
            active = entry
            local attached, result, attach_err = pcall(native.attach, lease, fresh)
            if not attached or result ~= true then
                local retired, retire_err = retire(entry, fresh, "partial attach rollback")
                return false, retired and tostring(attached and attach_err or result) or retire_err
            end
            remembered_fighter = ctx.fighter_id
            return true
    end
    function self.load() return command(load) end
    function self.save()
        return command(function()
            if not active then return false, "no manually loaded configuration" end
            local ctx, err = idle_context()
            if not ctx or not same(ctx, active.owner) then return false, err or "training context changed" end
            if active.session.needs_reload() then return false, "manual reload required after uncertain save" end
            local ok, document = pcall(native.capture, active.lease, ctx)
            if not ok then return false, tostring(document) end
            local fresh = read_context()
            if not same(fresh, active.owner) or fresh.idle ~= true then return false, "training changed during capture" end
            local staged, stage_err = active.session.stage(document)
            if not staged then return false, stage_err end
            return active.session.save()
        end)
    end
    function self.unload()
        return command(function()
            if not active then return true end
            local ctx, err = idle_context()
            if not ctx or not same(ctx, active.owner) then return false, err or "training context changed" end
            last_attempt = ctx
            return retire(active, ctx, "manual unload; discard unsaved changes")
        end)
    end
    function self.tick()
        return command(function()
            local ctx = read_context()
            if active then
                if same(ctx, active.owner) then return true end
                local retired, err = retire(active, ctx, "training or character changed; discard unsaved changes")
                if not retired then return false, err end
            end
            if not valid(ctx) then last_attempt = nil; return true end
            if ctx.fighter_id ~= remembered_fighter or ctx.idle ~= true or same(ctx, last_attempt) then return true end
            -- One entry-triggered request, not polling the file every frame on failure.
            return load()
        end)
    end
    return self
end

return M
