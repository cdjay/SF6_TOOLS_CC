-- REFramework can resolve autorun modules at load time, not at first deferred use.
local callbacks=false
local function object(fields)
    local value={fields=fields or {}}
    function value:get_field(key) return self.fields[key] end
    function value:get_address() return self end
    return value
end
local data=object({SelectMenu=object(),RecordSetting=object()})
local record=object({_tData=data})
function record:call(name) assert(name=="IsRecording" or name=="IsReplayNow"); return false end
local tm=object({_tData=data,_UIData=object(),_IsInit=true,_GameMode=1})
function tm:call(name) assert(name=="get_RecordFunc"); return record end
local objects={
    ["app.training.TrainingManager"]=tm,
    ["app.PauseManager"]=object({_CurrentPauseTypeBit=64}),
    ["app.network.NetworkManager"]=object(),
    ["app.bFlowManager"]=object({m_flow_work={_FlowMap={_ID=4}}}),
}
local env=setmetatable({sdk={get_managed_singleton=function(name) return objects[name] end}},{__index=_G})
local exports=0
local bank_size=8
local records={get_context=function() return {fighter_id=28} end,
    get_record_bank_size=function() return bank_size end,
    get_record_capacity=function() return 8 end,
    export_new=function() exports=exports+1; return true,"exported","test.json" end,
    list_configs=function() return {{path="test.json"}} end,
    read_config_metadata=function() return {fighter_id=28,title="Test"} end}
local loaded={
    ["SF6CCTrainingLibrary/TrainingConfigCompatibility"]={},
    ["SF6CCTrainingLibrary/CharacterNames"]=function(v) return v end,
    -- Shared() already imports Records while constructing the controller.
    ["SF6CCTrainingLibrary/Records"]=records,
}
env.require=function(name)
    if loaded[name] then return loaded[name] end
    assert(not callbacks,"autorun module unavailable from deferred callback: "..name)
    assert(name=="SF6CCTrainingLibrary/Context",name)
    loaded[name]=assert(loadfile("autorun/"..name..".lua","t",env))()
    return loaded[name]
end
local Library=assert(loadfile("autorun/SF6CCTrainingLibrary/Library.lua","t",env))()
local controller=Library.new(records,Library.runtime_context)
callbacks=true
local ok,ctx=pcall(Library.runtime_context)
assert(ok and ctx.allowed,"first deferred context failed: "..tostring(ctx))
assert(controller.request("export"),controller.status)
controller.tick()
assert(exports==1 and controller.status_ok,"first deferred export was silently blocked")
bank_size=80
local legacy=Library.runtime_context()
assert(legacy.allowed and legacy.bank_unsupported and legacy.slot_count==80 and legacy.error,
    "legacy bank must be identified for read-only menu presentation")
assert(not controller.request("export") and exports==1,"legacy bank must not write recordings")
bank_size=8
tm.fields._GameMode=2
assert(not Library.runtime_context().allowed,"preloading bypassed the training gate")
assert(not controller.request("clear"),"outside-training operation allowed")
print("PASS first deferred library context/export without editor preloading; outside-training gate retained")
