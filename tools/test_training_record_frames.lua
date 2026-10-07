-- Read current P2 scalar lengths only: no input buffers, exports or native writes.
package.path="autorun/?.lua;"..package.path
local function object(fields)
    return {get_field=function(_,key)
        assert(key~="InputData" and key~="ReversalSetting","frame labels must not read recording buffers/reversals")
        return fields[key]
    end,set_field=function() error("presentation wrote native data") end}
end
local function collection(items)
    return {call=function(_,name,index) assert(name=="get_Item"); return items[index] end,
        get_size=function() return items.size end}
end
local fighter=28
local selected={get_field=function(_,key) assert(key=="FighterID"); return fighter end}
local players=collection({[0]=object({FighterID=1}),[1]=selected})
local slots={size=8}
for i=0,7 do slots[i]=object({IsValid=true,Frame=0}) end
slots[0]=object({IsValid=true,Frame=55})
slots[1]=object({IsValid=true,Frame=167})
slots[5]=object({IsValid=false,Frame=999})
slots[7]=object({IsValid=1,Frame=262})
local other_slots={size=8}
for i=0,7 do other_slots[i]=object({IsValid=true,Frame=90+i}) end
local records=collection({[28]=object({RecordSlots=collection(slots)}),[26]=object({RecordSlots=collection(other_slots)})})
local data=object({SelectMenu=object({PlayerDatas=players}),RecordSetting=object({FighterDataList=records})})
local func=object({_tData=data})
local manager=object({_tData=data})
manager.call=function(_,name) assert(name=="get_RecordFunc"); return func end
local present=true
sdk={get_managed_singleton=function(name) assert(name=="app.training.TrainingManager"); return present and manager or nil end}
json={dump_file=function() error("frame labels must not write files") end,load_file=function() error("frame labels must not read files") end}
local module=dofile("autorun/SF6CCTrainingLibrary/Records.lua")
local s=assert(module.get_record_frames())
assert(s.fighter_id==28 and #s.frames==8 and s.frames[1]==55 and s.frames[2]==167)
assert(s.frames[6]==0 and s.frames[8]==262)
slots[0]=object({IsValid=true,Frame=170})
assert(s.frames[1]==55 and module.get_record_frames().frames[1]==170)
for _,bad in ipairs({-1,0.5,"55"}) do
    slots[0]=object({IsValid=true,Frame=bad}); assert(module.get_record_frames().frames[1]==false)
end
slots[0]=nil; assert(module.get_record_frames().frames[1]==false)
slots[0]={get_field=function() error("read failed") end}
assert(module.get_record_frames().frames[1]==false)
fighter=26; s=assert(module.get_record_frames())
assert(s.fighter_id==26 and #s.frames==8 and s.frames[1]==90)
fighter=28; slots.size=80
assert(module.get_record_frames()==nil,"old expanded bank must not be presented as native eight slots")
present=false; assert(module.get_record_frames()==nil,"unavailable bank must not look like empty slots")
print("PASS current P2 frame snapshot: native eight slots, unsupported-bank refusal, no IO/buffers/writes")
