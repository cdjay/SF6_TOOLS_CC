-- Training-only runtime integration. Hooks notify; native writes stay on UpdateBehavior.
local Session = require("SF6CCTrainingLibrary/NativeRecordingSession")
local Pager = require("SF6CCTrainingLibrary/NativeRecordingPager")
local Names = require("SF6CCTrainingLibrary/NativeRecordingNames")
local ReversalRecordings = require("SF6CCTrainingLibrary/NativeReversalRecordings")
local M = {}
local MAX_RETAINED = 4
local function same(a, b) return a and b and a:get_address() == b:get_address() end

function M.new(deps)
    local api, threads, library = deps.api, deps.threads, deps.library
    local entries, active, attempted, stopped, ready = {}, nil, nil, false, false
    local ticks, owner_thread, warned = 0, nil, false
    local hook_error, save_generation = nil, 0
    local self = {}
    local function report(message)
        library.status_ok, library.status = false, "录像栏位扩展暂停：" .. tostring(message)
        if deps.log then deps.log(tostring(message)) end
    end
    local function find(address)
        for i = #entries, 1, -1 do
            local entry = entries[i]
            if entry.phase ~= "closed" and entry.manager:get_address() == address then return entry end
        end
    end
    local function context()
        local ok, ctx = pcall(deps.context)
        return ok and ctx or { allowed = false }
    end
    local function matches(entry, ctx)
        return ctx and ctx.allowed and not ctx.error and same(ctx.session, entry.manager)
            and same(ctx.data, entry.data) and ctx.fighter_id == entry.fighter_id
    end
    local function already_attempted(ctx)
        return attempted and same(attempted.session, ctx.session) and same(attempted.data, ctx.data)
            and attempted.fighter_id == ctx.fighter_id
    end
    function self.install_hooks()
        local function method(name, signature)
            return assert(assert(api.find_type_definition(name)):get_method(signature), signature)
        end
        -- Resolve all required signatures before installing anything that can mount data.
        local save = method("app.training.TrainingManager", "SaveSaveData")
        local release = method("app.training.TrainingManager", "Release")
        local finish = method("app.storage.SaveDataController", "FinishSave")
        local enum = assert(api.find_type_definition("via.storage.saveService.SaveResult"))
        local success = assert(enum:get_field("Success")):get_data(nil)
        if type(success) ~= "number" then success = success:get_field("value__") end
        assert(type(success) == "number", "save result enum unavailable")
        local pager = Pager.new(api, threads, function() return active end, function()
            local ctx = context()
            return active ~= nil and matches(active, ctx) and ctx.menu_closed == false
        end, report)
        pager.install()
        local names=Names.new(api,threads,function() return active end,function()
            local ctx=context()
            return active~=nil and matches(active,ctx) and ctx.menu_closed==false
        end,library,report)
        local name_ok,name_err=pcall(names.install)
        if not name_ok then report("名称显示接口不可用："..tostring(name_err)) end
        local reversal_picker = ReversalRecordings.new(api, threads, function() return active end, function()
            if stopped then return false end
            local ctx = context()
            return active ~= nil and matches(active, ctx) and ctx.menu_closed == false
        end, report, library)
        local reversal_ok, reversal_err = pcall(reversal_picker.install)
        if not reversal_ok then report("反击录像列表扩展不可用：" .. tostring(reversal_err)) end
        local function hook(target, before, after)
            api.hook(target, function(args)
                local ok, value = pcall(before, args)
                if not ok then hook_error = tostring(value) end
                return ok and value or nil
            end, function(retval)
                local ok, value = pcall(after, retval)
                if not ok then hook_error = tostring(value); return retval end
                return value
            end)
        end
        hook(save, function(args)
            save_generation = save_generation + 1
            local storage = threads.get_hook_storage()
            local entry = find(api.to_int64(args[2]))
            storage.sf6cc_save_entry = entry
            if entry then entry.readers = entry.readers + 1 end
        end, function(retval)
            local entry = threads.get_hook_storage().sf6cc_save_entry
            if not entry then return retval end
            local result = retval
            if api.to_int64(retval) == entry.data:get_address() and entry.baseline then
                entry.issued = entry.issued + 1
                result = api.to_ptr(entry.baseline:get_address())
            end
            entry.readers = entry.readers - 1
            return result
        end)
        hook(release, function(args)
            threads.get_hook_storage().sf6cc_release_entry = find(api.to_int64(args[2]))
        end, function(retval)
            local entry = threads.get_hook_storage().sf6cc_release_entry
            if entry then entry.released = true end
            return retval
        end)
        hook(finish, function(args)
            local storage = threads.get_hook_storage()
            storage.sf6cc_finish = nil
            if #entries == 0 then return end
            local controller = api.to_managed_object(args[2])
            if not controller or controller:get_field("saveKey") ~= "TRAINING_SAVE_DATA" then return end
            local saved = controller:get_field("saveDataIns")
            local list = saved and saved:get_field("List")
            if not list then return end
            local count = list:call("get_Count")
            if type(count) ~= "number" or count < 0 or count > 64 then return end
            local owned = {}
            for i = 0, count - 1 do
                local value = list:call("get_Item", i)
                if value then owned[value:get_address()] = true end
            end
            local batch = {}
            for _, entry in ipairs(entries) do
                if entry.baseline and owned[entry.baseline:get_address()] and entry.readers == 0
                    and entry.issued > entry.completed then batch[#batch + 1] = { entry, entry.issued } end
            end
            storage.sf6cc_finish = batch
        end, function(retval)
            local batch = threads.get_hook_storage().sf6cc_finish
            if batch and (api.to_int64(retval) & 0xFFFFFFFF) == success then
                for _, pair in ipairs(batch) do pair[1].completed = math.max(pair[1].completed, pair[2]) end
            end
            return retval
        end)
        ready = true
    end
    function self.tick()
        if stopped or not ready then return end
        if hook_error then
            local error_message = hook_error
            hook_error = nil
            self.reset(); report(error_message)
            return
        end
        owner_thread = owner_thread or threads.get_id()
        assert(threads.get_id() == owner_thread, "runtime update thread changed")
        ticks = ticks + 1
        if ticks % 15 ~= 0 then return end
        local ctx = context()
        if active and (active.released or not matches(active, ctx)) then
            library.cancel()
            local ok, err = active.retire()
            if not ok then report(err); return end
            active = nil
            if library.reset_slot_names then library.reset_slot_names() end
        end
        for i = #entries, 1, -1 do
            if entries[i].can_close and entries[i].can_close() then
                entries[i].close(); table.remove(entries, i)
            end
        end
        if not ctx.allowed or ctx.error or not ctx.session or not ctx.data then attempted = nil; return end
        if active or ctx.busy ~= false or ctx.menu_closed ~= true or library.has_pending() then return end
        if already_attempted(ctx) then return end
        if deps.save_idle and not deps.save_idle(ctx) then return end
        if #entries >= MAX_RETAINED then
            if not warned then warned = true; report("保存任务尚未释放，请重新启动游戏") end
            return
        end
        attempted = { session = ctx.session, data = ctx.data, fighter_id = ctx.fighter_id }
        local generation = save_generation
        local entry, err, failed = (deps.prepare or Session.prepare)(api, threads, ctx, ready)
        if not entry then
            if failed then entries[#entries + 1] = failed end
            library.expansion_error = err
            report(err); return
        end
        local fresh = context()
        if generation ~= save_generation or not matches(entry, fresh) or fresh.busy ~= false
            or fresh.menu_closed ~= true or (deps.save_idle and not deps.save_idle(fresh)) then
            entry.discard()
            report("准备期间环境或保存状态改变，未挂载；请重新进入训练场")
            return
        end
        entries[#entries + 1], active = entry, entry
        local attached, why = entry.attach()
        if not attached then report(why); stopped = true; return end
        library.expansion_error = nil
        if library.reset_slot_names then library.reset_slot_names() end
        library.status_ok, library.status = true, "录像栏位已扩展至 " .. Session.CAPACITY .. " 个"
        if library.autoload then library.autoload(ctx.fighter_id) end
    end
    function self.reset()
        stopped = true
        library.cancel()
        if owner_thread and threads.get_id() ~= owner_thread then report("请冷启动游戏完成卸载"); return end
        if active then
            local ok, err = active.retire()
            if not ok then report(err .. "；请冷启动游戏"); return end
            active = nil
            if library.reset_slot_names then library.reset_slot_names() end
        end
        -- Do not drop counted roots for outstanding save readers during Lua reset.
        for _, entry in ipairs(entries) do
            if entry.can_close and entry.can_close() then entry.close() end
        end
    end
    function self.state() return active and active.phase or (stopped and "stopped" or "unloaded") end
    return self
end
return M
