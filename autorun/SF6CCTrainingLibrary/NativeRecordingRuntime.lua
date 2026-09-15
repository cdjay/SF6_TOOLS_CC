-- Bank/menu lifecycle and deferred page rebuilds use pre LateUpdateBehavior.
local Session = require("SF6CCTrainingLibrary/NativeRecordingSession")
local Menu = require("SF6CCTrainingLibrary/NativeRecordingMenu")
local Pager = require("SF6CCTrainingLibrary/NativeRecordingPager")
local Names = require("SF6CCTrainingLibrary/NativeRecordingNames")
local ReversalRecordings = require("SF6CCTrainingLibrary/NativeReversalRecordings")
local SaveCompletion = require("SF6CCTrainingLibrary/NativeSaveCompletion")
local M = {}
local MAX_RETAINED = 4
local function same(a, b) return a and b and a:get_address() == b:get_address() end

function M.new(deps)
    local api, threads, library = deps.api, deps.threads, deps.library
    local in_ui_update=assert(deps.in_ui_update,"native runtime requires a safe update scope")
    local entries, active, attempted, stopped, ready = {}, nil, nil, false, false
    local ticks, owner_thread, warned = 0, nil, false
    local hook_error, save_generation, release_generation = nil, 0, 0
    local presentation_generation = 0
    local reload_request, reload_blocked
    local candidate, stable_checks = nil, 0
    local pager
    local saves=SaveCompletion.new()
    local self = {}
    local trace_count=0
    local function trace(event,detail,inspect)
        if not deps.trace or trace_count>=48 or #entries==0 then return end
        trace_count=trace_count+1
        local states={}
        for i,entry in ipairs(entries) do
            states[i]={phase=entry.phase,issued=entry.issued,completed=entry.completed,
                readers=entry.readers,released=entry.released}
        end
        local ok,err=pcall(function()
            for i,entry in ipairs(entries) do
                states[i].manager_address=entry.manager:get_address()
                states[i].data_address=entry.data:get_address()
                states[i].baseline_address=entry.baseline and entry.baseline:get_address() or 0
            end
            if inspect then inspect(detail) end
        end)
        if not ok then detail.detail_error=tostring(err):match("[^\r\n]+") end
        -- Optional scalar-only diagnosis; failure cannot affect native save flow.
        pcall(deps.trace,event,{detail=detail,entries=states})
    end
    local function report(message)
        library.status_ok, library.status = false, "录像栏位扩展暂停：" .. (tostring(message):match("[^\r\n]+") or "未知错误")
        if deps.log then deps.log(tostring(message)) end
    end
    local function restart_status()
        library.status_ok, library.status = false, "分页恢复已停止，请完全退出并重启游戏；不要继续重试或重置脚本"
    end
    local function block_reload(message)
        reload_blocked, reload_request = true, nil
        report(message)
        restart_status()
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
    local function clear_candidate() candidate, stable_checks = nil, 0 end
    local function layout_ready(ctx)
        local valid, pages = Menu.validate_native(ctx.session)
        if not valid then
            clear_candidate()
            library.status_ok, library.status = true, "正在等待原生录像菜单就绪，将自动加载分页"
            return false
        end
        local unchanged = candidate and matches(candidate, ctx)
        for i, page in ipairs(pages) do
            local old = candidate and candidate.pages[i]
            unchanged = unchanged and old and same(page.node, old.node) and same(page.original, old.original)
        end
        stable_checks = unchanged and stable_checks + 1 or 1
        candidate = { manager=ctx.session, data=ctx.data, fighter_id=ctx.fighter_id, pages=pages }
        return stable_checks >= 3
    end
    function self.request_reload()
        if reload_blocked or stopped or not ready then restart_status(); return false end
        if reload_request then return false end
        local ctx = context()
        if not ctx.allowed or ctx.error or not ctx.session or not ctx.data or ctx.fighter_id == nil then
            report("请先进入离线训练场"); return false
        end
        if ctx.busy ~= false or library.has_pending() then
            report("请先停止录制、播放并等待当前配置操作完成"); return false
        end
        reload_request = { manager = ctx.session, data = ctx.data, fighter_id = ctx.fighter_id }
        library.status_ok, library.status = true, "分页重载已排队，请关闭游戏暂停菜单"
        return true
    end
    function self.install_hooks()
        local function method(name, signature)
            return assert(assert(api.find_type_definition(name)):get_method(signature), signature)
        end
        -- Resolve all required signatures before installing anything that can mount data.
        local save = method("app.training.TrainingManager", "SaveSaveData")
        local release = method("app.training.TrainingManager", "Release")
        local finish = method("app.storage.SaveDataController", "FinishSave")
        local start = method("app.storage.SaveDataController", "StartSaveDirectSlot(System.Int32, System.String)")
        local enum = assert(api.find_type_definition("via.storage.saveService.SaveResult"))
        local success = assert(enum:get_field("Success")):get_data(nil)
        if type(success) ~= "number" then success = success:get_field("value__") end
        assert(type(success) == "number", "save result enum unavailable")
        pager = Pager.new(api, threads, function() return active end, function()
            if stopped then return false end
            local ctx = context()
            return active ~= nil and matches(active, ctx) and ctx.menu_closed == false
        end, report, function() return library.has_pending() end, function()
            if stopped then return false end
            -- Native layout queries precede the menu-open flag. Read-only
            -- presentation still requires the same live training session.
            local ctx=context()
            return active~=nil and matches(active,ctx)
        end)
        pager.install()
        local names=Names.new(api,threads,function() return active end,function()
            if stopped then return false end
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
        local function save_snapshot(controller)
            local saved=controller:get_field("saveDataIns")
            local list=saved and saved:get_field("List")
            if not list then return nil end
            local count=list:call("get_Count")
            if type(count)~="number" or count<0 or count>64 then return nil end
            local snapshot={container=saved:get_address(),items={}}
            for i=0,count-1 do
                local value=list:call("get_Item",i)
                if not value then return nil end
                snapshot.items[#snapshot.items+1]=value:get_address()
            end
            return snapshot
        end
        hook(start,function(args)
            local storage=threads.get_hook_storage()
            storage.sf6cc_save_start=nil
            if #entries==0 then return end
            local controller=api.to_managed_object(args[2])
            if not controller then return end
            storage.sf6cc_save_start={raw=args[2],frame=saves.begin(threads.get_id(),controller:get_address(),
                controller:get_field("saveKey")=="TRAINING_SAVE_DATA")}
        end,function(retval)
            local storage=threads.get_hook_storage()
            local pending=storage.sf6cc_save_start
            storage.sf6cc_save_start=nil
            if not pending then return retval end
            local snapshot
            local ok,err=pcall(function()
                if pending.frame.training then snapshot=save_snapshot(api.to_managed_object(pending.raw)) end
            end)
            local started=(api.to_int64(retval)&0xFF)~=0
            saves.end_start(pending.frame,snapshot,ok and started)
            if not ok then error(err) end
            trace("save_handoff",{id=pending.frame.id,controller_address=pending.frame.controller,
                saved_container_address=snapshot and snapshot.container or 0,
                count=snapshot and #snapshot.items or 0,tickets=#pending.frame.tickets,started=started})
            return retval
        end)
        hook(save, function(args)
            save_generation = save_generation + 1
            local storage = threads.get_hook_storage()
            local entry = find(api.to_int64(args[2]))
            storage.sf6cc_save_entry = entry
            if entry then entry.readers = entry.readers + 1 end
            trace("save_pre",{matched=entry~=nil})
        end, function(retval)
            local entry = threads.get_hook_storage().sf6cc_save_entry
            if not entry then return retval end
            local result = retval
            if api.to_int64(retval) == entry.data:get_address() and entry.baseline then
                saves.issue(threads.get_id(),entry)
                result = api.to_ptr(entry.baseline:get_address())
            end
            entry.readers = entry.readers - 1
            trace("save_post",{substituted=result~=retval},function(detail)
                detail.input_address=api.to_int64(retval)
                detail.output_address=api.to_int64(result)
            end)
            return result
        end)
        hook(release, function(args)
            local entry = find(api.to_int64(args[2]))
            threads.get_hook_storage().sf6cc_release_entry = entry
            if entry then entry.releasing = true end
        end, function(retval)
            local entry = threads.get_hook_storage().sf6cc_release_entry
            if entry then
                entry.released = true
                release_generation = release_generation + 1
            end
            trace("release_post",{matched=entry~=nil})
            return retval
        end)
        hook(finish, function(args)
            local storage = threads.get_hook_storage()
            storage.sf6cc_finish = nil
            if #entries == 0 then return end
            local controller = api.to_managed_object(args[2])
            if not controller then trace("finish_pre",{reason="no_controller"}); return end
            local key=controller:get_field("saveKey")
            if key ~= "TRAINING_SAVE_DATA" then trace("finish_pre",{reason="other_key",key=key}); return end
            local saved = controller:get_field("saveDataIns")
            local list = saved and saved:get_field("List")
            if not list then trace("finish_pre",{reason=saved and "no_list" or "no_saved_data"}); return end
            local count = list:call("get_Count")
            if type(count) ~= "number" or count < 0 or count > 64 then trace("finish_pre",{reason="invalid_count",count=count}); return end
            local snapshot=save_snapshot(controller)
            if not snapshot then trace("finish_pre",{reason="invalid_snapshot"}); return end
            local batch=saves.capture(controller:get_address(),snapshot,entries)
            storage.sf6cc_finish = batch
            trace("finish_pre",{reason="matched_list",count=count,matches=#batch},function(detail)
                detail.controller_address=controller:get_address()
                detail.saved_container_address=saved:get_address()
                for i=0,math.min(count,8)-1 do
                    local value=list:call("get_Item",i)
                    local prefix="saved"..i.."_"
                    detail[prefix.."address"]=value and value:get_address() or 0
                    if value then
                        local td=value:get_type_definition()
                        local kind=td and td:get_full_name() or "unavailable"
                        detail[prefix.."type"]=kind
                        if kind=="app.training.TrainingData" then
                            local setting=value:get_field("RecordSetting")
                            local fighters=setting and setting:get_field("FighterDataList")
                            local size=fighters and fighters:call("get_Count")
                            if type(size)=="number" and size>=0 and size<=64 then
                                for j=0,size-1 do
                                    local fighter=fighters:call("get_Item",j)
                                    local id=fighter and fighter:get_field("FighterID")
                                    for _,entry in ipairs(entries) do
                                        if id==entry.fighter_id then
                                            local slots=fighter:get_field("RecordSlots")
                                            detail[prefix.."fighter"..id.."_capacity"]=slots and slots:get_size() or 0
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end, function(retval)
            local storage=threads.get_hook_storage()
            local batch = storage.sf6cc_finish
            storage.sf6cc_finish=nil
            if batch and (api.to_int64(retval) & 0xFFFFFFFF) == success then
                saves.complete(batch)
            end
            trace("finish_post",{result=api.to_int64(retval) & 0xFFFFFFFF,success=success,
                matches=batch and #batch or 0})
            return retval
        end)
        ready = true
    end
    function self.ui_tick()
        if stopped or not ready or not pager then return end
        pager.tick()
    end
    function self.tick()
        if stopped or not ready then return end
        assert(in_ui_update(),"native lifecycle outside pre LateUpdateBehavior")
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
        if reload_request and not matches(reload_request, ctx) then
            reload_request = nil; report("环境已改变，分页重载已取消")
        end
        if active and (active.released or not matches(active, ctx)) then
            if pager then pager.cancel() end
            if active.retire_failed_released == active.released then return end
            library.cancel()
            local ok, err, deferred = active.retire()
            trace("retire",{ok=ok,deferred=deferred})
            if not ok then
                if not deferred then active.retire_failed_released = active.released; report(err) end
                return
            end
            active = nil
            attempted = nil
            reload_blocked, reload_request = nil, nil
            clear_candidate()
            if library.reset_slot_names then library.reset_slot_names() end
        end
        for i = #entries, 1, -1 do
            if entries[i].can_close and entries[i].can_close() then
                trace("close",{entry=i})
                entries[i].close(); table.remove(entries, i)
            end
        end
        if reload_blocked then return end
        if not ctx.allowed or ctx.error or not ctx.session or not ctx.data then
            attempted = nil; clear_candidate(); return
        end
        if ctx.busy ~= false or library.has_pending() then
            clear_candidate()
            if reload_request then reload_request = nil; report("正在录制、播放或处理配置，分页重载已取消") end
            return
        end
        if ctx.menu_closed ~= true then clear_candidate(); return end
        if deps.save_idle and not deps.save_idle(ctx) then clear_candidate(); return end
        local manual_reload = reload_request ~= nil
        if active then
            reload_request = nil
            local called, ok, detail, deferred = pcall(active.reload_menu)
            if called and deferred then return end
            if not called or not ok then block_reload(called and detail or ok)
            elseif manual_reload or detail == true then
                library.status_ok, library.status = true, "分页已自动恢复，录像和配置未修改"
            end
            return
        end
        if already_attempted(ctx) and not manual_reload then return end
        if not manual_reload and not layout_ready(ctx) then return end
        reload_request = nil
        clear_candidate()
        if #entries >= MAX_RETAINED then
            if not warned then warned = true; block_reload("保存任务尚未释放，请重新启动游戏") end
            return
        end
        attempted = { session = ctx.session, data = ctx.data, fighter_id = ctx.fighter_id }
        local generation = save_generation
        local entry, err, failed, deferred = (deps.prepare or Session.prepare)(api, threads, ctx, ready)
        if not entry then
            -- Only the allocation-free session preflight may defer. Construction
            -- errors keep their existing no-retry/fail-closed behavior.
            if deferred == true and failed == nil then
                attempted = nil
                clear_candidate()
                library.status_ok, library.status = true, "等待原生录像器空闲后自动加载分页"
                return
            end
            -- Preflight has no counted roots or native readers to retain.
            if failed and not failed.preflight_failed then entries[#entries + 1] = failed end
            library.expansion_error = err
            if manual_reload or (failed and failed.preflight_failed) then block_reload(err)
            else report(err) end
            return
        end
        local fresh = context()
        if generation ~= save_generation or not matches(entry, fresh) or fresh.busy ~= false
            or fresh.menu_closed ~= true or (deps.save_idle and not deps.save_idle(fresh)) then
            entry.discard()
            local message = "准备期间环境或保存状态改变，未挂载；请重新进入训练场"
            if manual_reload then block_reload(message) else report(message) end
            return
        end
        entries[#entries + 1], active = entry, entry
        local attached, why = entry.attach()
        if not attached then report(why); stopped = true; return end
        presentation_generation = presentation_generation + 1
        library.expansion_error = nil
        if not manual_reload and library.reset_slot_names then library.reset_slot_names() end
        library.status_ok, library.status = true, manual_reload and "分页已重新加载，未导入配置，当前栏位名称保留"
            or ("录像栏位已扩展至 " .. Session.CAPACITY .. " 个")
        if not manual_reload and library.autoload then library.autoload(ctx.fighter_id) end
    end
    function self.reset()
        stopped = true
        if pager then pager.cancel() end
        reload_request = nil
        if not in_ui_update() or (owner_thread and threads.get_id()~=owner_thread) then
            library.abandon()
            if #entries>0 then report("脚本已停止；请完全退出并重启游戏，勿继续重载原生菜单") end
            return
        end
        library.cancel()
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
    function self.state() return stopped and "stopped" or (active and active.phase or "unloaded") end
    function self.generation() return release_generation end
    -- Scalar identity only: UI consumers must not retain native session objects.
    -- Release invalidates it before the next throttled lifecycle tick can retire.
    function self.presentation_session()
        if not stopped and active and active.phase == "active"
            and not active.releasing and not active.released then
            return presentation_generation
        end
        return nil
    end
    return self
end
return M
