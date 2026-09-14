-- Load the actual entry with no SF6CC globals, old autoruns or func/ fallback.
local root = arg[1] or "."
local loaded, callbacks, errors = {}, {}, {}
local env = setmetatable({}, { __index = _G })
env._G = env
env.sdk = {}
env.thread = {}
env.log = {error=function(message) errors[#errors+1]=message end, warn=function() end, info=function() end}
env.re = {}
for _,event in ipairs({"on_application_entry", "on_pre_application_entry", "on_script_reset", "on_draw_ui"}) do
    env.re[event]=function(a,b) callbacks[#callbacks+1]={event=event,fn=b or a} end
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
assert(loaded["SF6CCTrainingLibrary/Records"] and loaded["SF6CCTrainingLibrary/NativeMenu"])
assert(loaded["SF6CCTrainingLibrary/Library"] and loaded["SF6CCTrainingLibrary/NativeNoteEditor"])
local state=assert(loaded["SF6CCTrainingLibrary/State"])
assert(type(state.tick_jobs)=="function", "no independent deferred job owner")
local library=loaded["SF6CCTrainingLibrary/Library"].shared()
local ticks=0
library.has_pending=function() return true end
library.tick=function() ticks=ticks+1 end
state.tick_jobs()
assert(ticks==1, "queued operation did not run without legacy autorun")
assert(env.SF6CC_NativeNotes==nil and env.GameState==nil and env.SF6CC_RuntimeSafety==nil)
print("PASS standalone entry, private dependencies, one queue owner, no legacy globals")
