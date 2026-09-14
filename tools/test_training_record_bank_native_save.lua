local Projection=require("tools/training_record_bank/native_save_projection")
local function fixture()
    local next_id,releases,copies,thread_id=0,0,0,1
    local fault
    local function object(fields,items)
        next_id=next_id+1
        local o={fields=fields or {},items=items,id=next_id,refs=1}
        function o:add_ref() self.refs=self.refs+1 end
        function o:release() assert(self.refs>0); self.refs=self.refs-1; releases=releases+1 end
        function o:get_address() assert(self.refs>0); return self.id end
        function o:get_field(k) assert(self.refs>0); return self.fields[k] end
        function o:set_field(k,v) assert(self.refs>0); self.fields[k]=v end
        function o:get_size() return #self.items end
        function o:get_element(i) return self.items[i+1] end
        function o:call(method,i)
            if method=="get_Count" then return #self.items end
            if method=="get_Item" then return self.items[i+1] end
            error("unexpected native method "..method)
        end
        return o
    end
    local function clone(value)
        if type(value)~="table" then return value end
        local fields,items={},nil
        for k,v in pairs(value.fields) do fields[k]=clone(v) end
        if value.items then
            items={}
            for i,v in ipairs(value.items) do items[i]=clone(v) end
        end
        return object(fields,items)
    end
    local function bank(n)
        local slots={}
        for i=1,n do slots[i]=object({Frame=i,InputData=object({buff=object(nil,{16,32})})}) end
        return object(nil,slots)
    end
    local other=object({FighterID=0,RecordSlots=bank(8),Unrelated=123})
    local selected=object({FighterID=28,RecordSlots=bank(8),Unrelated=456})
    local data=object({SelectChildIndex=7,Difficulty=2,RecordSetting=object({FighterDataList=object(nil,{other,selected})})})
    function data:call(method)
        assert(method=="Duplicate")
        copies=copies+1
        if fault=="throw" then error("native copy failed") end
        if fault=="live" then return self end
        local copy=clone(self)
        local list=copy.fields.RecordSetting.fields.FighterDataList
        if fault=="id" then list.items[2].fields.FighterID=19 end
        if fault=="alias" then list.items[2].fields.RecordSlots=selected.fields.RecordSlots end
        return copy
    end
    local manager=object({_tData=data})
    return {manager=manager,data=data,selected=selected,other=other,bank=bank,
        threads={get_id=function() return thread_id end},set_thread=function(v) thread_id=v end,
        fault=function(v) fault=v end,stats=function() return copies,releases end}
end
local function selected(value)
    return value:get_field("RecordSetting"):get_field("FighterDataList"):call("get_Item",1)
end
local count=0
local function test(name,fn) local ok,err=pcall(fn); assert(ok,name..": "..tostring(err)); count=count+1 end
test("independent projection preserves latest unrelated settings and both fighter identities",function()
    local f=fixture(); local original=f.selected:get_field("RecordSlots")
    local p=assert(Projection.prepare(f.manager,28,f.threads)); assert(not p.guard_ready)
    local live9=f.bank(9); f.selected:set_field("RecordSlots",live9)
    f.data:set_field("Difficulty",5); f.data:set_field("SelectChildIndex",8)
    local out=assert(p.project())
    assert(out~=f.data and out:get_field("Difficulty")==5 and out:get_field("SelectChildIndex")==7)
    assert(selected(out):get_field("FighterID")==28 and selected(out):get_field("RecordSlots"):get_size()==8)
    assert(selected(out):get_field("RecordSlots")~=original)
    local other=out:get_field("RecordSetting"):get_field("FighterDataList"):call("get_Item",0)
    assert(other:get_field("FighterID")==0 and other:get_field("Unrelated")==123)
    assert(f.selected:get_field("RecordSlots")==live9 and live9:get_size()==9)
    assert(p.close_unpublished() and not p.project())
end)
for _,failure in ipairs({"id","alias","live","throw"}) do
    test("native copy "..failure.." uses original fallback and retains uncertain roots",function()
        local f=fixture(); local p=assert(Projection.prepare(f.manager,28,f.threads))
        f.selected:set_field("RecordSlots",f.bank(9)); f.fault(failure)
        local out,err=p.project()
        assert(out and err and p.state()=="blocked")
        assert(selected(out):get_field("FighterID")==28 and selected(out):get_field("RecordSlots"):get_size()==8)
        local copies=f.stats(); assert(p.project()==out and f.stats()==copies and not p.close_unpublished())
    end)
end
test("snapshot count stays bounded across repeated saves",function()
    local f=fixture(); local p=assert(Projection.prepare(f.manager,28,f.threads))
    assert(p.project()); assert(p.project())
    local fallback,err=p.project(); assert(fallback and err and p.state()=="blocked")
    for _=1,20 do assert(p.project()==fallback) end
    assert(f.stats()==3 and p.close_unpublished())
end)
test("wrong thread does not clone write or release",function()
    local f=fixture(); local p=assert(Projection.prepare(f.manager,28,f.threads))
    local copies,releases=f.stats(); f.set_thread(2)
    local fallback,err=p.project(); assert(fallback and err and not p.close_unpublished())
    local c,r=f.stats(); assert(c==copies and r==releases)
    f.set_thread(1); assert(p.close_unpublished())
end)
test("changed owner returns baseline without reading new owner",function()
    local f=fixture(); local p=assert(Projection.prepare(f.manager,28,f.threads))
    f.manager:set_field("_tData",nil)
    assert(p.project() and p.state()=="blocked" and f.stats()==1)
    assert(p.close_unpublished())
end)
test("published saves cannot be released on training exit alone",function()
    local f=fixture(); local p=assert(Projection.prepare(f.manager,28,f.threads))
    assert(not p.mark_returned(f.data))
    assert(p.mark_returned(assert(p.project())))
    local _,before=f.stats(); assert(not p.close_unpublished())
    local _,after=f.stats(); assert(before==after)
end)
test("already expanded baseline refuses preparation",function()
    local f=fixture(); f.selected:set_field("RecordSlots",f.bank(9))
    local out,err,failed=Projection.prepare(f.manager,28,f.threads)
    assert(not out and err and failed.state()=="failed" and f.stats()==0)
end)
print("PASS "..count.." native save projection cases (fake SDK; no native publication)")
