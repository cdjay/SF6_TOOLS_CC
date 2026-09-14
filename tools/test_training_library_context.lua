local function obj(fields)
    return setmetatable(fields or {}, {__index={get_field=function(self,k) return rawget(self,k) end,
        get_address=function(self) return self end}})
end
local data=obj({SelectMenu=obj(),RecordSetting=obj()})
local recorder=obj({_tData=data})
local tm=obj({_IsInit=true,_GameMode=1,_tData=data,_UIData=obj(),call=function() return recorder end})
local rule=obj({GameMode=1})
local pause=obj({_CurrentPauseTypeBit=64})
local map={_ID=4}
local objects={
    ["app.training.TrainingManager"]=tm,
    ["app.PauseManager"]=pause,
    ["app.network.NetworkManager"]=obj({["<Session>k__BackingField"]=obj({
        ["<FGBattle>k__BackingField"]=obj({["<BattleRule>k__BackingField"]=rule})})}),
    ["app.bFlowManager"]=obj({m_flow_work=obj({_FlowMap=map})}),
}
local env=setmetatable({sdk={get_managed_singleton=function(name) return objects[name] end}}, {__index=_G})
local context=assert(loadfile("autorun/SF6CCTrainingLibrary/Context.lua","t",env))()
assert(context.is_training_allowed(),"offline context must not depend on legacy frame publisher")
for _,mode in ipairs({14,15,16,17,18}) do
    rule.GameMode=mode
    assert(not context.is_training_allowed(),"stale TrainingManager allowed online battle")
end
rule.GameMode=1
for _,mode in ipairs({0,2,3}) do tm._GameMode=mode; assert(not context.is_training_allowed()) end
tm._GameMode=1
for _,id in ipairs({9,10}) do map._ID=id; assert(not context.is_training_allowed()) end
map._ID=4
recorder._tData=obj(); assert(not context.is_training_allowed()); recorder._tData=data
tm._IsInit=false; assert(not context.is_training_allowed()); tm._IsInit=true
local network=objects["app.network.NetworkManager"]
objects["app.network.NetworkManager"]=nil; assert(not context.is_training_allowed())
objects["app.network.NetworkManager"]=network
rule.GameMode="unknown"; assert(not context.is_training_allowed()); rule.GameMode=1
assert(context.is_training_allowed())
assert(context.pause_open()==false)
pause._CurrentPauseTypeBit=2112; assert(context.pause_open()==false)
pause._CurrentPauseTypeBit=1; assert(context.pause_open()==true)
pause._CurrentPauseTypeBit=nil; assert(context.pause_open()==nil)
env.sdk.get_managed_singleton=function() error("unavailable") end
assert(not context.is_training_allowed() and context.pause_open()==nil)
print("PASS standalone offline gate, online transition, replay/hub denial, owner and unknown-state checks")
