package.path="autorun/?.lua;"..package.path
local Bank=require("tools/training_record_bank/core")
local Native=require("tools/training_record_bank/native_array")
local Mount=require("tools/training_record_bank/native_menu_mount")
local Lifecycle=require("tools/training_record_bank/native_lifecycle")
local MENU="app.training.TrainingMenuData"
local SET="SetValue(System.Object, System.Int32)"
local function fixture()
    local next_id,releases=0,0
    local function object(kind,fields)
        next_id=next_id+1
        local o={kind=kind,fields=fields or {},items={},refs=1,id=next_id}
        local function live() assert(o.refs>0,"released native access") end
        function o:add_ref() self.refs=self.refs+1 end
        function o:release() live(); self.refs=self.refs-1; releases=releases+1 end
        function o:get_reference_count() live(); return self.refs end
        function o:get_address() live(); return self.id end
        function o:get_size() live(); return self.size end
        function o:get_field(key) live(); return self.fields[key] end
        function o:set_field(key,value)
            live()
            local old=self.fields[key]
            if type(old)=="table" and old.refs then old.refs=old.refs-1 end
            self.fields[key]=value
            if type(value)=="table" and value.refs then value.refs=value.refs+1 end
            if self.fail_field==key then self.fail_field=nil; error("setter failed after write") end
        end
        function o:get_element(i) live(); return self.items[i] end
        function o:get_type_definition() return {get_full_name=function() return kind end} end
        function o:call(method,value,index)
            live()
            if method=="set_MessageID(System.Guid)" then self.fields._MessageID=value
            elseif method=="set_GuideMessage(System.Guid)" then self.fields._GuideMessage=value
            elseif method=="Init" then self.fields.InputData=object("input")
            elseif method=="GetValue" then return self.items[value] or 0
            elseif method=="GetFighterIndex" then assert(value==28); return 0
            elseif method=="get_Count" then return self.size
            elseif method=="get_Item" then return self.items[value]
            else
                assert(method==SET)
                local old=self.items[index]
                if type(old)=="table" and old.refs then old.refs=old.refs-1 end
                self.items[index]=value
                if type(value)=="table" and value.refs then value.refs=value.refs+1 end
            end
        end
        return o
    end
    local function array(items)
        local a=object("array"); a.size=#items
        for i,v in ipairs(items) do a:call(SET,v,i-1) end
        return a
    end
    local api={
        create_instance=function(kind) local o=object(kind); o.refs=0; return o end,
        create_managed_array=function(kind,n) local o=object(kind.."[]"); o.size=n; o.refs=0; return o end,
        create_uint16=function(v) return v end,
        find_type_definition=function(kind)
            if kind=="System.Guid" then
                return {get_field=function() return {get_data=function() return {NewGuid=function()
                    next_id=next_id+1; local id=next_id
                    return {read_byte=function(_,i) return i==0 and id%255+1 or 0 end}
                end} end} end}
            end
            assert(kind==MENU)
            return {get_fields=function()
                local fields={}
                for _,key in ipairs({"_SlotID","_FuncType","_Title","_ChildData"}) do
                    fields[#fields+1]={get_name=function() return key end,is_static=function() return false end}
                end
                fields[#fields+1]={get_name=function() error("static should not be copied") end,is_static=function() return true end}
                return fields
            end}
        end,
    }
    local function page(kind,slot_kind)
        local rows={object(MENU,{_FuncType=kind==107 and 0 or 130,_Type=kind==107 and 9 or 0})}
        for i=0,7 do rows[#rows+1]=object(MENU,{_FuncType=slot_kind,_SlotID=i,_Title=77}) end
        rows[#rows+1]=object(MENU,{_FuncType=0,_Type=4})
        rows[#rows+1]=object(MENU,{_FuncType=202})
        rows[#rows+1]=object(MENU,{_FuncType=203})
        local original=array(rows)
        return object(MENU,{_FuncType=kind,_ChildData=original}),original
    end
    local record,record_rows=page(107,118)
    local play,play_rows=page(108,131)
    local library=object(MENU,{_FuncType=999})
    local selector=object(MENU,{_FuncType=106,_ChildData=array({record,play,library})})
    local root=object(MENU,{_FuncType=4,_ChildData=array({selector})})
    local original=object("slots"); original.size=8
    local fighter=object("fighter",{FighterID=28,RecordSlots=original})
    local settings=object("settings",{FighterDataList=array({fighter})})
    local data=object("data",{RecordSetting=settings})
    local manager=object("manager",{_tData=data,_UIData=object("ui",{_MenuData=array({root})})})
    local bank=assert(Bank.open(assert(Bank.empty(28))))
    bank.add_slot({name="saved",is_valid=true,is_active=true,weight=3,frame=2,
        input_buff={16,32},fields={},input_fields={}})
    local recording=assert(Native.prepare(Bank,api,bank.snapshot(),9))
    local permit={guard_ready=true,allows=function() return true end}
    return {api=api,manager=manager,recording=recording,permit=permit,
        record=record,play=play,record_rows=record_rows,play_rows=play_rows,
        fighter=fighter,original=original,selector=selector,library=library,array=array,
        releases=function() return releases end}
end
local passed=0
local function test(name,fn)
    local ok,err=pcall(fn); assert(ok,name..": "..tostring(err)); passed=passed+1
end
local function prepare(f) return Mount.prepare(f.api,f.manager,f.recording,28,f.permit) end
test("eight rows per page preserve both footer settings and all nine recordings",function()
    local f=fixture(); local m=assert(prepare(f))
    assert(f.record:get_field("_ChildData")==f.record_rows)
    assert(m.attach() and not m.close())
    assert(f.fighter:get_field("RecordSlots"):get_size()==9)
    for _,pair in ipairs({{f.record,f.record_rows,118},{f.play,f.play_rows,131}}) do
        local rows=pair[1]:get_field("_ChildData")
        assert(rows:get_size()==12)
        assert(rows:get_element(0):get_field("_FuncType")==345,"pager must reuse the native header position")
        assert(rows:get_element(10)==pair[2]:get_element(10) and rows:get_element(11)==pair[2]:get_element(11))
        for i=0,7 do assert(rows:get_element(i+1)==pair[2]:get_element(i+1),"native slot position moved") end
        assert(rows:get_element(9)==pair[2]:get_element(pair[3]==118 and 9 or 0))
        local pager=rows:get_element(0)
        assert(pager:get_field("_Type")==1 and pager:get_field("_ChildData"):get_size()==2)
        assert(m.navigate(pager,pair[1],1))
        rows=pair[1]:get_field("_ChildData")
        assert(rows:get_size()==12 and rows:get_element(0)==pager)
        assert(rows:get_element(1):get_field("_SlotID")==8)
        assert(rows:get_element(1):get_field("_FuncType")==pair[3])
        assert(rows:get_element(1):get_field("_Title")==77)
        for i=2,8 do
            assert(rows:get_element(i):get_field("_Type")==9)
            assert(rows:get_element(i):get_field("IsCantFocus")==true)
        end
        assert(rows:get_element(10)==pair[2]:get_element(10) and rows:get_element(11)==pair[2]:get_element(11))
        assert(m.navigate(pager,pair[1],0))
        assert(pair[1]:get_field("_ChildData"):get_size()==12)
    end
    assert(f.selector:get_field("_ChildData"):get_element(2)==f.library)
    assert(m.retire() and f.fighter:get_field("RecordSlots")==f.original)
    assert(f.record:get_field("_ChildData")==f.record_rows and f.play:get_field("_ChildData")==f.play_rows)
    assert(m.close() and not m.close() and not m.attach())
end)
test("no save protection refuses preparation without live writes",function()
    local f=fixture(); f.permit.guard_ready=false
    assert(not prepare(f)); assert(f.fighter:get_field("RecordSlots")==f.original)
end)

test("silent function-type copy failure reports readback without attaching",function()
    local f=fixture(); local create=f.api.create_instance
    f.api.create_instance=function(kind)
        local row=create(kind); local set=row.set_field
        function row:set_field(key,value)
            if key=="_FuncType" then self.fields[key]=0; return end
            return set(self,key,value)
        end
        return row
    end
    local m,err=prepare(f)
    assert(not m and err:find("field=_FuncType expected=118 (number) actual=0 (number)",1,true))
    assert(f.fighter:get_field("RecordSlots")==f.original)
    assert(f.record:get_field("_ChildData")==f.record_rows)
end)

test("silent ninth slot assignment failure reports stage and actual value",function()
    local f=fixture(); local create=f.api.create_instance
    f.api.create_instance=function(kind)
        local row=create(kind); local set=row.set_field
        function row:set_field(key,value)
            if key=="_SlotID" and value==8 then return end
            return set(self,key,value)
        end
        return row
    end
    local m,err=prepare(f)
    assert(not m and err:find("slot assignment mismatch: field=_SlotID expected=8 (number) actual=7 (number)",1,true))
    assert(f.fighter:get_field("RecordSlots")==f.original)
    assert(f.play:get_field("_ChildData")==f.play_rows)
end)

test("empty field enumeration is distinguished from a failed setter",function()
    local f=fixture()
    f.api.find_type_definition=function() return {get_fields=function() return {} end} end
    local m,err=prepare(f)
    assert(not m and err:find("ninth row field enumeration empty",1,true))
    assert(f.fighter:get_field("RecordSlots")==f.original)
end)

test("paging never reallocates or modifies the native recording bank",function()
    local f=fixture(); local m=assert(prepare(f)); assert(m.attach())
    local bank=f.fighter:get_field("RecordSlots")
    local first=bank:get_element(0); local frame=first:get_field("Frame")
    first:set_field("IsActive",true); first:set_field("Weight",7)
    local rows=f.record:get_field("_ChildData"); local pager=rows:get_element(0)
    f.api.create_instance=function() error("navigation allocated") end
    f.api.create_managed_array=f.api.create_instance
    for i=1,10 do assert(m.navigate(pager,f.record,i%2)) end
    assert(f.fighter:get_field("RecordSlots")==bank and bank:get_element(0)==first)
    assert(first:get_field("IsActive")==true and first:get_field("Weight")==7 and first:get_field("Frame")==frame)
    assert(m.retire() and m.close())
end)

test("pager rejects a foreign parent and reports page ranges",function()
    local f=fixture(); local m=assert(prepare(f)); assert(m.attach())
    local pager=f.record:get_field("_ChildData"):get_element(0)
    local key=require("SF6CCTrainingLibrary/NativeRecordingPager").key(pager:get_field("_MessageID"))
    assert(m.text(key)=="页码" and m.pager_info(pager).label:find("1-8",1,true))
    assert(not m.navigate(pager,f.play,1))
    assert(m.navigate(pager,f.record,1) and m.pager_info(pager).label:find("9-9",1,true))
    assert(not m.navigate(pager,f.record,-1) and not m.navigate(pager,f.record,2))
    assert(m.retire() and m.text(key)==nil and not m.navigate(pager,f.record) and m.close())
end)

test("partial page switch failure can retire every owned page array",function()
    local f=fixture(); local m=assert(prepare(f)); assert(m.attach())
    local pager=f.record:get_field("_ChildData"):get_element(0)
    f.record.fail_field="_ChildData"
    assert(not pcall(m.navigate,pager,f.record,1))
    assert(m.retire() and f.record:get_field("_ChildData")==f.record_rows and m.close())
end)

test("native layouts without the reusable separator fail before attaching",function()
    local f=fixture(); f.record_rows:get_element(9):set_field("_Type",0)
    local m,err=prepare(f)
    assert(not m and err:find("recording separator missing",1,true))
    assert(f.fighter:get_field("RecordSlots")==f.original)
end)
test("noncontiguous row IDs reject without modifying pages",function()
    local f=fixture(); f.play_rows:get_element(5):set_field("_SlotID",0)
    assert(not prepare(f)); assert(f.record:get_field("_ChildData")==f.record_rows)
end)
test("changed training owner refuses mount",function()
    local f=fixture(); local m=assert(prepare(f)); f.manager:set_field("_tData",nil)
    assert(not m.attach() and m.state()=="prepared")
    assert(f.fighter:get_field("RecordSlots")==f.original and m.close())
end)
test("menu rebuilt before attachment refuses mount",function()
    local f=fixture(); local m=assert(prepare(f)); f.record:set_field("_ChildData",f.array({}))
    assert(not m.attach() and f.fighter:get_field("RecordSlots")==f.original and m.close())
end)
test("partial setter failure restores both pages and recordings",function()
    local f=fixture(); local m=assert(prepare(f)); f.play.fail_field="_ChildData"
    assert(not m.attach() and m.state()=="attach_uncertain" and not m.attach())
    assert(m.retire() and f.record:get_field("_ChildData")==f.record_rows)
    assert(f.play:get_field("_ChildData")==f.play_rows and f.fighter:get_field("RecordSlots")==f.original)
    assert(m.close())
end)
test("retirement denied on wrong thread leaves arrays rooted",function()
    local f=fixture(); local m=assert(prepare(f)); assert(m.attach())
    f.permit.allows=function(stage) return stage~="menu_retire" end
    local releases=f.releases()
    assert(not m.retire() and m.state()=="attached" and not m.close() and f.releases()==releases)
    f.permit.allows=function() return true end
    assert(m.retire() and m.close())
end)
test("retire old rooted owners after native release clears current data",function()
    local f=fixture(); local m=assert(prepare(f)); assert(m.attach())
    f.manager:set_field("_tData",nil)
    assert(m.retire() and m.close())
end)
test("external menu replacement blocks without clobber or release",function()
    local f=fixture(); local m=assert(prepare(f)); assert(m.attach())
    local other=f.array({}); f.play:set_field("_ChildData",other)
    local releases=f.releases()
    assert(not m.retire() and m.state()=="failed" and not m.retire() and not m.close())
    assert(f.play:get_field("_ChildData")==other and f.releases()==releases)
end)
test("restoration is not permission to dispose cached native views",function()
    local f=fixture(); local m=assert(prepare(f)); assert(m.attach() and m.retire())
    f.permit.allows=function(stage) return stage~="menu_dispose" end
    local releases=f.releases()
    assert(not m.close() and m.state()=="retired" and f.releases()==releases)
    f.permit.allows=function() return true end
    assert(m.close())
end)
test("worker exit restores real mount modules only on update thread and keeps disposal separate",function()
    local f=fixture()
    local current_thread,consumers_done=1,false
    f.permit.allows=function() return current_thread==1 end
    local m=assert(prepare(f))
    local life=Lifecycle.new({get_id=function() return current_thread end})
    local token=assert(life.watch(f.manager:get_address(),m,{
        can_retire=function(facts) return facts.release_post==true end,
        can_dispose=function() return consumers_done end,
    }))
    assert(m.attach())
    current_thread=2
    life.notify(token,"save_pre"); life.notify(token,"save_post")
    current_thread=3
    life.notify(token,"save_data_pre"); life.notify(token,"save_data_post")
    current_thread=4
    life.notify(token,"release_pre"); life.notify(token,"release_post")
    assert(not life.tick() and m.state()=="attached")
    assert(f.fighter:get_field("RecordSlots"):get_size()==9)
    current_thread=1
    assert(life.tick() and m.state()=="retired")
    assert(f.fighter:get_field("RecordSlots")==f.original and f.play:get_field("_ChildData")==f.play_rows)
    consumers_done=true
    assert(life.tick() and life.state()=="closed" and m.state()=="closed")
end)
print("PASS "..passed.." native mount integration cases (fake SDK; not live acceptance)")
