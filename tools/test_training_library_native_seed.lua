-- Models captured Init loss; native Duplicate behavior still needs game acceptance.
package.path="autorun/?.lua;"..package.path
local fixture=require("tools.fixtures.native_recording_runtime")
local accepted=require("tools.fixtures.native_recording_session_pre_seed")
local candidate=require("SF6CCTrainingLibrary/NativeRecordingSession")
local passed=0
local function test(name,fn) fn(); passed=passed+1; print("PASS "..name) end
local function setup(strategy,options)
    options=options or {}
    package.loaded["SF6CCTrainingLibrary/NativeRecordingSession"]=strategy
    local f=fixture({native_capacity=options.capacity or 8,expire_slot=52,expire_stage="Init"})
    if options.empty then
        for _,slot in ipairs(f.original) do
            slot.fields.Frame=0; slot.fields.IsValid=false; slot.fields.IsActive=false
            slot.fields.InputData.fields.Num=0; slot.fields.InputData.fields.buff=nil
        end
    end
    local count=0
    -- Model the captured length-based native deep copy, including a detached seed.
    local function duplicate(data)
        count=count+1
        if options.fail_copy==count then error("injected native seed duplicate failure") end
        local bank=data.fields.RecordSetting.fields.FighterDataList.items[1].fields.RecordSlots
        local slots={}
        for i,source in ipairs(bank.items) do
            if options.alias and count==3 and i>8 then slots[i]=slots[1]
            else slots[i]=f.obj(); slots[i]:call("DeepCopy",source) end
        end
        local result=f.obj({RecordSetting=f.obj({FighterDataList=f.array({f.obj({FighterID=28,
            RecordSlots=f.array(slots)})})})})
        result.call=function(self,name,...) assert(name=="Duplicate"); return duplicate(self,...) end
        return result
    end
    f.data.call=function(self,name) assert(name=="Duplicate"); return duplicate(self) end
    f.runtime.install_hooks()
    return f,function() return count end
end
test("captured slot52 two-to-zero Init loss blocks the accepted eight-slot path",function()
    local f=setup(accepted); local original=f.fighter.fields.RecordSlots
    f.tick()
    assert(f.runtime.state()=="unloaded" and f.fighter.fields.RecordSlots==original)
    assert(f.stats.error:find("slot 52 / init",1,true))
    assert(f.stats.error:find("refs=2",1,true) and f.stats.error:find("initialized{",1,true))
end)
test("candidate avoids per-slot Init and mounts eighty independent slots",function()
    local f,copies=setup(candidate); local original=f.fighter.fields.RecordSlots
    f.tick()
    assert(f.runtime.state()=="active",f.stats.error)
    assert(copies()==3,"unexpected native data copy count")
    local slots=f.fighter.fields.RecordSlots
    assert(slots:get_size()==80 and slots~=original)
    for i=0,79 do
        local s=slots:get_element(i)
        if i<8 then
            assert(s.fields.Frame==i+1 and s~=original:get_element(i))
        else
            assert(s.fields.Frame==0 and s.fields.InputData.fields.Num==0 and not s.fields.IsValid)
            assert(not s.fields.IsActive and s.fields.Weight==1 and s.fields.InputData.fields.buff:get_size()==3600)
        end
    end
    f.ctx.menu_closed=false
    f.option_arrow(1,9,true,function(page) assert(page.fields._ChildData:get_element(1).fields._SlotID==72) end)
    f.ctx.menu_closed=true; f.ctx.allowed=false; f.tick()
    assert(f.fighter.fields.RecordSlots==original and original:get_size()==8)
end)
test("existing eighty-slot native bank keeps the accepted two-copy path",function()
    local f,copies=setup(candidate,{capacity=80}); f.tick()
    assert(f.runtime.state()=="active",f.stats.error)
    assert(copies()==2)
    assert(f.fighter.fields.RecordSlots:get_element(79).fields.Frame==80)
end)
test("all-empty native eight-slot bank stays empty with private recording buffers",function()
    local f=setup(candidate,{empty=true}); f.tick()
    assert(f.runtime.state()=="active",f.stats.error)
    for i=0,79 do
        local slot=f.fighter.fields.RecordSlots:get_element(i)
        assert(slot.fields.Frame==0 and not slot.fields.IsValid)
        assert(slot.fields.InputData.fields.Num==0 and slot.fields.InputData.fields.buff:get_size()==3600)
    end
    for _,slot in ipairs(f.original) do assert(slot.fields.InputData.fields.buff==nil) end
end)
test("seed candidate waits for native recorder without copying or latching a failure",function()
    for _,field in ipairs({"ReqType","State"}) do
        local f,copies=setup(candidate)
        f.record.fields._gData.fields[field]=1
        f.tick(450)
        assert(copies()==0 and f.native_work.allocations==0 and not f.stats.logs)
        f.record.fields._gData.fields[field]=0; f.tick()
        assert(f.runtime.state()=="active",f.stats.error or "seed stayed blocked after idle")
    end
end)
for _,options in ipairs({{fail_copy=2},{fail_copy=3},{alias=true}}) do
    test("failed or aliasing native seed copy cannot publish partial data or retry",function()
        local f,copies=setup(candidate,options)
        local bank,rows=f.fighter.fields.RecordSlots,f.pages[1].fields._ChildData
        f.tick()
        assert(f.runtime.state()=="unloaded" and f.stats.error)
        assert(f.fighter.fields.RecordSlots==bank and f.pages[1].fields._ChildData==rows)
        local count=copies(); f.tick(450); assert(copies()==count)
    end)
end
package.loaded["SF6CCTrainingLibrary/NativeRecordingSession"]=accepted
print(passed.." native-seed candidate checks passed (fake SDK only)")
