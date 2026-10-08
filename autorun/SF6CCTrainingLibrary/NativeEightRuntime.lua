-- Observe the native training session without replacing its recording bank or menus.
local M = {}

local function address(value)
    return value and value:get_address()
end

function M.new(deps)
    local library, context = deps.library, deps.context
    local active, identity, generation, stopped = false, nil, 0, false
    local stable, age, autoloaded = 0, 0, false
    local self = {}

    local function leave()
        if active or identity then
            library.cancel()
            if library.reset_slot_names then library.reset_slot_names() end
        end
        active, identity, stable, age, autoloaded = false, nil, 0, 0, false
    end

    function self.tick()
        if stopped then return end
        local ok, ctx = pcall(context)
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
            age = 0
        end
        if not autoloaded and not ctx.bank_unsupported then
            age = age + 1
            if age >= 30 and ctx.busy == false and ctx.menu_closed == true
                and deps.save_idle(ctx) then
                autoloaded = true
                if library.reset_slot_names then library.reset_slot_names() end
                if library.autoload then library.autoload(ctx.fighter_id) end
            end
        end
    end

    function self.state() return stopped and "stopped" or (active and "active" or "unloaded") end
    function self.presentation_session() return active and not stopped and generation or nil end
    function self.generation() return generation end
    function self.reset()
        stopped = true
        library.abandon()
        active = false
    end
    return self
end

return M
