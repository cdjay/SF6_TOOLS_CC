-- Accepted recording runtime and shared manual/remembered configuration queue.
if _G.SF6CC_NATIVE_MOUNT_RETAINED then return end
local State=require("SF6CCTrainingLibrary/State")
if State.started then return end
State.started=true
local state={stopped=false,active_ticks=0,allocations={}}
_G.SF6CC_NATIVE_MOUNT_RETAINED=state
local TAG="[SF6CC-RuntimeWithManualLibrary] "
local Library=require("SF6CCTrainingLibrary/Library")
local Runtime=require("SF6CCTrainingLibrary/NativeRecordingRuntime")
local library=Library.shared()
local api=setmetatable({},{__index=sdk})
for _,name in ipairs({"create_instance","create_instance_global","create_managed_array"}) do
    api[name]=function(...)
        assert(#state.allocations<2048,"diagnostic retention limit reached; restart required")
        local value=sdk[name](...)
        if value then state.allocations[#state.allocations+1]={value=value,kind=tostring(select(1,...)),factory=name} end
        return value
    end
end
local in_update=false
local runtime=Runtime.new({api=api,threads=thread,library=library,
    in_ui_update=function() return in_update end,context=Library.runtime_context,
    trace=function(event,values)
        local parts={event,"thread_id="..tostring(thread.get_id())}
        for key,value in pairs(values.detail or {}) do parts[#parts+1]=key.."="..tostring(value) end
        for i,entry in ipairs(values.entries) do
            parts[#parts+1]=string.format("entry%d=%s issued=%d completed=%d readers=%d released=%s",
                i,entry.phase,entry.issued,entry.completed,entry.readers,tostring(entry.released))
            parts[#parts+1]=string.format("entry%d_addresses manager=%s data=%s baseline=%s",i,
                tostring(entry.manager_address),tostring(entry.data_address),tostring(entry.baseline_address))
        end
        log.info("[SF6CC-SaveFence] "..table.concat(parts,"; "))
    end,
    save_idle=function(ctx)
        local manager=sdk.get_managed_singleton("app.storage.SaveManager")
        return manager and manager:call("get_IsBusy")==false
            and ctx.session:get_field("_IsSaveReq")==false
    end,
    log=function(message) log.error(TAG..tostring(message)) end})
state.runtime=runtime
State.runtime=runtime
local ok,err=pcall(runtime.install_hooks)
if not ok then state.stopped=true; log.error(TAG.."HOOKS FAILED "..tostring(err)); return end
function State.tick_jobs()
    if state.stopped or runtime.state()~="active" or not library.has_pending() then return end
    assert(in_update,"configuration job outside the accepted update scope")
    library.tick()
end
log.info(TAG.."ARMED; remembered P2 configuration imports after runtime attachment; shared configuration queue")
re.on_pre_application_entry("LateUpdateBehavior",function()
    if state.stopped then return end
    in_update=true
    local success,detail=xpcall(function()
        runtime.tick()
        State.tick_jobs()
        runtime.ui_tick()
        local phase=runtime.state()
        if phase~=state.last_phase then
            log.info(TAG.."PHASE "..tostring(phase).." allocations="..#state.allocations)
            state.last_phase=phase; state.active_ticks=0
        end
        if phase=="active" then
            state.active_ticks=state.active_ticks+1
            if state.active_ticks==180 then log.info(TAG.."SURVIVED active runtime for180 updates") end
        end
    end,debug.traceback)
    in_update=false
    if not success then
        state.stopped=true
        log.error(TAG.."STOPPED; restart required, no automatic cleanup/retry: "..tostring(detail))
    end
end)
local draw_panel=require("SF6CCTrainingLibrary/Panel")
re.on_draw_ui(function()
    if state.stopped then return end
    if imgui.tree_node("木人库（独立插件）") then
        local drawn,why=pcall(draw_panel)
        imgui.tree_pop()
        if not drawn then library.status_ok=false; library.status="管理面板显示失败，详情见日志"; log.error(TAG..tostring(why)) end
    end
end)
re.on_script_reset(function()
    state.stopped=true
    local success,detail=pcall(runtime.reset)
    if not success then log.error(TAG.."RESET FAILED "..tostring(detail)) end
end)

-- Register the native library module; it stays dormant until training is ready.
local tab_ok,tab_error=pcall(require,"SF6CCTrainingLibrary/NativeLibraryTab")
if not tab_ok then log.error("[NativeLibraryTab] Load failed; manual library unchanged: "..tostring(tab_error)) end
