-- Entry integration: native eight-slot mode never installs hooks or replaces banks.
package.path = "autorun/?.lua;" .. package.path
local Runtime = require("SF6CCTrainingLibrary/NativeEightRuntime")
local Library = require("SF6CCTrainingLibrary/Library")

local function object(id)
    return {get_address=function() return id end,
        get_field=function(_,name) assert(name=="_IsSaveReq"); return false end}
end
local session, data, recorder = object(1), object(2), object(3)
local ctx={allowed=true,session=session,data=data,record_func=recorder,
    fighter_id=28,slot_count=8,busy=false,menu_closed=true}
local counts={autoload=0,imports=0,saves=0,cancels=0}
local records={
    get_record_capacity=function() return ctx.slot_count end,
    get_slot_name=function() return "" end,
    reset_slot_names=function() end,
    list_configs=function() return {{path="mai.json",filename="mai.json"}} end,
    read_config_metadata=function() return {fighter_id=28,record_slots=8,title="Mai"} end,
    begin_import=function(path)
        counts.imports=counts.imports+1
        return true,"imported",path,nil,{kind="import",written=8,cleared=0,reversals=30,apply_state="applied"}
    end,
    save_current=function(path)
        counts.saves=counts.saves+1
        return true,"saved",path
    end,
}
local library=Library.new(records,function() return ctx end,{
    load=function() return { ["28"]="mai.json" } end,
    save=function() return true end,
})
local autoload=library.autoload
library.autoload=function(...)
    counts.autoload=counts.autoload+1
    return autoload(...)
end
local cancel=library.cancel
library.cancel=function(...)
    counts.cancels=counts.cancels+1
    return cancel(...)
end
local State={}
local callbacks={}
local sdk={get_managed_singleton=function(kind)
    assert(kind=="app.storage.SaveManager")
    return {call=function() return false end}
end}
local env=setmetatable({sdk=sdk,log={error=function(e) error(e) end}}, {__index=_G})
env._G=env
env.imgui={tree_node=function() return false end}
env.re={
    on_pre_application_entry=function(name,fn) assert(name=="LateUpdateBehavior"); callbacks.tick=fn end,
    on_draw_ui=function(fn) callbacks.draw=fn end,
    on_script_reset=function(fn) callbacks.reset=fn end,
}
env.require=function(name)
    if name=="SF6CCTrainingLibrary/State" then return State end
    if name=="SF6CCTrainingLibrary/Library" then
        return {shared=function() return library end,runtime_context=function() return ctx end}
    end
    if name=="SF6CCTrainingLibrary/NativeEightRuntime" then return Runtime end
    if name=="SF6CCTrainingLibrary/Panel" then return function() end end
    if name=="SF6CCTrainingLibrary/NativeLibraryTab" then return true end
    if name=="SF6CCTrainingLibrary/NativeSlotNames" then return true end
    error("Unexpected dependency: "..name)
end
local entry=assert(loadfile("autorun/SF6CC_TrainingLibrary.lua","t",env))
entry(); entry()
assert(State.runtime and callbacks.tick and callbacks.draw and callbacks.reset)
assert(sdk.hook==nil and sdk.create_managed_array==nil and sdk.create_instance_global==nil)

local function tick(n)
    for _=1,n do callbacks.tick() end
end
tick(32)
assert(State.runtime.state()=="active" and counts.autoload==1 and counts.imports==1)
tick(100)
assert(counts.autoload==1 and counts.imports==1,"autoload repeated in one session")

assert(library.request("save"))
ctx.menu_closed=false; tick(10)
assert(counts.saves==0 and library.has_pending())
ctx.menu_closed=true; tick(1)
assert(counts.saves==1 and not library.has_pending())

-- Matchmaking from training: each search attempt reports an online battle rule
-- for about a second while the training scene stays intact (2026-10-09 log).
-- A hold must neither restart the session nor autoload again.
local live,generation,cancels=ctx,State.runtime.presentation_session(),counts.cancels
assert(library.request("save"))
ctx={allowed=false,online_hold=true}; tick(60)
assert(counts.saves==1 and library.has_pending(),"a job ran during the online hold")
ctx=live; tick(1)
assert(counts.saves==2 and not library.has_pending(),"a queued job did not resume after the hold")
for _=1,5 do
    ctx={allowed=false,online_hold=true}; tick(60)
    ctx=live; tick(40)
end
assert(State.runtime.state()=="active" and State.runtime.presentation_session()==generation,
    "matchmaking hold restarted the session")
assert(counts.autoload==1 and counts.imports==1 and counts.cancels==cancels,
    "matchmaking hold re-imported or cancelled work")

ctx.slot_count=80; tick(1)
ctx.error="当前录像不是8栏位"; ctx.bank_unsupported=true
tick(3)
assert(State.runtime.state()=="active" and State.runtime.presentation_session(),
    "legacy bank must not hide the native library tab")
assert(counts.autoload==1 and counts.imports==1,"legacy bank must not autoload")
assert(not library.request("save") and counts.saves==2,"unsupported bank was modified")
ctx.slot_count=8; ctx.error=nil; ctx.bank_unsupported=nil
ctx.fighter_id=1; tick(35)
assert(State.runtime.state()=="active" and counts.autoload==2)
assert(counts.imports==1,"wrong fighter auto-imported")

ctx.allowed=false; tick(1)
assert(State.runtime.state()=="unloaded")
callbacks.reset(); tick(1)
assert(State.runtime.state()=="stopped")
print("PASS native eight-slot entry: no bank/menu hooks, gated autoload, save, character switch, unsupported-bank refusal")
