local Bank = require("tools/training_record_bank/core")
local Native = require("tools/training_record_bank/native_array")
local function doc()
    local bank=assert(Bank.open(assert(Bank.empty(28))))
    bank.add_slot({name="sample",is_valid=true,is_active=true,weight=3,frame=3,
        input_buff={16,32,65535},fields={},input_fields={Cursor=0,State=1,cmd_type=0,
            negativeEdge=false,isLoop=false,IsForceStop=false}})
    return bank.snapshot()
end
local function fixture(opts)
    local count, releases, all=0,0,{}
    local function object(kind)
        count=count+1
        local o={kind=kind,id=count,refs=0,fields={},items={}}
        all[#all+1]=o
        local function live() assert(o.refs>0,"dead object accessed") end
        function o:add_ref() self.refs=self.refs+1 end
        function o:release() live(); releases=releases+1; if opts.release_error then error("release") end; self.refs=self.refs-1 end
        function o:get_reference_count() live(); return self.refs end
        function o:get_address() live(); return self.id end
        function o:get_size() live(); return self.size end
        function o:get_type_definition() live(); return {get_full_name=function() return self.kind end} end
        function o:get_field(k) live(); return self.fields[k] end
        function o:set_field(k,v)
            live(); self.fields[k]=v
            if type(v)=="table" and v.refs and not opts.no_owner then v.refs=v.refs+1 end
        end
        function o:get_element(i) live(); return self.items[i] end
        function o:call(name,v,index)
            live()
            if name=="Init" then
                local input=object("input"); input.refs=1; self.fields.InputData=input
            elseif name=="GetValue" then
                if opts.corrupt then return -1 end
                return self.items[v] or 0
            else
                assert(name=="SetValue(System.Object, System.Int32)")
                if opts.write_error then error("write") end
                local old=self.items[index]
                if type(old)=="table" and old.refs then old.refs=old.refs-1 end
                self.items[index]=v
                if type(v)=="table" and v.refs and not opts.no_owner then v.refs=v.refs+1 end
            end
        end
        return o
    end
    return {
        create_instance=function(kind) if opts.null then return nil end; return object(kind) end,
        create_managed_array=function(kind,n) local a=object(kind.."[]"); a.size=n; return a end,
        create_uint16=function(value) return value end,
    },function() return count,releases end
end
local api,counts=fixture({}); local lease=assert(Native.prepare(Bank,api,doc(),9))
assert(lease.guard_ready==false and lease.verify())
assert(lease.close() and not lease.close() and not pcall(lease.verify))
for _,change in ipairs({
    function(d) d.records[1].recording.input_buff[1]=65536 end,
    function(d) d.records[1].recording.fields.Unknown=1 end,
    function(d) d.records[1].recording.input_fields.Unknown=1 end,
    function(d) d.records[1].recording.input_fields.State=0.5 end,
    function(d) d.record_refs={{group="down",slot=1,record_id=1}} end,
}) do
    local d=doc(); change(d); api,counts=fixture({})
    assert(not Native.prepare(Bank,api,d,9)); assert(counts()==0)
end
api,counts=fixture({}); assert(not Native.prepare(Bank,api,doc(),10)); assert(counts()==0)
for _,option in ipairs({"null","write_error","no_owner"}) do
    api=fixture({[option]=true})
    local result,reason,failed=Native.prepare(Bank,api,doc(),9)
    assert(not result and reason and failed.state()=="failed" and not failed.close())
end
api=fixture({corrupt=true}); lease=assert(Native.prepare(Bank,api,doc(),9)); assert(not pcall(lease.verify))
assert(lease.state()=="failed" and not lease.close())
api,counts=fixture({release_error=true}); lease=assert(Native.prepare(Bank,api,doc(),9))
assert(not lease.close()); local _,before=counts(); assert(not lease.close()); local _,after=counts(); assert(before==after)
local long=doc(); local record=long.records[1]; record.recording.frame=3600; record.recording.input_buff={}
for i=1,3600 do record.recording.input_buff[i]=16 end
local second={id=2,name="second",enabled=true,weight=1,recording={frame=500,input_buff={},fields={},input_fields={}}}
for i=1,500 do second.recording.input_buff[i]=32 end
long.next_id=3; long.records[2]=second
api,counts=fixture({}); assert(not Native.prepare(Bank,api,long,9)); assert(counts()==0)
-- Live field binding still uses a fake SDK here; a real save/thread permit is
-- deliberately not supplied by this fixture or by the detached production API.
local function mount_fixture(options)
    local sdk=fixture(options or {})
    local target=sdk.create_instance("fighter"); target:add_ref()
    local original=sdk.create_managed_array("slot",8); original:add_ref()
    target:set_field("FighterID",28); target:set_field("RecordSlots",original)
    local prepared=assert(Native.prepare(Bank,sdk,doc(),9))
    local permit={guard_ready=true,allows=function() return true end}
    return prepared,target,original,permit,sdk
end
local target, original, permit
lease, target, original, permit = mount_fixture()
assert(lease.attach(target,permit))
assert(target:get_field("RecordSlots"):get_size()==9 and not lease.close())
assert(lease.detach(permit) and target:get_field("RecordSlots")==original)
assert(not lease.close() and lease.close(permit))
lease,target,original,permit=mount_fixture()
assert(not lease.attach(target,{guard_ready=false}) and target:get_field("RecordSlots")==original)
target:set_field("FighterID",19)
assert(not lease.attach(target,permit) and target:get_field("RecordSlots")==original and lease.close())
lease,target,original,permit=mount_fixture()
assert(lease.attach(target,permit))
permit.allows=function() return false end
assert(not lease.detach(permit) and lease.state()=="attached" and not lease.close(permit))
permit.allows=function() return true end
assert(lease.detach(permit) and lease.close(permit))
lease,target,original,permit=mount_fixture()
local set=target.set_field
function target:set_field(key,value)
    set(self,key,value)
    if key=="RecordSlots" and value~=original then error("setter threw after write") end
end
assert(not lease.attach(target,permit) and lease.state()=="attach_uncertain")
assert(lease.detach(permit) and target:get_field("RecordSlots")==original and lease.close(permit))
lease,target,original,permit=mount_fixture()
assert(lease.attach(target,permit))
target:set_field("RecordSlots",{get_address=function() return -99 end})
assert(not lease.detach(permit) and lease.state()=="failed" and not lease.close(permit))
print("PASS 18 native-array adapter cases (fake SDK; no engine capacity claim)")
