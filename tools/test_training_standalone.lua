-- Load the actual entry with no SF6CC globals, old autoruns or func/ fallback.
local root = arg[1] or "."
local loaded, callbacks, errors = {}, {}, {}
local excluded_globals = { SF6CC_NativeNotes = true, GameState = true, SF6CC_RuntimeSafety = true }
local env = setmetatable({}, { __index = function(_, key)
    if excluded_globals[key] then return nil end
    return _G[key]
end })
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
assert(loaded["SF6CCTrainingLibrary/NativeEightRuntime"])
assert(not loaded["SF6CCTrainingLibrary/NativeRecordingRuntime"],"expansion runtime loaded")
assert(loaded["SF6CCTrainingLibrary/NativeLibraryTab"], "standalone package must include the deferred native library")
assert(not loaded["SF6CCTrainingLibrary/NativeMenu"], "unsafe subtab refresh must remain withdrawn")
assert(loaded["SF6CCTrainingLibrary/Library"] and loaded["SF6CCTrainingLibrary/Context"])
assert(loaded["SF6CCTrainingLibrary/NativeNoteEditor"],"native library must include its deferred name editor")
assert(loaded["SF6CCTrainingLibrary/NativeSlotNames"],"native lists must include the deferred slot-name installer")
local state=assert(loaded["SF6CCTrainingLibrary/State"])
assert(state.runtime and type(state.runtime.presentation_session)=="function")
local safe_updates=0
local unsafe_updates=0
for _,callback in ipairs(callbacks) do
    if callback.event=="on_application_entry" then unsafe_updates=unsafe_updates+1 end
    if callback.event=="on_pre_application_entry" and callback.name=="LateUpdateBehavior"
        then
        safe_updates=safe_updates+1
    end
end
assert(safe_updates==3,"one observer, one dormant native library update and one deferred slot-name installer")
assert(unsafe_updates==0,"native recording lifecycle still runs outside pre LateUpdateBehavior")
local library=loaded["SF6CCTrainingLibrary/Library"].shared()
local ticks=0
library.has_pending=function() return true end
library.tick=function() ticks=ticks+1 end
for _=1,29 do
    for _,callback in ipairs(callbacks) do
        if callback.event=="on_pre_application_entry" then callback.fn() end
    end
end
assert(ticks==0,"queued operation ran before the new session settled")
for _,callback in ipairs(callbacks) do
    if callback.event=="on_pre_application_entry" then callback.fn() end
end
assert(ticks==0,"unavailable native eight-slot context ran queued work")
assert(env.SF6CC_NativeNotes==nil and env.GameState==nil and env.SF6CC_RuntimeSafety==nil)
assert(state.runtime.request_reload==nil,"extension page reload remains reachable")
print("PASS standalone native eight-slot entry and private dependencies, no expansion runtime")
