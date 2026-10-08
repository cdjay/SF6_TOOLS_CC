-- Observe the native training session without replacing its recording bank or menus.
local M = {}

local function address(value)
    return value and value:get_address()
end

function M.new(deps)
    local library, context = deps.library, deps.context
    local active, identity, generation, stopped = false, nil, 0, false
    local stable = 0
    -- Last context validated for the active session; menu text hooks read it
    -- instead of re-reading native training data on every native call.
    local last
    local self = {}

    -- Leaving training only cancels queued work. Recordings stay in the game's
    -- data and slot descriptions stay in memory per fighter.
    local function leave()
        if active or identity then library.cancel() end
        active, identity, stable, last = false, nil, 0, nil
    end

    function self.tick()
        if stopped then return end
        local ok, ctx = pcall(context)
        -- Each matchmaking attempt from training reports an online rule for about
        -- a second. Leaving here would restart the session on every attempt.
        if ok and type(ctx) == "table" and ctx.online_hold == true then return end
        if not ok or type(ctx) ~= "table" or not ctx.allowed
            or (ctx.error and not ctx.bank_unsupported)
            or not ctx.session or not ctx.data or not ctx.record_func or ctx.fighter_id == nil
            or (ctx.slot_count ~= 8 and not (ctx.bank_unsupported and ctx.slot_count > 8)) then
            leave()
            return
        end
        local key = table.concat({address(ctx.session), address(ctx.data),
            address(ctx.record_func), ctx.fighter_id}, ":")
        if key ~= identity then
            leave()
            identity = key
        end
        if not active then
            if ctx.busy ~= false or ctx.menu_closed ~= true or not deps.save_idle(ctx) then
                stable = 0
                return
            end
            stable = stable + 1
            if stable < 3 then return end
            active = true
            generation = generation + 1
            -- Never import on entry: the native eight slots already hold what
            -- the player left there. Only descriptions and selection follow P2.
            -- Missing descriptions are not worth stopping the session for.
            if library.restore_names then pcall(library.restore_names, ctx.fighter_id) end
        end
        last = ctx
    end

    function self.state() return stopped and "stopped" or (active and "active" or "unloaded") end
    function self.presentation_session() return active and not stopped and generation or nil end
    function self.context() return active and not stopped and last or nil end
    function self.generation() return generation end
    function self.reset()
        stopped = true
        library.abandon()
        active = false
    end
    return self
end

return M
