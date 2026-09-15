-- Experimental private seed for native length-based Duplicate; never mount it.
local M = {}
local SLOT = "app.training.TrainingData.TM_RecordSetting.SlotData"
local SET = "SetValue(System.Object, System.Int32)"
local function same(a,b) return a and b and a:get_address()==b:get_address() end
local function bank(data,id)
    local settings=assert(data:get_field("RecordSetting"))
    local fighters=assert(settings:get_field("FighterDataList"))
    local index=settings:call("GetFighterIndex",id)
    assert(type(index)=="number" and index>=0 and index<fighters:call("get_Count"),"seed fighter index")
    local fighter=assert(fighters:call("get_Item",index))
    assert(fighter:get_field("FighterID")==id,"seed fighter identity")
    return fighter,assert(fighter:get_field("RecordSlots"))
end
function M.build(api,data,id,capacity,own)
    assert(capacity==80,"unsupported seed capacity")
    local _,original=bank(data,id)
    assert(original:get_size()==8,"seed requires original eight slots")
    local seed=own(data:call("Duplicate"))
    assert(not same(seed,data),"seed aliases live training data")
    local fighter,source=bank(seed,id)
    assert(source:get_size()==8 and not same(source,original),"seed bank aliases live bank")
    local template,selected=assert(source:get_element(0)),false
    for i=0,7 do
        local slot=assert(source:get_element(i))
        assert(not same(slot,original:get_element(i)),"seed slot aliases live slot")
        if not selected and slot:get_field("IsValid") and slot:get_field("Frame")>0 then
            template,selected=slot,true
        end
    end
    -- Alias only detached seed references. Duplicate must produce independent
    -- SlotData/InputData/buff objects; the caller verifies all eighty before use.
    local expanded=own(api.create_managed_array(SLOT,capacity))
    for i=0,capacity-1 do expanded:call(SET,i<8 and source:get_element(i) or template,i) end
    fighter:set_field("RecordSlots",expanded)
    assert(same(fighter:get_field("RecordSlots"),expanded),"seed assignment readback")
    local working=own(seed:call("Duplicate"))
    assert(not same(working,data) and not same(working,seed),"working seed copy aliases source")
    local _,result=bank(working,id)
    assert(result:get_size()==capacity and not same(result,expanded),"native copy did not expand bank")
    assert(same(select(2,bank(data,id)),original),"seed changed live recording bank")
    return working,result
end
return M
