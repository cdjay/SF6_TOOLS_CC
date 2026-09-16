-- Load the actual entry with no SF6CC globals, old autoruns or func/ fallback.
local root = arg[1] or "."
local loaded, callbacks, errors = {}, {}, {}
local runtime_ticks,pager_ticks,hook_installs=0,0,0
local env = setmetatable({}, { __index = _G })
env._G = env
env.sdk = {}
env.thread = {}
env.log = {error=function(message) errors[#errors+1]=message end, warn=function() end, info=function() end}
env.re = {}
for _,event in ipairs({"on_application_entry", "on_pre_application_entry", "on_script_reset", "on_draw_ui"}) do
    env.re[event]=function(a,b) callbacks[#callbacks+1]={event=event,name=b and a or nil,fn=b or a} end
end
env.imgui = {tree_node=function() return false end, tree_pop=function() end}
env.json = {load_file=function() return nil end}
env.require = function(name)
    assert(name:match("^SF6CCTrainingLibrary/"), "legacy dependency: " .. name)
    if loaded[name]~=nil then return loaded[name] end
    if name=="SF6CCTrainingLibrary/NativeRecordingRuntime" then
        loaded[name]={new=function()
            return {install_hooks=function() hook_installs=hook_installs+1 end,
                tick=function() runtime_ticks=runtime_ticks+1 end,
                ui_tick=function() pager_ticks=pager_ticks+1 end,
                state=function() return "active" end,reset=function() end}
        end}
        return loaded[name]
    end
    local fn=assert(loadfile(root.."/autorun/"..name..".lua", "t", env))
    loaded[name]=fn() or true
    return loaded[name]
end
local entry=assert(loadfile(root.."/autorun/SF6CC_TrainingLibrary.lua", "t", env))
entry()
local count=#callbacks
assert(count>0, "standalone entry registered nothing")
entry()
assert(#callbacks==count, "entry registered duplicate owners")
assert(loaded["SF6CCTrainingLibrary/Records"])
assert(loaded["SF6CCTrainingLibrary/NativeLibraryTab"], "standalone package must include the deferred native library")
assert(not loaded["SF6CCTrainingLibrary/NativeMenu"], "unsafe subtab refresh must remain withdrawn")
assert(loaded["SF6CCTrainingLibrary/Library"] and loaded["SF6CCTrainingLibrary/Context"])
assert(loaded["SF6CCTrainingLibrary/NativeNoteEditor"],"native library must include its deferred name editor")
local state=assert(loaded["SF6CCTrainingLibrary/State"])
assert(type(state.tick_jobs)=="function", "no independent deferred job owner")
local safe_updates=0
local unsafe_updates=0
for _,callback in ipairs(callbacks) do
    if callback.event=="on_application_entry" then unsafe_updates=unsafe_updates+1 end
    if callback.event=="on_pre_application_entry" and callback.name=="LateUpdateBehavior"
        then
        safe_updates=safe_updates+1
    end
end
assert(safe_updates==2 and hook_installs==1,"one recording update owner plus one dormant native library update")
assert(unsafe_updates==0,"native recording lifecycle still runs outside pre LateUpdateBehavior")
local library=loaded["SF6CCTrainingLibrary/Library"].shared()
local ticks=0
library.has_pending=function() return true end
library.tick=function() ticks=ticks+1 end
for _,callback in ipairs(callbacks) do
    if callback.event=="on_pre_application_entry" then callback.fn() end
end
assert(ticks==1, "queued operation did not run without legacy autorun")
assert(runtime_ticks==1 and pager_ticks==1,"entry must drive lifecycle and pager even with manual jobs")
assert(env.SF6CC_NativeNotes==nil and env.GameState==nil and env.SF6CC_RuntimeSafety==nil)
local reloads=0
state.runtime.request_reload=function() reloads=reloads+1 end
library.loaded=true
loaded["SF6CCTrainingLibrary/Records"].get_context=function() return {fighter_id=28,fighter_name="Mai"} end
env.imgui.text=function() end
env.imgui.text_colored=function() end
env.imgui.combo=function() return false,1 end
env.imgui.same_line=function() end
env.imgui.small_button=function() return false end
env.imgui.button=function(label) return label=="重新加载分页" end
loaded["SF6CCTrainingLibrary/Panel"]()
assert(reloads==1,"visible reload button must delegate to runtime queue")
print("PASS standalone entry, private dependencies, one queue owner, no legacy globals")
